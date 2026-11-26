# Notes: decisions, placeholders and open questions

## Replace before launch

- (CR-25) The LGD district list was imported on 26 Nov 2026; to refresh it
  later, see `supabase/imports/README.md`.
- **Privacy Notice and Terms** (`website/privacy.html`, `website/terms.html`,
  CR-25B B4): the legal name of the business that runs Simplek, its postal
  address and contact email; the Terms' plans and prices and the courts that
  have jurisdiction. Shown as "[… to be added]" on the pages.
- **Grievance contact** (B4.5): a named person and email, on the Privacy
  Notice (section 7) and in the app (`PrivacyInfo.grievanceName` and
  `grievanceEmail` in `lib/privacy_pages.dart`).
- **Breach plan roles** (`docs/BREACH-RESPONSE.md`): who is the breach lead,
  the technical lead and the grievance contact.
- **"Raise a concern" emails the grievance contact**: not yet. Requests are
  stored (`privacy_requests`, due in 30 days, status shown to the user), but
  Simplek has no email service until the super admin change request adds the
  email settings. Until then, check new requests in the Supabase table
  editor.

- **Nightly backup (CR-25B B5): owner's steps** (Claude Code walks you
  through them; it never creates keys or enters secrets):
  1. Cloudflare → R2: create the private bucket `simplek-backups` and an R2
     API token with *Object Read & Write* on that bucket only (reading and
     deleting are needed to keep 30 daily and 12 monthly copies).
  2. GitHub → Settings → Secrets and variables → Actions: add
     `SUPABASE_DB_URL` (Supabase → Project Settings → Database → *session*
     connection string, with the database password), `SUPABASE_URL`,
     `SUPABASE_SERVICE_ROLE_KEY`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
     `R2_SECRET_ACCESS_KEY` and `BACKUP_PASSPHRASE` (names in
     `.env.example`).
  3. **Store `BACKUP_PASSPHRASE` safely offline** (on paper or in a password
     manager). Without it the backups can't be opened.
  4. Create a free **test** Supabase project for the restore test
     (`docs/RESTORE.md`). B5 is not Done until one restore has passed.
  Until the secrets are set, each night's run fails with "Missing …" and
  GitHub emails you; that is expected.
- **Encryption uses gpg (AES-256)**, the change request's second choice:
  `age` only reads a passphrase from a keyboard, so it can't run unattended.

- **Sign-up email needs custom SMTP (login fixes, cause F): owner's step.**
  Supabase → Authentication → Emails → SMTP Settings. Without it Supabase
  sends sign-up emails only to the project's team members, at most 2 an hour,
  so customers can't sign up. Gmail SMTP with an app password, or a free
  Brevo account, is enough to start.
- **Redirect URLs (login fixes L5): owner to check.** The app sends sign-up
  links back to `simplek://login-callback/` (Android; the app's manifest
  handles it) and to the web app's own address,
  `https://simplek.pages.dev/app/`. Both must be listed in Supabase →
  Authentication → URL Configuration → Redirect URLs, and the Site URL should
  be `https://simplek.pages.dev/app/`. They can't be read from the project's
  code: `supabase/config.toml` only holds local-development values
  (`127.0.0.1:3000`), and the live settings are in the dashboard.

- **Super admin: your admin login** (S0). After the admin migrations are
  applied, add yourself in the Supabase SQL editor:
  `insert into public.super_admins (user_id) select id from auth.users where email = '<your login email>';`
  Then open `https://simplek.pages.dev/app/#/admin`, set up the two-step
  login with an authenticator app, and the panel opens. Everyone else sees
  "Page not found".
- **Super admin: accounts you must create** (S5), then enter them on the
  Integrations page: an email sender (Brevo is simplest, or Gmail /
  Workspace / Zoho / SES SMTP on port 465), a Meta WhatsApp Cloud API app
  (number, phone number ID, business account ID, access token), and a
  Razorpay account (test keys first). Nothing is sent yet except the test
  buttons. The WhatsApp and Razorpay webhook URLs shown are placeholders until
  the change that receives their messages.
- **Website pricing** (S4.6): `website/index.html` still says "Free: up to 30
  invoices a month". Not changed until you confirm the wording for the
  250-invoice free plan.

## Needs owner's confirmation

- **Free plan: 250 in total or 250 a month?** (S4) It is seeded as 250 in
  total (`lifetime`). Change it on the Plans page (Invoice limit: "Each
  month") if you meant per month; usage then counts the current month.
- **"Enforce plan limits" is off**: usage is counted and shown (Settings,
  the admin pages, the 80% notice on Home) but nobody is blocked until you
  turn it on in Platform settings.
- **"Needs attention" lists only businesses over their limit.** The app
  doesn't record failed GSTIN lookups yet, so "GSTIN lookup failing" can't
  be shown.
- **Monthly recurring revenue shows ₹0** until plan payments exist.
- **"This email already has an account"** (S3) means the sign-up page can
  tell anyone whether an email is registered. That is what the change
  request asks for; it does make guessing which emails have accounts easier.
- **Admin "Download business data"** makes the PDFs without the business's
  logo, signature and QR (those images stay in the business's own folder).


- **A lawyer must review the Privacy Notice and Terms before launch**
  (CR-25B B4). Both pages say "Draft: to be reviewed by a lawyer before
  launch" until then.
- **"This year" and "This quarter" follow the financial year** (B2 date
  presets): this year is 1 April to 31 March, quarters are Apr–Jun, Jul–Sep,
  Oct–Dec and Jan–Mar, as GST returns use. The button shows the dates.
- **Download my data: the PDFs are made in the app** (B4). The server sends
  everything as JSON (`export_my_data`, deleted invoices and payments
  included) and the app adds the Excel file and every invoice PDF with the
  same code it uses for invoices, zips them, stores the ZIP in a private
  folder and opens a link that works for 24 hours. The change request said
  "built on the server"; making the PDFs a second time on the server would
  mean a second copy of the invoice design. Exports are removed after 7
  days.
- **Supabase Free keeps platform logs only briefly**, so "access and
  security logs kept for at least 1 year" (B4.7) holds for Simplek's own
  logs (audit log, consents, access invitations) but not for Supabase's API
  and login logs until the project moves to a paid plan or the logs are
  exported. See `docs/SECURITY.md`.
- **Account deletion is confirmed by typing the business name**, or the
  login email for an account without a business (an accountant's own
  account).

- **Description on the PDF is 9 pt** (terms are 9.5 pt) so that the full 300
  characters fit in three lines without cutting any text. Change request 9
  asked for the same size as the terms *and* at most three lines; both can't
  hold for 300 characters.
- **Signature area on the PDF is 48 pt tall** (change 10 said at most 56) and
  **the "Subtotal" row is left out on GST invoices**, where it always equalled
  "Taxable value". Both were needed for the 8-item, 300-character invoice to
  fit on one page.
- **Text line spacing on PDFs** was reduced (1.5 pt → 0.8 pt extra between
  lines) for the same reason.
- **GSTIN from a lookup fills address line 1 and the PIN only when line 1 is
  empty**, because the provider's address is one long line.
- **Quotations still don't store a customer GSTIN** (known since 19 Nov), so a
  converted quotation loses it; not part of this change request.

## Decisions

- Deploy workflow: the deploy steps run only for `master`, so a manual run on
  another branch checks and builds but can never publish it.
- `save_invoice` got a sixth parameter, `p_description` (default null). The old
  five-parameter version was dropped so the API never has two candidates; app
  1.2.0 still calls it successfully. An edit that sends no description keeps
  the saved one; '' clears it.
- States are compared by GST state code everywhere (`sameGstState`), and names
  keep the spelling the app already saved ("Jammu and Kashmir"), so old
  customers and invoices still match.
- Customer form for an unregistered business: an existing customer's GSTIN and
  state are kept in the database, not shown, and not overwritten on edit.
- Screenshots for review are rendered by `test/screenshots_test.dart`
  (`SIMPLEK_SCREENSHOTS=1`) with sample data and no network; screens that need
  a login (picker lists, saved invoices) are hand tests.

### Part B (CR-25B), from 26 Nov 2026

- **B1 delete is a soft delete.** `invoices.deleted_at` / `deleted_by`; a
  restrictive SELECT policy hides deleted invoices (and, through it, their
  items) from every read the app makes, so no list, total or export can
  forget the filter. Payments stay with the invoice and come back on Undo.
  The hard-delete policy on invoices was dropped. A quotation whose converted
  invoice was deleted can't be converted again ("The converted invoice no
  longer exists"); restore the invoice instead.
- **B1 audit log** (`audit_log`) has RLS with no policies: the app can't read
  or write it. Only `audit_invoice` (security definer) writes, from the
  database's own copy of the invoice, its items and payments.
- **B3 rounding rule** (also at the top of `lib/money.dart`), all in integer
  paise:
  1. line taxable value = quantity × rate, rounded half-up to the paisa;
  2. line tax = taxable value × GST % ÷ 100, rounded half-up to the paisa;
  3. within the state: CGST = tax ÷ 2 rounded half-up, SGST = tax − CGST
     (₹5.05 → ₹2.53 + ₹2.52); otherwise IGST = tax;
  4. invoice subtotal, tax, CGST, SGST and IGST are sums of the line values,
     and so are the PDF's rate-wise CGST/SGST lines;
  5. total payable = subtotal + tax rounded to the rupee, 50 paise and above
     up (19 Nov); the difference is Round off;
  6. the amount in words is the printed total payable.
  Quantity, rate and GST % are first rounded to the places the database keeps
  (3, 2 and 2 decimals), so the app and the server start from the same
  numbers. "Half-up" is half away from zero, as Postgres `round()` does.
- **B4 consent**: the tick at sign-up is saved with the new account
  (`privacy_consent_version`, `privacy_consent_at` in the user's metadata)
  and stored in `consents` at the first login, with the IP from the request
  headers. Anyone who hasn't accepted the current version
  (`PrivacyInfo.noticeVersion`) sees "We've updated our Privacy Notice" once.
  Changing the notice means a new version string.
- **B4 deletion**: a login within the 30 days cancels it (checked at every
  session start); asking to delete signs the account out on all devices so
  only a real new login cancels it. On day 31 `privacy-daily` removes the
  files and `purge_account` deletes every row and the login.
- **B4 sign-ups never completed** = logins older than 30 days with no
  business profile, not an invited accountant and no deletion pending. On
  26 Nov 2026 that was 0 of the 7 logins.
- **B3 on the server:** `save_invoice` works every amount out again. The app
  sends `money_rule: 'paise-v1'`; then any difference is refused ("…do not
  match the server's calculation. Update the app and try again."). Older app
  versions don't send it: the server stores its own amounts instead of theirs,
  so they keep working and the database always follows the rule. In rare
  cases an older version's screen or PDF can then differ by a paisa (or a
  rupee at a round-off boundary) from what is stored, until it is updated.
  Invoices saved before 26 Nov keep their stored amounts.
