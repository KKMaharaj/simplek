# Tally integration kit (taken from the Rejwin store)

This kit is for the AI or developer adding a Tally export to another app (Simplex). It is the TallyPrime export from the Rejwin store, rebuilt after the client's first import attempts failed. The final test import by the accountant is still pending. Copy the logic and the XML rules exactly. Change only what connects it to your own database and screens.

## What it does

From the app's billing screen, Accounts pick a date range and press **Export for Tally**. They get one XML file, which they import in TallyPrime with **Import > Transactions** (with masters). The file holds:

1. **Masters**, written only when they are missing (`ACTION="Create"`):
   - the unit and the stock item, with HSN and GST rates;
   - one ledger per customer under Sundry Debtors, with address, state, PIN, mobile, email, GSTIN and registration type;
   - the sales ledgers (local and interstate);
   - CGST, SGST and IGST under Duties & Taxes;
   - Round Off, Cash, Bank and UPI;
   - Discount Allowed, with its GST settings.
2. **Vouchers**, and the user picks which kinds:
   - **Sales:** item invoices with quantity, rate, discount % and amount; the party is billed with `New Ref` and 30 days.
   - **Receipts:** a payment against the invoice (`Agst Ref`), into Cash, Bank or UPI.
   - **Credit notes:** a refund or return against the invoice.

Purchases are **not** exported, on purpose: the client enters them directly in Tally.

Before downloading, the screen shows a check summary for the same dates:
- the number of vouchers of each kind;
- the quantity sold and returned;
- the taxable value, CGST, SGST, IGST and total;
- whether those totals match the app's own sales report;
- each voucher with "already exported on [date]";
- a red warning for invoices that were exported and later deleted, which must be cancelled in Tally by hand.

The **Tally settings** screen lets Accounts type each ledger name exactly as it is in their Tally company (13 names). Every rename is logged with who made it, when, and the old and new name.

## The rules that make TallyPrime accept the file (learned from failed imports)

Keep all of these. Each one fixed a real import failure.

1. **Sales and Credit Notes are invoice-view vouchers.** Use `OBJVIEW="Invoice Voucher View"` and `<PERSISTEDVIEW>Invoice Voucher View</PERSISTEDVIEW>`. The item goes in `ALLINVENTORYENTRIES.LIST`, with `ACCOUNTINGALLOCATIONS.LIST` to the sales ledger inside it. The party, tax, discount, shipping and round-off lines go in `LEDGERENTRIES.LIST`.
2. **Receipts (and Payment, Journal, Contra) are accounting-view vouchers.** Use `OBJVIEW="Accounting Voucher View"`, and put every line in `ALLLEDGERENTRIES.LIST`. If a receipt uses `LEDGERENTRIES.LIST`, Tally drops the lines and the voucher arrives empty.
3. **Debits are negative amounts with `ISDEEMEDPOSITIVE` Yes; credits are positive with No.** The top-level amounts of every voucher must add up to exactly 0.00.
4. **Every voucher has a stable `REMOTEID` and `GUID`** made from its database ID, for example `rejwin-sales-<invoice id>`. Importing the same file again then updates the voucher instead of adding a duplicate. Use your own prefix (for example `simplex-`), but **never change it after the first export**.
5. **The item `AMOUNT` is the invoice's own line value, never rate × quantity.** Any rounding difference goes to the Round Off ledger, so Tally matches the invoice to the paisa.
6. **Discounts:**
   - a percentage discount stays on the item as `<DISCOUNT>`;
   - a rupee discount (coupon or a fixed amount) goes on the Discount Allowed ledger instead;
   - the Discount Allowed master has `APPROPRIATEFOR` GST, `GSTAPPROPRIATETO` Goods and `EXCISEALLOCTYPE` "Based on Value".
7. **Masters come before vouchers** in the file: one `IMPORTDATA` "All Masters" block, then one "Vouchers" block. Both use `SVCURRENTCOMPANY` = the company name exactly as in Tally.
8. **Dates are `YYYYMMDD` in Indian time (IST).** Amounts are rupees with 2 decimals; the app stores money as integer paise.
9. **Never write a voucher with an amount of 0.** Escape every text value for XML (`& < > " '`).
10. **Two customers with the same name** get the mobile number added to the ledger name, for example "Ramesh Kumar (9876543210)". Otherwise Tally merges them into one ledger.
11. **Intra-state sales** go to the local sales ledger with CGST and SGST. **Inter-state sales** go to the interstate ledger with IGST.

## The files

| File | What it is | What to change for Simplex |
| --- | --- | --- |
| `server/tally.ts` | The whole exporter: ledger settings, masters, the three voucher kinds, the export with its summary | Imports at the top (see "Connecting it" below). The default names in `TALLY_DEFAULTS`. The GUID prefix `rejwin-`. The stock item's HSN `30049011` and GST 5% in `fixedMasters`, if Simplex sells other products |
| `server/invoice-snapshot.ts` | The invoice shape the exporter reads (`InvoiceSnapshot`) | Map your invoice data to this shape, or change the fields read in `tally.ts` |
| `server/reports-queries.excerpt.ts` | `invoicesIn` and `creditNotesIn`: invoices and credit notes in a date range, skipping deleted orders | Rewrite them for your tables |
| `server/tally-routes.excerpt.ts` | The four API endpoints: download, summary, and get/save settings | Your router, role check and audit log |
| `server/helpers.excerpt.ts` | `escapeHtml` (XML escaping) and `istParts` (IST dates) | Copy as they are |
| `database/TallyExport.prisma`, `database/migration.sql` | The table recording each exported voucher (GUID, first and last export date, count) | Leave out the `INSERT` part of the migration: it only carried over old Rejwin data |
| `web/TallySettings.tsx` | The ledger names screen, with the rename log | Your UI components |
| `web/TallyExportPanel.excerpt.tsx` | The export screen: dates, the kinds to include, the check summary, the voucher list, the deleted warning | Your UI components |
| `samples/Tally-sample-export.xml` | A sample file made by this exporter, with test data | Compare your output against it |
| `samples/Tally-Receipts-corrected-example.xml` | The corrected receipt shape from the client's change request | Same as above |
| `tests/tally.test.ts`, `tests/tally-06.test.excerpt.ts` | API tests TL7a to TL7i and TS7: balance to 0.00, receipts in accounting view, stable GUIDs, masters first, names from settings, discount maths | Change the helpers that create invoices; keep every assertion |
| `tests/tally-screens.spec.excerpt.ts` | Browser tests for the two screens | Your page paths and labels |

## Connecting it to Simplex

`tally.ts` uses these parts of the Rejwin app. Give Simplex an equivalent for each:

- `prisma`, with these tables:
  - `setting` (a key and JSON value store; the ledger names are saved under the key `tally.ledgers`);
  - `invoice` (`id`, `number`, `issuedAt`, `paidAt`, `paymentMode`, `snapshot` JSON, `tallyExportedAt`, `order`);
  - `creditNote` (`id`, `number`, `createdAt`, `amountPaise`, `reason`, `invoice`);
  - `tallyExport`;
  - `auditLog` and `staff`, for the rename log.
- `audit(actor, action, entityType, entityId, detail)`, which writes the audit log.
- `getSettings().identity.name`, the company name as it is in Tally.
- `salesReport({from, to})`, used only for the "matches reports" check. If Simplex has no sales report yet, return `null` there.
- `order.type` (`online` or `offline`) and `paymentMode` (`Cash`, `UPI`, or anything else, which means bank). These choose the receipt ledger in `PAY_LEDGER`.

## Done means

- All the tests in `tests/` pass against Simplex.
- An exported file imports into a test company in TallyPrime with no errors.
- Tally's day book totals equal the app's sales report for the same dates.
- Importing the same file twice does not create duplicate vouchers.
