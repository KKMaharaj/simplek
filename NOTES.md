# Notes: decisions, placeholders and open questions

## Replace before launch

- **District list.** `assets/data/states_districts.json` has the 36 states and
  UTs but no districts yet. The LGD district download needs a CAPTCHA, so the
  owner downloads it: https://lgdirectory.gov.in/downloadDirectory.do →
  Districts, all states, XLS. Then save it as CSV (Excel) and run
  `dart run tool/import_lgd.dart <file.csv> <download date>`, which also writes
  `supabase/migrations/20261126000002_seed_states_districts.sql`. Until then
  the District field is typed by hand.

## Needs owner's confirmation

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
