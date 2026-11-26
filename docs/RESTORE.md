# Restoring Simplek from a backup (CR-25B B5)

The nightly backup (`.github/workflows/nightly-backup.yml`, script
`tool/backup/nightly_backup.sh`) puts one encrypted file per night in the
private Cloudflare R2 bucket `simplek-backups`:

- `daily/simplek-backup-YYYY-MM-DD.tar.gz.gpg`: the newest 30 nights;
- `monthly/simplek-backup-YYYY-MM.tar.gz.gpg`: the copy from the 1st of each
  month, the newest 12.

Inside (after decrypting) is a folder `simplek-backup-YYYY-MM-DD/` with:

- `db/roles.sql`, `db/schema.sql`, `db/data.sql`: the whole database, made
  with `supabase db dump` (roles, schema, data with `COPY`);
- `storage/business-media/…`: every logo, signature and QR file, in the same
  folders as in Storage (`<user id>/logo.png`, …);
- `MANIFEST.txt`: the date and the row counts (businesses, customers, items,
  invoices, invoice lines, payments, quotations) and the number of files, to
  check a restore against.

A restore always goes into a **new** Supabase project, never on top of the
live one. Only after checking it do you switch the app over.

## What you need

- The backup passphrase (`BACKUP_PASSPHRASE`, kept offline). **Without it a
  backup cannot be opened.**
- Access to the Cloudflare account (R2) and the Supabase organisation.
- On the computer: the Supabase CLI, PostgreSQL 17 client tools (`psql`),
  `gpg`, `tar`, and Node 18 or newer. (Git Bash on Windows has `gpg` and
  `tar`.)

## 1. Download the backup

In Cloudflare: R2 → `simplek-backups` → `daily/` (or `monthly/`) → the file →
Download. Or with the AWS CLI and an R2 token:

```bash
aws s3 cp --endpoint-url https://<account id>.r2.cloudflarestorage.com \
  s3://simplek-backups/daily/simplek-backup-2026-11-28.tar.gz.gpg .
```

## 2. Decrypt and unpack

```bash
gpg --decrypt simplek-backup-2026-11-28.tar.gz.gpg | tar -xz
cat simplek-backup-2026-11-28/MANIFEST.txt
```

`gpg` asks for the passphrase.

## 3. Create the new Supabase project

Supabase → New project, region **Mumbai (ap-south-1)**. Note its database
password and, under Project Settings → Database → Connection string, the
**session** connection string (port 5432). Call it `NEW_DB_URL` below.

## 4. Restore the database

```bash
cd simplek-backup-2026-11-28/db
psql --single-transaction --variable ON_ERROR_STOP=1 \
  --file roles.sql \
  --file schema.sql \
  --command 'SET session_replication_role = replica' \
  --file data.sql \
  --dbname "$NEW_DB_URL"
```

`session_replication_role = replica` loads the data without firing triggers
or checking foreign keys row by row; that is how Supabase's own restore
guide does it. If `roles.sql` fails on a role that the new project already
has, run the command again without `--file roles.sql`.

Then apply any migration in `supabase/migrations/` that is newer than the
backup (`supabase link --project-ref <new ref>` then `supabase db push`).

## 5. Restore the files

With the new project's URL and service-role key (Project Settings → API):

```bash
export SUPABASE_URL=https://<new ref>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=<new service role key>   # never commit it
node tool/backup/storage_files.mjs upload business-media \
  simplek-backup-2026-11-28/storage/business-media
```

The `business-media` and `data-exports` buckets are created by the
migrations (`data.sql` also restores the bucket list).

## 6. Check the restore

In the new project's SQL editor, compare with `MANIFEST.txt`:

```sql
select
  (select count(*) from public.business_profiles) as business_profiles,
  (select count(*) from public.customers) as customers,
  (select count(*) from public.products) as products,
  (select count(*) from public.invoices) as invoices,
  (select count(*) from public.invoice_items) as invoice_items,
  (select count(*) from public.payments) as payments,
  (select count(*) from public.quotations) as quotations,
  (select count(*) from storage.objects where bucket_id = 'business-media') as storage_files;
```

Every number must match. Then run the SQL tests in `supabase/tests/` against
the new project; each ends in `rollback`, so they change nothing.

## 7. Switch the app over (only for a real disaster)

1. Edge functions: `supabase functions deploy gstin-lookup`,
   `pincode-lookup` and `privacy-daily --no-verify-jwt`, and set their
   secrets again (the GSTIN provider key) under Edge Functions → Secrets.
2. Auth: copy the URL configuration (site URL, redirect URLs) and email
   templates from the old project.
3. The schedule: apply `20261127000004_privacy_daily_schedule.sql` with the
   new project's function URL.
4. The app: put the new project URL and publishable key in `lib/main.dart`
   (`Supabase.initialize`), raise the version, push to `master` (the website
   and web app deploy), and build a new APK.
5. The nightly backup: change the `SUPABASE_*` GitHub secrets to the new
   project.

## Tested restores

| Date | Backup | Into | Result |
|---|---|---|---|
| 27 Nov 2026 | `backups/20261127_*` (local, the same three dump files) | — | Encrypt → decrypt round trip identical; row counts read correctly (37 invoices). **Full restore into a test Supabase project not done yet**: needs the owner's test project (`NOTES.md`). |
