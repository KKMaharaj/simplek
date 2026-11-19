# Simplek - Project Tracker

Last updated: 2026-09-22

This tracker maps the Software Requirements Document (SRD) to the current
implementation. Update the status and notes whenever a feature changes.

## Status key

- `Done` - implemented and verified.
- `In progress` - actively being implemented.
- `Blocked` - cannot proceed without a decision, credentials, or database detail.
- `Not started` - not yet implemented.

## Foundation

| Requirement | Status | Notes |
| --- | --- | --- |
| Flutter application | Done | Android app builds and launches on the emulator. |
| Supabase connection | Done | Supabase Flutter is configured. |
| Android build reliability | Done | Kotlin incremental compilation is disabled to avoid local cache collisions. |
| iOS build verification | Blocked | Android/web assets and iOS project metadata are present, but a real build requires macOS and Xcode. |
| Clean app architecture | In progress | Shared persistence and settings services are isolated by class, but feature widgets remain concentrated in `lib/main.dart`; a mechanical file split is deferred until broader regression coverage exists. |

## Authentication and business setup

| Requirement | Status | Notes |
| --- | --- | --- |
| Email-link signup and password login | Blocked | App-side login, registration, email verification, password setup, remembered email, Android password-manager hints, deep-link manifest, and logout are complete. Dashboard URL Configuration is inaccessible with the current project role; add `simplek://login-callback/` there before final email-link testing. |
| Redirect new users to business setup | Done | After email verification and password creation, new users complete a required three-step business onboarding flow before returning to login. |
| Business profile | Done | Profile data syncs per user. Logo, signature, and payment QR use a private per-user Storage bucket and restore into persistent app storage on another device. Apply migrations through `20260901000000_business_media_storage.sql`. |
| GST registration options | Done | Onboarding captures GST status, registration type, PAN, business state and default place of supply. Registered businesses verify GSTIN to fill registered details. |
| Terms and conditions | Done | Standard quotation and invoice terms are prefilled separately during onboarding, remain editable in Business Settings, and can be overridden on each document. |
| Default invoice due date | Done | Business Settings stores invoice payment terms in days (7 by default); new invoices calculate the due date from the invoice date and remain editable. |
| Financial year and document numbering settings | Done | Business profile stores financial year plus invoice/quotation prefixes; atomic PostgreSQL numbering uses these preferences. |

## Dashboard

| Requirement | Status | Notes |
| --- | --- | --- |
| Dashboard layout | Done | Summary cards, quick actions, and a live Recent Invoices list are implemented. |
| Live sales and outstanding totals | Done | Dashboard now reads invoice and customer data from Supabase and supports manual refresh. |
| Quotations and recent activity | Done | Quotations are available from the drawer, customer history includes quotation activity, and reports include ranked customer sales. |

## Customers

| Requirement | Status | Notes |
| --- | --- | --- |
| Add customer | Done | Name validation, optional contact details, GSTIN, tenant-owned Supabase save, and success feedback are implemented. `20260831000000_customer_product_rls.sql` was applied and verified on 2026-08-31. |
| Customer list | Done | Supabase-backed list, loading/error states, pull-to-refresh, and drawer navigation are implemented. |
| Search and autocomplete | Done | Customer list and reusable document pickers search by name, mobile, email, or GSTIN. |
| Customer history | Done | Tapping a customer shows their contact details, billing total, outstanding balance, invoices, and quotations. |
| GST portal/API lookup | Blocked | Secure Edge Function and verification UI are implemented. Deployment requires the external `GSTINAPI_KEY` secret, which is not available in the workspace. |

## Products and items

| Requirement | Status | Notes |
| --- | --- | --- |
| Add product/service | Done | Product/service saves include the authenticated owner required by RLS. GST classification is conditional, UQC selection is database-backed for products, and GST rate is entered manually. RLS was applied and verified on 2026-08-31. |
| Product list, search, and autocomplete | Done | Searchable Products & Services list plus searchable invoice/quotation item pickers are implemented. |
| Last selling price | Done | Selecting a saved item on a new invoice reuses its most recent invoiced unit price, with the catalog price as fallback; the suggested rate remains editable. |
| HSN and GST item details | Done | Separate searchable HSN/SAC master is live with 21,932 HSN and 681 SAC records. Businesses select classification from the master and enter the GST rate manually. |

## Quotations

| Requirement | Status | Notes |
| --- | --- | --- |
| Create and edit quotation | Done | Users can create quotations or edit non-converted quotations while retaining the same quotation number. |
| Draft, sent, accepted, rejected, expired statuses | Done | All lifecycle actions are available; overdue draft/sent quotations are automatically marked expired when quotation data loads or refreshes. |
| Convert quotation to invoice | Done | Accepted quotations can be converted into draft invoices. Converted quotations are protected from editing. |
| Quote PDF, preview, print, email, and WhatsApp share | Done | Quotation PDF preview, printing, native PDF sharing, and saved-customer email/WhatsApp shortcuts are implemented. |

## Invoices and payments

| Requirement | Status | Notes |
| --- | --- | --- |
| Invoice builder and line items | Done | Invoice form supports reusable saved-customer and saved-product/service selection, preview, and Save Draft. Drafts have atomic unique numbers and a refreshable invoice history. Product selection pre-fills selling price and the business-entered GST default, which remains editable. |
| Automatic amount and GST calculations | Done | Invoice and quotation line items calculate taxable amount and split GST into CGST/SGST for intra-state supply or IGST for inter-state supply. Component amounts are stored on documents and rows. |
| Unique invoice numbering | Done | Default format is `INV/YYYY-YY/0001`; PostgreSQL allocates the sequential number atomically. |
| Invoice preview and PDF | Done | Clean PDF preview supports seller details, GSTIN, line-item GST, totals, bank details, QR code, signature, and terms. Draft persistence and atomic numbering are implemented. |
| Record payments | Done | Payment screen and database function are live and verified with a partial payment. |
| Cash, UPI, bank transfer, card, and cheque | Done | Payment screen and database accept all five methods. |
| Partial payment and outstanding validation | Done | Database rejects payments above the locked outstanding balance. |
| Automatic paid/pending status | Done | Database changes invoice status to `partial` or `paid` after a successful payment. |

## Reports and exports

| Requirement | Status | Notes |
| --- | --- | --- |
| Sales, revenue, and pending-payment reports | Done | Live reports show total sales, collected amount, outstanding amount, invoice count, paid/pending counts, and recent invoices. |
| GSTR-1 report | Done | Period-filtered B2B/B2C tables, draft exclusion, GST validation, component summaries, and PDF/Excel/CSV/Tally XML exports are implemented. |
| Customer-wise and item-wise reports | Done | Live ranked customer and item sales summaries include quantity, taxable value, tax, total sales and outstanding amounts. |
| Export PDF, Excel, CSV, and TallyPrime XML | Done | Reports export the selected period's non-draft invoices through the native share sheet in all four formats. |

## Platform capabilities

| Requirement | Status | Notes |
| --- | --- | --- |
| PDF preview and download | Done | Invoice and quotation PDFs are generated in-app and can be previewed/shared. |
| Print | Done | Invoice and quotation PDFs use the platform printing integration. |
| Email with PDF attachment | Done | Email composer and native PDF attachment share are implemented; delivery uses the user's installed mail app. |
| WhatsApp share with PDF attachment | Done | Direct WhatsApp chat and native PDF attachment sharing are implemented, subject to WhatsApp's platform chooser behavior. |
| Cloud sync | Done | Customers, products, HSN/SAC, invoices, quotations, payments, dashboard, reports, business settings, and private business media sync through Supabase. |
| Offline support | Done | Customers and products are cached with UUID-backed create queues. Invoice drafts and payments queue per user while offline and retry in order; invoice numbers and payment balance validation remain server-authoritative at sync time. |
| Global search | Done | Dashboard search covers customers, products/services, invoices, and quotations, with cached customer/item results while offline. |
| Duplicate quotation/invoice | Done | Invoice and quotation history actions preload a new editable document from an existing one; current dates and fresh atomic document numbers are used when saved. |
| Secure storage | Done | GSTIN, PAN, bank/IFSC/account, and UPI values use platform keystore-backed secure storage. Existing plaintext preference values migrate automatically and are removed. Supabase manages auth-session persistence. |

## Current blockers / decisions needed

1. Provide `GSTINAPI_KEY` to deploy and activate the GSTIN lookup Edge Function.
2. Add `simplek://login-callback/` in Supabase Auth URL Configuration using a dashboard role with Auth configuration access.
3. Run the iOS build on macOS/Xcode.
4. The requested fresh-start reset and creation of a separate test account are
   pending Supabase administrator sign-in. On 2026-09-22, both browser sessions
   were signed out and no administrator credentials were available in the
   workspace. No accounts or billing data have been deleted.

## September 22 invoice improvements

- Five invoice palettes: white/red, white/blue, cream/blue, light yellow/blue,
  and white/dark green. The choice is stored in authenticated user metadata
  and cached under a user-specific key. No new database migration is needed.
- Business Settings previews the actual PDF using unsaved profile values and
  sample items; preview mode cannot save or share sample invoices.
- WhatsApp offers a client chat with an encoded prefilled message, targeted
  PDF attachment sharing, and message copying. Attachment sharing still
  requires selecting the recipient in WhatsApp; document captions depend on
  WhatsApp. Removed the unsupported recipient `jid` intent dependency.
- All 17 tests passed, including five multi-page PDF generations and phone /
  message normalization. All ten rendered sample PDF pages were inspected.
- Final on-phone WhatsApp testing remains pending: no Android device was
  connected during this change.

## Next implementation milestone

All locally actionable product requirements are implemented. Remaining work is
limited to the external blockers above and the low-risk architectural file split.

Security and media migrations through `20260901000001_quotation_rls.sql`,
`20260901000000_business_media_storage.sql`, and `20260904000001_invoice_rls.sql` were
applied to the live project by 2026-09-04.

## November 6 payment and invoice-save fixes

- **Deployed:** `20261106000000_atomic_invoice_payment_saves.sql` was applied to
  the live project on 2026-11-15 (see below). The app on `master` needs it.
- `record_invoice_payment` now checks invoice ownership, is closed to `anon`,
  and ignores a repeated `client_request_id`.
- `save_invoice` and `convert_quotation_to_invoice` run as one transaction, so a
  failure leaves no partial document and uses no number. Retrying a create with
  the same invoice id returns the saved invoice.
- Offline queues (`lib/offline_queue.dart`) keep items added during a sync, send
  each item once, and set aside items the server refuses, telling the user.
  Offline payments keep the date they were recorded.
- `supabase/tests/20261106_atomic_saves_regressions.sql` passed on a local
  Postgres and, on 2026-11-15, on the live project. These flows have not been
  tried on a device.

## November 15 live database takeover

- The repo is linked to the live project with the Supabase CLI
  (`supabase/config.toml`). A full backup taken before any change is in the
  git-ignored `backups/` folder (schema, data and roles; uploaded images are
  not included).
- **Security fix:** three policies that existed only in the live project ("Allow
  all customers", "Allow all products", "Allow all payments") gave anonymous
  callers full read and write access to every business's rows. Removed by
  `20261115000000_remove_anon_full_access.sql`. Whether they were ever misused
  cannot be determined from the database.
- Migrations were renamed to unique 14-digit versions, and the 18 already
  present on live were recorded as applied with `supabase migration repair`.
  `supabase migration list --remote` now matches the repo, so new migrations go
  out with `supabase db push --remote` (dry-run first with `--dry-run`).
- Both regression scripts passed on live; row counts were unchanged.
- Still open: the repo's migrations cannot build the database from scratch (no
  migration creates `customers`, `products` or `invoice_items`).
- The one ownerless invoice, `INV/2026-27/0008` (a pre-login draft), was given
  to Malnad Kitchen (account `04453ceb…`) by
  `20261115000001_assign_orphan_invoice.sql`. Its number does not affect that
  business's sequence.
- The remaining ownerless test rows, all created before any account existed,
  were deleted by `20261115000002_delete_ownerless_test_rows.sql`: quotation
  `QTN/2026-27/0001` with its item, 5 customers and the product "auditing".
  The line on `INV/2026-27/0008` kept its name and amounts and lost only its
  product link. No ownerless rows remain; restoring them needs the 2026-11-15
  backup.

## November 15 redesign, web app, website and biometric unlock

- **New design** (`lib/app_theme.dart`, `lib/modern_ui.dart`): one visual
  language for phone and web. The Classic/Modern switch was removed. New app
  frame: bottom navigation on phones, sidebar at 900px and wider. New home,
  More, login and "Create" sheet. The light/dark choice is a three-way switch
  (Light / Dark / Auto) in More, Settings and the sidebar, plus a one-tap
  toggle on the home screen. List, builder, report and settings screens take
  the new theme but keep their old layouts; a few document screens still
  contain unused Classic branches behind `DesignSettings.modern`.
- **Signature**: new full-width signing pad (`lib/signature_pad.dart`) saves
  only the ink on a transparent background. On documents, signatures are
  trimmed to their ink (`lib/signature_image.dart`) and print in a 200×84pt
  box instead of 110×45pt. Quotations now carry the signature too.
- **Fingerprint / face unlock** (`lib/app_lock.dart`, `local_auth`): offered
  once after login on devices with biometrics; toggle in More and Settings.
  It unlocks the saved session; the password is still needed to sign in on a
  new device or after logging out. `MainActivity` is now a
  `FlutterFragmentActivity`. Not yet tried on a real phone.
- **Web app**: the same Flutter code builds for the web. File access goes
  through `lib/platform/local_files.dart` (real files on phones, memory on the
  web, restored from cloud storage). `dart:io` is no longer imported by the
  app. Saving the profile no longer clears a cloud image reference when the
  local copy is missing or an upload fails.
- **Website** (`website/index.html`): public page with Log in and Sign up
  leading to the web app at `/app/` (`/app/?signup=1` opens sign-up).
  `tool/build_site.sh` builds `build/site`; `dart run tool/serve.dart` previews
  it at http://localhost:8080.
- **Live sync** (`lib/live_sync.dart`, `20261115000003_realtime_sync.sql`,
  applied on live): the same account on web and phone shares one database, and
  open home/list screens refresh when another device changes invoices,
  quotations, customers or products.
- `pubspec.yaml` Dart constraint relaxed to `^3.12.0` to match the installed
  SDK; `http` and `local_auth` added.
- **Before the website can go live:** choose a host and upload `build/site`,
  then add the site's `/app/` URL to Supabase Auth → URL Configuration →
  Redirect URLs, or email sign-up links from the web will not return to it.

## November 16 sync screen, online-only saving, accountant access, pricing page

- **Sync & backup** (More → Sync & backup): shows anything an earlier version
  left waiting on the device for the signed-in account and uploads it; warns
  when another account on the device has items waiting. Leftovers also upload
  automatically at start and login.
- **Online-only saving:** invoices, payments, customers and products are no
  longer queued on the device when offline. The app says nothing was saved; an
  open invoice form can simply be saved again once online. A read-only cached
  copy of the customer and product lists is still kept for search.
- **Accountant access** (`20261116000000_accountant_access.sql`,
  `20261116000001_accountant_media_access.sql`, applied on live;
  `lib/business_access.dart`): an owner gives view-only access by email under
  More → Accountant access. The accountant logs in with their own account,
  opens the shared business there, and sees it with a "view only" banner.
  Read policies follow `viewing_business()`; writes stay owner-only, and the
  server refuses any new record while another business is being viewed. Only
  a confirmed email matches an invite; removing the invite ends access at
  once. `supabase/tests/20261116_accountant_access_regressions.sql` passed
  locally and on live. Known gaps: no email is sent to the accountant; a new
  accountant still goes through business onboarding; edit buttons inside
  screens are not hidden in view mode (the server rejects the change); not
  tried with two real accounts in the app.
- **Website:** leads with sales-invoices-only, explains what Simplek leaves
  out, lists accountant login and Tally/GSTR-1 export, and shows pricing (free
  to 30 invoices a month; ₹250 a month or ₹1,500 a year). AI invoice creation
  is marked "Coming soon". **The 30-invoice limit and payments are not
  implemented**: today every account is unlimited and free.

## November 16 website and web app online

- Live on Cloudflare Pages (project `simplek`, account
  akshaykk.personal@gmail.com): website https://simplek.pages.dev, web app
  https://simplek.pages.dev/app/. Deployed by direct upload of
  `build/simplek-site.zip`; `tool/build_site.sh` now also builds that zip.
  To update the site, rebuild and upload a new deployment to the same project.
- `https://simplek.pages.dev/app/` added to Supabase Auth Redirect URLs. Site
  URL stays `simplek://login-callback/` for the phone app.
- Not yet tried: signing up or logging in on the live web app.

## November 19 changes (change request of 19 Nov 2026, version 1.2.0 build 20261120)

1. **Signature editor** (`lib/image_editor.dart`, `crop_your_image`): uploaded
   signature, logo and payment QR open a full-screen editor with free crop,
   presets (Signature shape 200:84, Square), pinch/scroll zoom, drag, rotate
   and Reset; a Clean background switch with a strength slider and previews on
   white, on a chequered background and inside the invoice signature box.
   Tiles in onboarding and Settings offer Edit / crop, Upload a new one, Draw
   again and Remove. A removed image is now removed on other devices too.
2. **Default place of supply removed** from onboarding and Settings. New
   invoices and quotations start with the business state and switch to the
   customer's state on selection; editing keeps the saved value. The
   `place_of_supply` column in `business_profiles` is left unused, not dropped.
3. **Financial year field removed.** The server already derives the year from
   the document date. The quotation number call still sends an empty
   `p_financial_year` so the 3-argument function keeps matching; the column is
   not dropped.
4. **App preferences:** theme and fingerprint/face unlock now live only at the
   bottom of Business Settings. Removed from More, the sidebar and the Home top
   bar.
5. **Home recent invoices** open that invoice.
6. **Invoice view** (`InvoiceViewPage`): tapping an invoice in the list or on
   Home opens its PDF with Share PDF, WhatsApp, Email, Print, Download (web),
   More → Edit / Duplicate / Record payment (Payments pre-selects the invoice),
   and Total / Paid / Balance due / Due date. Lists use customer name,
   `number • dd/mm/yyyy`, Indian-format amounts and status chips, with Preview
   first in the ⋮ menu. View-only accountants get no edit actions.
7. **New PDF layout** (`lib/document_pdf.dart`) after the Eesha Herbals
   reference, for invoices and quotations: page frame on every page, header,
   bordered boxes, HSN/SAC column (from the product), repeated table header,
   totals per GST rate, round off, payment and terms/signature boxes kept
   together, `Page x of y`. Noto Sans is embedded (`assets/fonts`, OFL) so `₹`
   prints. **Round off:** new documents save `total_amount` rounded to the
   rupee (50 paise up); subtotal and tax stay exact; older documents show no
   round off. UPI QR now pre-fills the balance due. Tested with
   `test/document_pdf_test.dart` (9 cases; `SIMPLEK_PDF_QA=1` writes PDFs to
   `tmp/pdfs-new`). Indian-script customer names were not tested in the PDF;
   the `pdf` package does not shape Kannada/Hindi, so expect them to print
   incorrectly.
8. **Numbering:** confirmed every number comes from
   `allocate_business_document_number` (2-digit serials, then 100, 101 ...;
   `0022` and `22` read as the same serial). Added
   `supabase/tests/20261119_document_number_format_regressions.sql` (passed
   locally and on live). Settings and onboarding warn when a prefix would push
   numbers past 16 characters. Existing numbers were not renumbered.
9. **Not GST registered:** no GST rate or customer GSTIN fields, tax saved as
   0, PDF titled INVOICE with no GST columns or lines. Registered businesses
   always get TAX INVOICE. Editing an old taxed invoice keeps its tax.

Also: Indian digit grouping on Home and lists (`lib/money.dart`); list dates
as dd/mm/yyyy. Test plan cells ONB-001/006/008/011/012, NAV-008, INV-020 and
DOC-001/004/014/015/016 updated (`tool/update_test_plan.dart`).

Not done in this round: forgot password and sign-up OTP (owner decision).
Not tried by hand on the phone or in the logged-in web app; the place-of-
supply prefill has no automated test (the builder needs a live Supabase
session in tests).
