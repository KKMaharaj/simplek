# Change status

## Change request of 25 Nov 2026: sign-up, customers and the business GST rule

File: `docs/CHANGE_REQUEST_2026-11-25.md`. Branch `cr-2026-11-25`, version
1.3.0 (build 20261126). **Not on `master` yet: waiting for the owner's
approval of the screenshots.** Screenshots and sample PDFs:
`docs/screenshots/2026-11-25/`.

Database: backed up first (`backups/20261126_*`, 33 invoices, 30 customers,
30 products, 4 businesses), then migrations `20261126000000` and
`20261126000001` and `20261126000002` (790 districts) applied on 26 Nov after a rolled-back rehearsal and a dry
run. All five SQL regression scripts in `supabase/tests/` pass on the live
database. Edge function `pincode-lookup` deployed.

| # | Change | Status | Where to check |
|---|---|---|---|
| 0 | Version line under the login form and at the bottom of Business Settings | Done | Login screen; Settings, bottom. `test/app_version_test.dart` |
| 0 | Raise version, build APK | Done (APK built, not installed) | Install `build/app/outputs/flutter-apk/app-release.apk` over the old app; look for 1.3.0 (build 20261126) |
| 5 | `flutter analyze` and `flutter test` before the automatic deploy | Done. Checked 26 Nov: run #5 on branch `ci-check-failing-test` (a deliberately failing test) stopped at Test; Build and Deploy were skipped | `.github/workflows/deploy-site.yml` (deploy steps run only on `master`); GitHub Actions run #5 |
| 1 | GST question as Yes / No buttons, no default, "Select Yes or No"; forms at most 640 px wide | Done | Onboarding step 1; Settings → Tax and numbering. Screenshots `onboarding-*`, `settings-*` |
| 2 | PAN, IFSC, GSTIN in capitals, letters and digits only, 10 / 11 / 15 characters | Done | Onboarding, Settings, customer form, invoice. `test/cr25_test.dart` |
| 3 | State picker: label above, no "Select state" overlap; form dialogs scroll with fixed buttons | Done | All state pickers; New customer dialog at 360×640. `test/cr25_test.dart` |
| 4 | Not registered: no place of supply; registered: state from the GSTIN, read-only; GSTIN checksum; real lookup status; CGST/SGST v IGST by state code | Done; **Needs hand test** with a real GSTIN lookup | New invoice / quotation for each account type |
| 6 | The business's GST status decides everything (customer form, invoices, PDF, reports, exports) | Done; **Needs hand test** in the logged-in web app and phone | Screenshots `new-customer-*`, `new-invoice-*`; Reports for an unregistered business |
| 7 | Item and customer picker: Add selects the new record (rate, GST %, HSN/SAC, link), Restore for archived names | Done in code; **Needs hand test** (the picker needs a live login) | New invoice → Product or service → type a new name → Add |
| 8 | SKU removed from the app and PDFs (database column kept) | Done | `grep -ri sku lib/` finds nothing |
| 9 | Optional Description (300 characters) on invoices and quotations; PDF box; copied on duplicate and conversion; searchable | Done (database tested); **Needs hand test** in the app | New invoice → Description; PDF `pdf-gst-8-items-description.pdf` |
| 10 | Compact, aligned payment box; 8 items + 300-character description on one page; 12 items on two | Done | `pdf-gst-8-items-description.pdf`; `test/cr25_test.dart` |
| 11 | Business address with PIN lookup, State and District; no "State (code)" line on the PDF | Done (36 states and 790 districts from the owner's LGD download of 26 Nov, in the app and the database); **Needs hand test** of the PIN lookup in the app | Onboarding / Settings address: Karnataka → Shivamogga; `supabase/imports/README.md` |

Pushed to `master` on 26 Nov after the owner's approval; the deploy run
passed and https://simplek.pages.dev/app/version.json showed 1.3.0 (build
20261126). Still open: hand tests on web and the phone.

## UI redesign of 25 Nov 2026 (`docs/UI_REDESIGN_2026-11-25.md`)

Branch `ui-redesign-2026-11-25`, version 1.4.0 (build 20261127). The owner
approved the screenshots in `docs/screenshots/2026-11-26-redesign/` on 26 Nov
and it was pushed to `master` the same day. Deploy run #6 stopped at Test (the
layout test could not find the Material icon font on GitHub's Linux runner;
nothing was deployed). Fixed in `6b22c0e`; run #7 passed and
https://simplek.pages.dev/app/version.json showed 1.4.0 (build 20261127).
Still open: the hand tests below, signed in, on web and the phone. Look only: no screen's data or rules
changed, except that Record payment now has the payment date the design
shows (today by default).

| Part | Change | Status | Where to check |
|---|---|---|---|
| 1 | Navy / orange / sky tokens; no gradients or violet; status chips with a dot and the word; light theme by default (set once for anyone on Auto or Dark); navy dark theme | Done | `lib/app_theme.dart`, `lib/ui_kit.dart`; Settings → App preferences |
| 2 | Fraunces titles, Inter text, bundled TTFs with OFL licences; dates on screens as DD MMM YYYY | Done | `assets/fonts/`; every list and form |
| 3 | Buttons (orange primary with navy text, navy secondary, sky outline, orange text; 48 px tall, 12 px corners); press feedback (98% scale, deeper colour, sky flash on rows, haptic on phones); 2 px orange focus outline; skeleton loading; empty states with the next action | Done; **Needs hand test** of haptics on the phone | All screens |
| 3 | Labels above every field; no floating labels left | Done | `test/layout_overflow_test.dart` fails if `labelText:` comes back |
| 3 | White sidebar from 1024 px; full-width ☰ slide-in menu from 600 to 1023 px (closes with ✕, a link or Escape); bottom bar with an orange-tint pill on phones | Done; **Needs hand test** in the signed-in web app | Web at 1440, 900 and 390 px |
| 4 | Login, Onboarding (step bar, fixed Back/Continue), Home (phone and web), Invoices, Invoice view, New invoice and quotation, picker, Quotations, Customers, New customer (bottom sheet on phones), Items, Record payment, Reports (period, tiles, weekly chart, GSTR-1 card, exports), More, Settings | Done; the lists **Need hand test** with real data | `docs/design/*.png` beside the app |
| 5 | No overlapping text: every screen that runs without a login, 320–1920 px, text scale 1.0 and 1.3, light and dark, GST and not | Done (passes); lists that need the server are a hand test | `test/layout_overflow_test.dart` |
| — | Version 1.4.0 (build 20261127) | Done (APK built, not installed) | Login screen; Settings; install `build/app/outputs/flutter-apk/app-release.apk` over the old app |

## Change request of 25 Nov 2026, part B (`docs/CHANGE_REQUEST_2026-11-25_STANDARDS.md`)

Branch `cr-2026-11-25-standards`, version 1.5.0 (build 20261128). **Not on
`master` yet: waiting for the owner's check with real data and approval of
the screenshots.**

Database, 26 Nov: backed up first (`backups/20261127_*`, 37 invoices, 31
customers, 32 items, 4 businesses; again as `backups/20261127b_*` before B4),
each migration dry-run and rehearsed in a rolled-back transaction, then
applied: `20261127000000` (B1), `…0001` (B3), `…0002` (B2), `…0003` (B4),
`…0004` (B4 schedule). All nine SQL test files in `supabase/tests/` pass on
the live database. The live 1.4.0 app keeps working (older versions are
recalculated by the server; nothing they use was removed). Edge function
`privacy-daily` deployed; its first run removed nothing (0 accounts, 0
sign-ups, 0 exports).

| # | Change | Status | Where to check |
|---|---|---|---|
| B1 | Delete invoice (soft delete, `deleted_at`/`deleted_by`, owner-checked server function; hidden from every list, total, report, GSTR-1, export and balance; payments go with it; number never reused; Undo for 10 s; accountants can't) | Done (database tested live); **Needs hand test** in the app | Invoice view ⋯ and list ⋮ → Delete invoice. `supabase/tests/20261127_cr25b_b1_regressions.sql`, `test/cr25b_b1_test.dart` |
| B1 | One warning dialog; GST line only for GST businesses; "Edit anyway" once for invoices dated before today (GST only); note after changing name, address, GSTIN, bank, UPI, or a product's HSN/SAC or GST rate | Done; **Needs hand test** | Test plan INV-026…030, SET-009 |
| B1 | Audit log of every delete, restore and edit, with old values (not shown in the app) | Done (tested live) | `audit_log` in Supabase |
| B2 | Totals on the server over all matching invoices (no deleted, draft or cancelled): Home, invoice and customer tiles, customer history, Reports (summary, customer-wise, item-wise, GSTR-1 checks) | Done (650-invoice SQL test equals direct sums, live); **Needs hand test** | `supabase/tests/20261127_cr25b_b2_regressions.sql` |
| B2 | Invoices, Quotations, Customers, Items and the Record payment picker page on the server: "Showing 26–50 of 287", ‹ Prev 1 2 3 … Next ›, 10/25/50/100 remembered per user from 600 px; pages of 25 with "Page 2 of 12" on phones; search, filters and sort on the server, back to page 1 on change | Done; **Needs hand test** with real data | `test/cr25b_b2_test.dart`; NAV-012, NAV-013, SRCH-005 |
| B2 | Web address keeps tab, page, search, filters, sort and dates | Done; **Needs hand test** | NAV-014 |
| B2 | Date presets on Invoices and Reports (Today … This year = financial year, Custom) | Done | RPT-013 |
| B2 | Exports (PDF, Excel, CSV, Tally) include every matching invoice, with the business, dates, count and time at the top | Done; **Needs hand test** | RPT-014 |
| B2 | Status badges always have words | Done (since the redesign) | `StatusChip` |
| B3 | All money maths in integer paise (`Paise`, `LineMoney`, `DocumentMoney` in `lib/money.dart`); one rounding rule written in `money.dart` and `NOTES.md` (CGST = tax ÷ 2 half-up, SGST = tax − CGST); PDF rate-wise lines are sums of lines | Done | `test/money_test.dart` (5% on ₹101, 3 × ₹33.33 @ 18%, 0%, mixed rates, ₹1.25 crore) |
| B3 | `save_invoice` repeats the maths and refuses a mismatch from this app; older versions are recalculated; saved invoices keep their amounts | Done (tested live) | `supabase/tests/20261127_cr25b_b3_regressions.sql` |
| B4 | Privacy Notice `/privacy` and Terms `/terms`, linked from the website footer, sign-up, login and Settings | Done as **drafts: a lawyer must review them before launch**; the owner's details are placeholders (`NOTES.md`) | `website/privacy.html`, `website/terms.html` |
| B4 | Unticked consent box at sign-up; `consents` table (time, version, web/Android, IP, device); one-time "We've updated our Privacy Notice" screen | Done (tested live in SQL); **Needs hand test** of a real sign-up | AUTH-017, AUTH-018 |
| B4 | Settings → Your data and privacy: Download my data (ZIP: JSON, Excel, every invoice PDF; 24-hour link), Correct my data, Nominate a person, Raise a concern (30-day due date, status), grievance contact, Delete my account (30 days' grace, a login cancels it, day 31 deletes everything) | Done (deletion tested live with made-up logins and a moved clock); **Needs hand test** of the download | SEC-008…010; `supabase/tests/20261127_cr25b_b4_regressions.sql` |
| B4 | Daily clean-up (sign-ups never completed after 30 days, deletions on day 31, audit entries anonymised after a year, exports after 7 days) | Done: `privacy-daily` deployed and scheduled at 03:00 IST | `cron.job` in Supabase |
| B4 | `docs/SECURITY.md`, `docs/BREACH-RESPONSE.md`, web storage notice, optional fields marked "(optional)" | Done (breach-plan names are placeholders) | SEC-011 |
| B4 | Raise a concern emails the grievance contact | **Not started**: needs an email service (super admin change request) | `NOTES.md` |
| B5 | Nightly encrypted backup workflow (02:30 IST, database and every Storage file, gpg AES-256, R2 daily + monthly, keep 30 + 12, size check) and `docs/RESTORE.md` | **In progress**: written and tested locally (encrypt/decrypt round trip, counts, pruning); needs the owner's R2 bucket and GitHub secrets, then a run | `.github/workflows/nightly-backup.yml`, `tool/backup/` |
| B5 | One tested restore into a test Supabase project | **Not started**: needs the owner's test project. B5 is not Done until this passes | `docs/RESTORE.md` |
| B5 | Download my backup on More → Sync and backup, with the last download date on this device | Done; **Needs hand test** | SYNC-008 |
| — | Test plan: 27 new cases; Known Issues KI-01/KI-02 marked fixed | Done | `docs/Simplek_Test_Plan.xlsx` |
| — | Version 1.5.0 (build 20261128) | Done; APK not built yet | Login screen; Settings |

## Change request of 26 Nov 2026: login, sign-up, log-out and fingerprint fixes (`docs/CHANGE_REQUEST_2026-11-26_LOGIN_FIXES.md`)

In version 1.5.0 (build 20261128), with part B. No database change.

| # | Change | Status | Where to check |
|---|---|---|---|
| L1 | Fingerprint only when the app opens with a saved login or after 45 s in the background; never after a password or email-link login; per account; offer once per account; no "Log in with password instead" loop | Done (widget tests); **Needs hand test** on the phone (test 4 below) | `lib/app_lock.dart`; `test/login_fixes_test.dart` |
| L2 | Pending sign-up kept with email and time; used only for that email, < 24 h, no password yet, from the email link; otherwise deleted; "Cancel and log out" on Set your password | Done (tests); **Needs hand test** (tests 3, 5) | `PendingSignup`, `pendingSignupApplies` |
| L3 | `password_set` in metadata; an existing account gets "You already have a Simplek account. You're now logged in." and Home; set-up whenever an owner has no profile (not accountants with shared businesses); set-up never overwrites a saved profile; Log out on set-up; straight to Home after set-up | Done (tests for the rules); **Needs hand test** (tests 2, 5) | `isExistingAccount`, `needsBusinessSetup`, `_finish` |
| L4 | One log-out for every button: warns about unsynced items (kept), logs out even offline, clears the old business profile, files, terms, view, choices and pending sign-up, closes every screen; a different account signing in clears the previous one first | Done (test: the next account sees a blank profile); **Needs hand test** (test 1) | `lib/session.dart` |
| L5 | Plain sign-up email errors (rate limit, other); "Open the link on this phone…" | Done | Sign-up, Check your email |
| L5 | Custom SMTP and redirect URLs in Supabase | **Owner's step** | `NOTES.md` |

Hand tests on the phone (Android), from the change request:
1. Log in as account A, log out → login screen; log in as B → none of A's business details.
2. Start sign-up on the phone for an email that already has an account, tap the link on the phone → "You already have a Simplek account", Home; no password or set-up page; the profile is unchanged.
3. Start sign-up on the phone, then log in as another account → normal Home, no "Set your password".
4. Quick unlock on: password login → no fingerprint; close and reopen the app → fingerprint once.
5. On "Set your password" and "Set up your business", Cancel and Log out work.
