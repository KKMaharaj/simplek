# Simplek security (CR-25B B4.7)

How Simplek protects personal data, as required by the DPDP Rules 2025
("reasonable security safeguards"). Keep this file current when anything
here changes.

## In transit and at rest

- **HTTPS everywhere.** The website and web app are served by Cloudflare
  Pages over HTTPS only; the app talks to Supabase (database, login,
  storage, edge functions) over HTTPS only. Lookups (GSTIN, PIN, IFSC) go
  over HTTPS.
- **Encryption at rest.** The Supabase project (`vvzaoxhygzhentywnlwr`,
  region `ap-south-1`, Mumbai) stores the database and Storage files
  encrypted at rest (AES-256, managed by Supabase).
- **Backups** are encrypted before they leave GitHub Actions (B5:
  `.github/workflows/nightly-backup.yml`, `age` with a passphrase kept only
  in a GitHub secret and offline), and kept in a private Cloudflare R2
  bucket. Local copies (`backups/`) are never committed (`.gitignore`).

## Who can see what

- **Row-level security on every table.** Each business sees only its own
  rows (`user_id = viewing_business()`); an invited accountant sees a shared
  business read-only, checked on the server. Tables the app must not read or
  change (`audit_log`, `account_deletions`, `payments` directly) have RLS
  with no app policy; they are reached only through `security definer`
  functions that check the caller.
- **Storage.** `business-media` (logos, signatures, QR images) and
  `data-exports` ("Download my data" ZIPs) are private; each user's files sit
  in a folder named after their user id and only they can reach it. Export
  links are signed and expire after 24 hours; the files are removed after 7
  days.
- **Service-role key** is used only inside Supabase (edge functions) and,
  for backups, in a GitHub secret. It is never in the app or the repository.
- **Passwords** are handled by Supabase Auth (hashed, never visible to us).
  The app never logs passwords or tokens.

## Logs, kept at least 1 year

- **Audit log** (`audit_log`): every invoice delete, restore and edit, with
  who, when and the old values (B1). Entries of a deleted account are kept a
  year after deletion and then anonymised (`privacy_cleanup`).
- **Accountant access**: invitations live in `business_access` (who was
  given access, by whom, when) and switches in `business_viewing`; the
  Supabase Auth logs record each login of the accountant.
- **Supabase platform logs** (API, Auth, Postgres) as kept by the Supabase
  plan. *The Free plan keeps them for a short time only; moving to a paid
  plan, or exporting them, is needed to keep access logs for a full year.*
  (Listed in `NOTES.md`.)
- **Consents** (`consents`): each acceptance of the Privacy Notice, with the
  time, notice version, web/Android, IP and device.

## Changes and reviews

- Database changes are migrations in `supabase/migrations/` with a dry run,
  a rolled-back rehearsal and regression tests in `supabase/tests/`.
- Pushing to `master` deploys the website and web app only after
  `flutter analyze` and `flutter test` pass.
- If a breach happens, follow `docs/BREACH-RESPONSE.md`.
