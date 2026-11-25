# Simplek — complete project summary

Last updated: 19 November 2026 (version 1.2.0, build 20261120).

Paste or attach this file at the start of a new Claude chat to give it the full
picture. It covers what Simplek is, what is built and live, how it is put
together, how to release changes, known problems, and what is still to build.

---

## 1. What Simplek is

Simplek ("Invoicing made easy") is GST billing software for Indian small
businesses. It is deliberately **only for sales invoices**:

- **It does:** GST sales invoices and quotations, payments received and amounts
  still due, a GSTR-1 report, and exports to TallyPrime, Excel, CSV and PDF.
- **It leaves out:** purchase invoices, stock and inventory, ledgers and full
  accounting.
- **Promise:** simple enough to need no training. An accountant can be given
  view-only access, and receives Tally/GSTR-1 exports instead of doing data entry.

**Planned pricing (shown on the website, not yet enforced in the app):** free up
to 30 invoices a month; Unlimited at ₹250 a month or ₹1,500 a year. The yearly
price is half of twelve months; the owner stated these figures.

**Not yet decided:** the exact meaning of the name "Simplek". The website
currently just says "Simple, on purpose."

---

## 2. Where everything lives

| Thing | Where |
|---|---|
| Website | https://simplek.pages.dev |
| Web app | https://simplek.pages.dev/app/ (same login and data as the phone app) |
| Android app | Built locally as an APK; not on the Play Store |
| Code | GitHub `KKMaharaj/simplek`, branch `master` (the only branch). The old repo `akshaykk305/simplek` is no longer accessible. |
| Local copy | `D:\projects\simple_billing` on the owner's Windows PC |
| Backend | Supabase project `vvzaoxhygzhentywnlwr` (Mumbai, Postgres 17, Free plan) |
| Website hosting | Cloudflare Pages project `simplek` (direct upload, no auto-deploy) |
| Backups | `D:\projects\simple_billing\backups\` (git-ignored, local only): database schema, data and roles dumps and the 6 logo/signature images, taken 15 Nov 2026 |

**Businesses using it (live data, 16 Nov 2026):** three accounts, all the owner's:
Ekathva Innovations (invoice prefix `EINV`) and two Malnad Kitchen accounts
(prefix `INV`). About 29 invoices, 24 customers, 25 products, 2 quotations and
4 payments.

---

## 3. Technology

- **App:** Flutter (Dart 3.12, Flutter 3.44 on a non-standard channel). One
  codebase builds the Android app and the web app.
- **Backend:** Supabase: Postgres with row-level security, Auth (email +
  password, email-link sign-up), Storage (private `business-media` bucket for
  logos, signatures and QR images), Realtime, and one Edge Function
  (`gstin-lookup`).
- **Key packages:** `supabase_flutter`, `pdf` + `printing` (PDFs), `qr_flutter`
  (UPI QR), `share_plus`, `excel_plus`, `local_auth` (fingerprint/face),
  `flutter_secure_storage`, `http`, `image_picker`, `uuid`.
- **Website:** one static HTML page, `website/index.html`, with no framework.
- **External services:** Razorpay IFSC lookup (`ifsc.razorpay.com`) and
  gstinapi.in for GSTIN lookup (through the Edge Function; needs a
  `GSTINAPI_KEY` secret and may not be set up).

### Code layout

| Path | What it is |
|---|---|
| `lib/main.dart` | Almost the whole app (about 11,000 lines): screens, PDF generation, Supabase calls |
| `lib/app_theme.dart` | Visual design: colours, theme, light/dark/auto toggle |
| `lib/modern_ui.dart` | Home dashboard and shared UI pieces |
| `lib/app_lock.dart` | Fingerprint / face unlock |
| `lib/business_access.dart` | Accountant (view-only) access |
| `lib/live_sync.dart` | Realtime refresh across devices |
| `lib/document_pdf.dart`, `lib/money.dart` | Invoice and quotation PDF layout; rupee formatting and round off |
| `lib/image_editor.dart` | Crop and clean-background editor for signature, logo and QR |
| `lib/offline_queue.dart` | Uploads items older app versions left on the device |
| `lib/signature_pad.dart`, `lib/signature_image.dart` | Signing pad and signature sizing on PDFs |
| `lib/platform/local_files*.dart` | File access that works on phone and web |
| `lib/payment_pdf.dart`, `invoice_palette.dart`, `document_*.dart` | UPI QR, invoice colours, defaults, sharing, amount in words |
| `supabase/migrations/` | 25 database migrations, unique 14-digit versions |
| `supabase/tests/` | 4 rollback-only SQL regression scripts |
| `supabase/functions/gstin-lookup/` | GSTIN lookup proxy |
| `website/` | Public website |
| `tool/build_site.sh`, `tool/zip_site.dart`, `tool/serve.dart` | Build, zip and locally preview the site |
| `test/` | 10 Flutter test files (55 tests) |
| `PROJECT_TRACKER.md` | Running change log with dates |
| `docs/AI-Handoff-Billing-Website.md` | Older brief for a separate billing website |

---

## 4. What is built (working today)

### Billing features (from before November)
- Email sign-up with email link, password login, business onboarding
  (identity, GST status, GSTIN, PAN, state, prefixes, terms, bank, UPI, logo,
  signature).
- Customers and products/services with search, inline creation in documents,
  GSTIN verification, HSN/SAC master (21,932 HSN and 681 SAC codes), units
  (UQC), archive instead of delete.
- Quotations: create, edit, statuses (draft/sent/accepted/rejected/expired),
  convert to invoice.
- Invoices: line items, CGST/SGST or IGST by place of supply, preview, PDF,
  print, share by WhatsApp or email, five colour palettes, due dates, terms.
- Document numbers per business and per April–March financial year
  (e.g. `INV/2026-27/01`), allocated atomically on the server.
- Payments: cash, UPI, bank transfer, card, cheque; partial payments; status
  becomes partial/paid automatically.
- Reports: sales, outstanding, customer- and item-wise, GSTR-1 (B2B/B2C), exports
  to PDF, Excel, CSV and TallyPrime XML.
- Dashboard, global search, UPI QR on invoices.

### Fixed and added in November 2026
| Date | Change |
|---|---|
| 6 Nov | **Security:** the payment function let anyone (even signed out) record payments on any invoice; now checks ownership and blocks anonymous use. |
| 6 Nov | **Atomic saves:** invoices, quotation conversion and payments save in one database transaction; retries can't duplicate; failed saves use no number. |
| 15 Nov | **Security:** removed three live-only policies that let anonymous users read and edit all customers, products and payments. |
| 15 Nov | Supabase linked to the repo; migration history cleaned and synced; one ownerless invoice assigned to Malnad Kitchen; ownerless test rows deleted; storage permissions checked (correct). |
| 15 Nov | **New design** for phone and web (new home, More page, login, sidebar on wide screens); one-tap Light/Dark/Auto switch. |
| 15 Nov | **Signature:** new full-width signing pad; signatures trimmed to their ink and printed about twice as large; now also on quotations. |
| 15 Nov | **Fingerprint / face unlock** on the phone (offered after login; toggle in More and Settings). |
| 15 Nov | **Web app** from the same code; **public website**; **live sync** (screens refresh when another device changes data). |
| 16 Nov | **Sync & backup** screen uploads anything an older version left on the phone. **Saving now needs internet** — nothing new is kept only on the device. |
| 16 Nov | **Accountant access:** owner shares a business by email (More → Accountant access); accountant views it read-only with their own login; enforced in the database. |
| 16 Nov | Website rewritten around "sales invoices only" with pricing. |
| 16 Nov | Android release build fixed (version raised to 1.1.0 build 20261116; internet permission added) and installed on the owner's phone. |
| 16 Nov | Website and web app **published** at simplek.pages.dev; Supabase redirect added for web sign-up. |
| 19 Nov | **New invoice and quotation PDF** after the Eesha Herbals reference (page frame, bordered boxes, HSN/SAC, tax lines per rate, ₹ with Indian commas); **round off** to the rupee; **TAX INVOICE** only for GST-registered businesses, **INVOICE** with no GST otherwise. |
| 19 Nov | **Invoice view** screen (tap any invoice in the list or on Home): PDF, share, print, edit, duplicate, record payment. Tidier invoice and quotation lists. |
| 19 Nov | **Signature, logo and QR editor:** free crop, zoom, rotate, clean background, preview in the invoice box; edit, redraw or remove later. |
| 19 Nov | Removed "Default place of supply" and "Financial year"; theme and fingerprint unlock moved to Settings → App preferences; prefix-length warning; 2-digit document numbers confirmed with a new regression test. Version 1.2.0 (build 20261120). |

---

## 5. Database and security model

- **Every business is one Supabase user.** Rows carry `user_id`; row-level
  security limits each user to their own rows.
- **Main tables:** `business_profiles`, `customers`, `products`, `invoices`,
  `invoice_items`, `quotations`, `quotation_items`, `payments`,
  `business_document_counters`, `hsn_sac_master`, `uqc_master`,
  `business_access` (accountant invites), `business_viewing` (which shared
  business an accountant is viewing).
- **Server functions:** `save_invoice`, `convert_quotation_to_invoice`,
  `record_invoice_payment` (ownership-checked, request id prevents double
  payments), `next_invoice_number` / `next_quotation_number`,
  `viewing_business`, `set_viewing_business`, `shared_businesses`.
- **Accountant access:** read policies follow `viewing_business()`; all writes
  stay owner-only, and no new records can be created while viewing another
  business. Only confirmed emails match an invite; removing an invite ends
  access immediately.
- **Anonymous users** can only read the HSN/SAC and unit master lists.
- **Storage:** private bucket; each user (or their accountant while viewing)
  reads only that business's folder.
- **Regression tests** in `supabase/tests/` (numbering, atomic saves and
  payment ownership, accountant access) all pass on the live database.

---

## 6. How to work on it

Run these from `D:\projects\simple_billing`.

- **Check the code:** `flutter analyze` and `flutter test` (55 tests pass).
- **Android app:** raise `version:` in `pubspec.yaml` (the newest build is
  1.2.0+20261120, so the next must be higher), then `flutter build apk --release`.
  The APK is in `build/app/outputs/flutter-apk/app-release.apk` (about 64 MB).
  Install over the old app without uninstalling. If the phone refuses, connect
  it with USB debugging and install with `adb`.
- **Website and web app:** `.github/workflows/deploy-site.yml` builds both
  and deploys them to the Cloudflare Pages project `simplek` on every push to
  `master`, after `flutter analyze` and `flutter test` pass (if either fails,
  nothing is deployed). **Pushing to master deploys the web app to real
  users. Push only finished, tested work. Use a separate branch for anything
  in progress.** A manual run on another branch checks and builds but never
  deploys. Locally, `bash tool/build_site.sh` builds both and creates
  `build/simplek-site.zip`; preview with `dart run tool/serve.dart` at
  http://localhost:8080.
- **Database changes:** add a new file in `supabase/migrations/` with a unique
  14-digit version, test it, then `supabase db push --remote --dry-run` and
  `supabase db push --remote`. Run the regression scripts with
  `supabase db query --remote --yes -f supabase/tests/<file>.sql`. The Supabase
  CLI (v3.1.0) is at `C:\Users\HP\bin\supabase.exe` and is logged in and linked.
  `supabase db dump` needs Docker, which isn't installed; use the local
  PostgreSQL 17 `pg_dump` instead.
- **Supabase dashboard settings** (redirect URLs etc.):
  Authentication → URL Configuration. Site URL is `simplek://login-callback/`;
  redirect URLs include `simplek://login-callback/` and
  `https://simplek.pages.dev/app/`.

---

## 7. Known problems and limitations (not fixed yet)

**Money and reports**
- Dashboard totals add up only the newest 100 invoices.
- Reports and GSTR-1 load only the newest 500 invoices and 5,000 line items,
  then filter by period on the device, so older periods can be incomplete.
- Amounts are calculated in floating point and rounded per stored field, so
  CGST + SGST can differ from total tax by a paisa (5% on ₹101: CGST and SGST
  stored as ₹2.53 each against ₹5.05 tax).
- Converting a quotation drops the customer's GSTIN (quotations have no GSTIN
  field), so a B2B sale shows as B2C until edited.
- Editing an invoice to below the amount already paid marks it paid with zero
  balance, and the overpayment isn't shown.
- Payments can't be viewed, edited or reversed, and reference/notes aren't
  captured.
- Invoice prefixes allow 20 characters; GST rules may cap invoice numbers at
  16 (to be confirmed with a tax adviser). Settings now warns when a prefix
  would exceed 16, but doesn't block it.
- Round off applies to documents saved from 19 Nov 2026; older invoices keep
  their exact totals.

**App**
- `lib/main.dart` is one 11,000-line file; most screens keep their old layout
  inside the new theme, and some unused "Classic" design branches remain.
- PDFs now embed Noto Sans, so `₹` prints, but Indian-script names (Hindi,
  Kannada, Malayalam) won't print correctly: the `pdf` package doesn't shape
  those scripts. Not tested.
- HSN/SAC on PDFs comes from the product record at print time; invoices don't
  store their own copy, so changing a product's HSN changes old PDFs too.
- The place-of-supply prefill on new invoices has no automated test.
- Saved business details (bank, UPI, PAN) stay on the device after logout and
  aren't tied to a user.
- GSTIN verification shows "active" when the provider returns no status; the
  Edge Function has no per-user rate limit, and its API key may not be set.
- Accountant access: no invitation email is sent; a new accountant still goes
  through business onboarding; edit buttons aren't hidden in view-only mode
  (the server refuses, with an unfriendly message); not yet tested with two
  real accounts.
- No offline saving: without internet, saves fail with a message.
- The 30-invoice limit and paid upgrade aren't built, so everyone is unlimited
  and free.
- The live web app hasn't been tested past the login screen.

**Release and operations**
- Android app ID is `com.example.simplek` and release builds use the debug
  signing key: the Play Store will reject it. Fix before anyone else installs,
  because changing it later forces every user to reinstall.
- The database can't be rebuilt from the migrations alone (no migration
  creates `customers`, `products` or `invoice_items`); use the backup schema
  dump as the starting point.
- Supabase Free plan has no automatic backups; the only backup is the local
  one from 15 Nov.
- The website doesn't auto-deploy; each update is a manual zip upload.

---

## 8. What still needs to be built (suggested order)

1. **Play Store readiness:** real app ID (e.g. `in.simplek.app`), release
   signing key kept safely, store listing, privacy policy.
2. **Free limit and paid plan:** count invoices per month, block the 31st on
   the free plan, ₹250/month or ₹1,500/year upgrade through a payment provider
   such as Razorpay (needs an account in the owner's name), with payment
   verification on the server.
3. **AI invoice creation:** type or say "Invoice Malnad Kitchen for catering,
   15 people at ₹250 each" and get a draft invoice to check and save. Needs an
   AI provider API key stored as a Supabase secret, called from an Edge
   Function (never from the app).
4. **Accountant access polish:** invitation email, skip onboarding for
   accountants, hide edit buttons in view mode, friendly error messages.
5. **Report accuracy:** totals and GSTR-1 computed on the server across all
   invoices; money in paise; carry GSTIN into converted quotations.
6. **Redesign the remaining screens** (invoice and quotation builders, lists,
   reports, settings) in the new style, and split `main.dart` into files.
7. **Indian-script names on PDFs:** needs a PDF engine that shapes Kannada
   and Hindi (the `₹` part is done).
8. **Payments:** history, edit and reverse, reference and notes.
9. **Operations:** automatic website deploys, regular database backups (or a
   paid Supabase plan), and complete migrations that can rebuild the database.

---

## 9. Ground rules used so far

- Never test against live data without a backup; database changes go through
  migrations, a dry run, and regression tests that roll back their test data.
- Keep secrets (API keys, service keys) on the server, never in the app or the
  repo. The app only contains Supabase's public "publishable" key.
- Install new Android builds over the old app; don't uninstall, or anything
  stored only on that phone is lost.
- Each Android build needs a higher version number than the one installed.
- The owner makes final calls on tax treatment; GST filing advice should be
  checked with an accountant.
