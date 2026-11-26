#!/usr/bin/env bash
# The nightly server backup (CR-25B B5 part 1), run by
# .github/workflows/nightly-backup.yml. Can also be run by hand.
#
# 1. Dumps the database as three files (roles, schema, data), like
#    backups/20261115_*, and downloads every file in the business-media
#    Storage bucket.
# 2. Packs them into simplek-backup-YYYY-MM-DD.tar.gz and encrypts it with
#    gpg (AES-256, passphrase from BACKUP_PASSPHRASE). Only the encrypted
#    file ever leaves this machine; the plain copy is deleted first.
# 3. Uploads it to the private Cloudflare R2 bucket: daily/, and on the 1st
#    of the month also monthly/. Keeps the newest 30 daily and 12 monthly
#    copies and deletes older ones.
# 4. Checks the uploaded file exists and is larger than a minimum size.
#
# Needs: SUPABASE_DB_URL (direct or session connection string, not the
# transaction pooler), SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
# BACKUP_PASSPHRASE, R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY.
# Tools: supabase CLI (and Docker, which it uses for pg_dump), node 18+,
# gpg, tar, aws CLI. BACKUP_UPLOAD=0 stops after encrypting (a local test);
# BACKUP_OUT keeps the encrypted file in that folder.
set -euo pipefail

bucket=simplek-backups
min_bytes=${BACKUP_MIN_BYTES:-50000}
keep_daily=30
keep_monthly=12

for name in SUPABASE_DB_URL SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY BACKUP_PASSPHRASE; do
  if [ -z "${!name:-}" ]; then echo "Missing $name" >&2; exit 1; fi
done
upload=${BACKUP_UPLOAD:-1}
if [ "$upload" = 1 ]; then
  for name in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY; do
    if [ -z "${!name:-}" ]; then echo "Missing $name" >&2; exit 1; fi
  done
fi

day=$(TZ=Asia/Kolkata date +%F)
name="simplek-backup-$day"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/$name/db" "$work/$name/storage/business-media"

echo "Dumping the database"
supabase db dump --db-url "$SUPABASE_DB_URL" --role-only -f "$work/$name/db/roles.sql"
supabase db dump --db-url "$SUPABASE_DB_URL" -f "$work/$name/db/schema.sql"
supabase db dump --db-url "$SUPABASE_DB_URL" --data-only --use-copy -f "$work/$name/db/data.sql"

echo "Downloading Storage files"
node "$(dirname "$0")/storage_files.mjs" download business-media "$work/$name/storage/business-media"

# What the backup holds, for the restore check (docs/RESTORE.md).
count_rows() {
  awk -v t="COPY \"public\".\"$1\" " 'index($0, t) == 1 { on = 1; next } on && /^\\\.$/ { exit } on { n++ } END { print n + 0 }' \
    "$work/$name/db/data.sql"
}
{
  echo "Simplek backup $day ($(date -u +%FT%TZ))"
  for table in business_profiles customers products invoices invoice_items payments quotations; do
    echo "$table $(count_rows "$table")"
  done
  echo "storage_files $(find "$work/$name/storage" -type f | wc -l | tr -d ' ')"
} > "$work/$name/MANIFEST.txt"
cat "$work/$name/MANIFEST.txt"

echo "Packing and encrypting"
file="$work/$name.tar.gz.gpg"
"$(dirname "$0")/pack_and_encrypt.sh" "$work/$name" "$file"
size=$(wc -c < "$file" | tr -d ' ')
echo "Encrypted backup: $size bytes"
if [ "$size" -lt "$min_bytes" ]; then
  echo "The backup is smaller than $min_bytes bytes; something went wrong." >&2
  exit 1
fi
if [ -n "${BACKUP_OUT:-}" ]; then cp "$file" "$BACKUP_OUT/"; fi
if [ "$upload" != 1 ]; then echo "Not uploading (BACKUP_UPLOAD=$upload)"; exit 0; fi

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=auto AWS_EC2_METADATA_DISABLED=true
r2=(aws s3 --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com")
r2api=(aws s3api --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com")

echo "Uploading"
"${r2[@]}" cp "$file" "s3://$bucket/daily/$name.tar.gz.gpg" --only-show-errors
if [ "$(TZ=Asia/Kolkata date +%d)" = 01 ]; then
  "${r2[@]}" cp "$file" "s3://$bucket/monthly/simplek-backup-${day:0:7}.tar.gz.gpg" --only-show-errors
fi

echo "Checking the upload"
uploaded=$("${r2api[@]}" head-object --bucket "$bucket" --key "daily/$name.tar.gz.gpg" \
  --query ContentLength --output text)
if [ "$uploaded" != "$size" ]; then
  echo "Uploaded size $uploaded does not match $size." >&2
  exit 1
fi

echo "Keeping the newest $keep_daily daily and $keep_monthly monthly copies"
prune() {
  local prefix=$1 keep=$2
  "${r2api[@]}" list-objects-v2 --bucket "$bucket" --prefix "$prefix" \
    --query 'Contents[].Key' --output text \
    | tr '\t' '\n' | { grep -v '^None$' || true; } | sort \
    | "$(dirname "$0")/older_than_newest.sh" "$keep" \
    | while read -r key; do
        [ -n "$key" ] || continue
        "${r2[@]}" rm "s3://$bucket/$key" --only-show-errors
        echo "Removed $key"
      done
}
prune daily/ "$keep_daily"
prune monthly/ "$keep_monthly"
echo "Backup $name done"
