# Simplek: instructions for Claude Code

Follow `BUILD-STANDARDS.md` (in this folder) in everything you build, unless the project's own
requirements say otherwise. The project's own requirements are:
- the owner's change requests in `docs/` (for example `CHANGE_REQUEST_2026-11-25.md` and
  `UI_REDESIGN_2026-11-25.md`);
- the owner's instructions in chat.

Where they differ from `BUILD-STANDARDS.md`, they win. Everything they don't mention follows
`BUILD-STANDARDS.md`.

## Work queue, in this order

**Urgent, do next:** `docs/CHANGE_REQUEST_2026-11-26_LOGIN_FIXES.md`. Finish the change you're on,
then fix log-out, sign-up, the stuck "Set your password" screen, set-up overwriting a saved business
profile, and the fingerprint asked after a password login. Then carry on with the queue below.

1. `docs/CHANGE_REQUEST_2026-11-25.md`: sign-up, customers, the business GST rule, the item
   picker, removing SKU, the description, the compact PDF, and the address with State/District.
   11 changes.
2. `docs/UI_REDESIGN_2026-11-25.md`: the new light, three-colour look for phone and web. Screen
   images are in `docs/design/`.
3. `docs/CHANGE_REQUEST_2026-11-25_STANDARDS.md`: deleting invoices with a GST warning, totals
   from all data, paisa-exact GST, privacy (DPDP), and nightly backups. 5 changes.
4. `docs/CHANGE_REQUEST_2026-11-26_SUPER_ADMIN.md`: the super admin panel (web only), plans with
   250 free invoices (deleted ones still count), usage tracking, one email = one account,
   temporary-password reset, and the email, WhatsApp and Razorpay settings. Design:
   `docs/design/AdminDashboard.png`.
5. `docs/CHANGE_REQUEST_2026-11-26_TALLY.md`: replace the stub Tally export with the owner's proven
   kit (`docs/reference/tally-integration-kit/`), adapted for many items, GST rates, services,
   non-GST businesses and partial payments. The kit already imports correctly into real
   TallyPrime, so keep its XML structure exactly.
6. `docs/CHANGE_REQUEST_2026-11-26_INVOICE_FOOTER.md`: small. The PDF footer line becomes "This is a
   computer-generated invoice, made with Simplek.", where the word "Simplek" links to
   https://simplek.in. It can be done at any time, as its own commit.

Finish and test each file before the next. After each file, update `CHANGE-STATUS.md` and send
the owner screenshots before pushing to `master`.

## Before you start
- Read `docs/PROJECT_SUMMARY.md`: how the project is built and released, and its ground rules.
- Read `docs/STANDARDS_GAP_REVIEW.md`: where the app does not yet meet the standard. Only fix those
  items when a change request asks for them.

How to work (from `BUILD-STANDARDS.md` section 18):
- Pushing to `master` deploys the web app to real users. Push only finished, tested work.
- Commit each change separately, with a clear message (for example `change 25.07: select a new
  product after adding it`).
- After each change request, write `CHANGE-STATUS.md`: a table of number, change, status (Done /
  In progress / Not started / Needs hand test) and where to check it.
- Keep `NOTES.md` for decisions, placeholders ("Replace before launch") and anything that needs
  the owner's confirmation.
- Never mark something done that wasn't tested. Never delete data or history to make a change
  easier; deactivate or hide instead.
- Don't edit the owner's change-request files in `docs/` unless asked. Read them fresh before each
  piece of work. Don't restore old copies of them from git.
