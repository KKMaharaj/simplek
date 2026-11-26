# Notes: decisions, placeholders and open questions

## Replace before launch

- Nothing yet for this change request. (The LGD district list was imported on
  26 Nov 2026; to refresh it later, see `supabase/imports/README.md`.)

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

### Part B (CR-25B), from 27 Nov 2026

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
- **B3 on the server:** `save_invoice` works every amount out again. The app
  sends `money_rule: 'paise-v1'`; then any difference is refused ("…do not
  match the server's calculation. Update the app and try again."). Older app
  versions don't send it: the server stores its own amounts instead of theirs,
  so they keep working and the database always follows the rule. In rare
  cases an older version's screen or PDF can then differ by a paisa (or a
  rupee at a round-off boundary) from what is stored, until it is updated.
  Invoices saved before 27 Nov keep their stored amounts.
