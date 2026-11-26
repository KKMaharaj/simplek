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
and it was pushed to `master` the same day. Look only: no screen's data or rules
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

Not started.
