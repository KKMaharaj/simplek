# Simplek: instructions for Claude Code

Follow `BUILD-STANDARDS.md` (in this folder) in everything you build, unless the project's own
requirements say otherwise. The project's own requirements are:
- the owner's change requests in `docs/` (for example `CHANGE_REQUEST_2026-11-25.md` and
  `UI_REDESIGN_2026-11-25.md`);
- the owner's instructions in chat.

Where they differ from `BUILD-STANDARDS.md`, they win. Everything they don't mention follows
`BUILD-STANDARDS.md`.

## Work queue, in this order

1. `docs/CHANGE_REQUEST_2026-11-25.md`: sign-up, customers, the business GST rule, the item
   picker, removing SKU, the description, the compact PDF, and the address with State/District.
   11 changes.
2. `docs/UI_REDESIGN_2026-11-25.md`: the new light, three-colour look for phone and web. Screen
   images are in `docs/design/`.
3. `docs/CHANGE_REQUEST_2026-11-25_STANDARDS.md`: deleting invoices with a GST warning, totals
   from all data, paisa-exact GST, privacy (DPDP), and nightly backups. 5 changes.

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
