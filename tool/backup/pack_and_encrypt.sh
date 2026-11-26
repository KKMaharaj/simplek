#!/usr/bin/env bash
# Packs a backup folder into <out> (a .tar.gz encrypted with gpg, AES-256,
# passphrase from BACKUP_PASSPHRASE) and deletes the plain copies, so only
# the encrypted file is left. Used by nightly_backup.sh; decrypt with
#   gpg --decrypt <file> | tar -xz        (docs/RESTORE.md)
set -euo pipefail
folder=${1:?backup folder}
out=${2:?encrypted file to write}
: "${BACKUP_PASSPHRASE:?Missing BACKUP_PASSPHRASE}"
parent=$(dirname "$folder")
name=$(basename "$folder")
plain="$out.plain.tar.gz"
tar -czf "$plain" -C "$parent" "$name"
rm -rf "${folder:?}"
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
  --symmetric --cipher-algo AES256 -o "$out" "$plain" 3<<<"$BACKUP_PASSPHRASE"
rm -f "$plain"
