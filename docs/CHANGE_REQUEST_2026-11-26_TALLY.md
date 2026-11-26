# Simplek — Change Request, 26 Nov 2026: a real TallyPrime export, from the owner's kit

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner. He used this Tally export in another project (the Rejwin store) and wants
Simplek's customers to have the same: their Simplek sales go straight into their accountant's
TallyPrime.
**The kit:** `docs/reference/tally-integration-kit/`. **Read its `README.md` first, all of it.**
Its "rules that make TallyPrime accept the file" (1–11) came from real failed imports. Keep every
one.
**Order:** after the earlier files in the `CLAUDE.md` work queue. It uses:
- soft-deleted invoices (B1);
- server-side totals (B2);
- paise maths and round off (B3, 19 Nov);
- the states table (change 11).

**The kit is proven.** The owner confirmed on 26 Nov 2026 that its files import correctly into
real TallyPrime. The README's note that the final import was "pending" is out of date; ignore it.
So **don't change the kit's XML structure.** Simplek's files must look like the kit's samples. Only
the data differs.

---

## T0. Today, and why it must change

`_exportTallyXml()` in `lib/main.dart` (around line 6609) writes, for each invoice, a Sales voucher
holding only the date, number, party name and total amount. It has:
- no ledger lines;
- no tax lines;
- no item or inventory entries;
- no masters;
- no `REMOTEID` or `GUID`.

TallyPrime rejects such vouchers or imports them empty, and importing twice would duplicate them.
**Replace it completely** with the kit's exporter.

## T1. Where it runs

- **Port `server/tally.ts` to a Supabase edge function** `tally-export`. It is TypeScript, so it
  moves to Deno almost as it is.
- Replace Prisma with Supabase queries. Copy the kit's `escapeHtml` and `istParts` helpers
  unchanged.
- The function checks that the caller owns the business, **or is an accountant with view access**:
  accountants are the main users of this. It then reads that business's data only.
- It returns the XML file and the check summary.
- Keep the kit's structure: `tallyLedgers` / `saveTallyLedgers` / `fixedMasters` /
  `invoiceLines` / `itemVoucher` / `receiptVoucher` / `tallyExport`.

## T2. Adapting the kit to Simplek

The kit was built for one shop selling one product at 5% GST. Simplek has many businesses, many
items, several GST rates, services, and businesses without GST. Make these changes, keeping all 11
rules:

1. **Settings per business** (not one shared set): a `tally_settings` table (business, JSON of
   names), with RLS.
   - **Company name in Tally** defaults to the business name; it is used in `SVCURRENTCOMPANY`.
   - The help text says: "Type it exactly as your company is named in TallyPrime".
2. **One stock item per Simplek product (goods):** the product name, its HSN, its unit, and its GST
   rate in `GSTDETAILS.LIST` (CGST and SGST = rate ÷ 2, IGST = rate).
   - This replaces the kit's single fixed stock item `Rejwin, 1000 ml` and HSN `30049011`.
   - **Units:** map Simplek's UQC codes to Tally unit names (NOS → "Nos", KGS → "Kgs", and so on).
     The mapping is editable in Tally settings.
   - Two products with the same name get their HSN added to the stock-item name, the same idea as
     rule 10.
3. **Services** (items with a SAC code) are **not stock items**. They go as ledger lines to a
   "Service sales" ledger inside the same invoice-view voucher.
   - Test a goods-only invoice, a services-only invoice and a **mixed** one in TallyPrime.
   - If the mixed one fails, add the fallback switch in item 9 and note it in `NOTES.md`.
4. **One sales ledger and one tax ledger per GST rate,** for every rate the business has used
   (0, 0.25, 3, 5, 12, 18, 28 and so on), with editable names. Defaults follow the kit's pattern:
   - `Sales GST 18% Local` / `Sales GST 18% Interstate` (and `Service Sales GST 18% Local` /
     `… Interstate` for services);
   - `Output CGST 9%`, `Output SGST 9%`, `Output IGST 18%`.
   - An invoice with several rates gets one tax line per rate. Intra-state versus inter-state is
     decided by comparing **state codes** (CR-25 changes 4 and 11).
5. **Business not registered under GST** (`isGstRegistered = false`):
   - one `Sales` ledger, and stock items with GST "Not Applicable";
   - no tax ledgers and no tax lines;
   - parties marked "Unregistered/Consumer";
   - no `PARTYGSTIN` or `PLACEOFSUPPLY`.
6. **Receipts:** **one Receipt voucher per Simplek payment** (Simplek allows partial payments).
   - GUID `simplek-receipt-<payment id>`; number `R-<invoice number>-<n>`.
   - The party is credited `Agst Ref` the invoice number, for the payment amount.
   - The debit goes to the ledger for the payment method:
     - `cash` → Cash;
     - `upi` → UPI receipts;
     - `bank_transfer`, `card` or `cheque` → Bank.
   - In accounting view, per rule 2 (`ALLLEDGERENTRIES.LIST`).
7. **Credit notes and discounts:** Simplek has neither yet.
   - **Hide** the "Credit notes" choice.
   - Don't write the Discount Allowed master.
   - Keep the kit's code paths dormant, so they switch on when those features arrive.
8. **Round off:** Simplek totals are rounded to the rupee (19 Nov). The kit's
   `roundOff = total − (items + tax)` goes to the Round Off ledger; keep it exactly.
9. **Optional switch, "Export items to Tally as": Stock items (default) / Ledger lines only.**
   Many small businesses don't keep stock in Tally. "Ledger lines only" writes every line to the
   rate-wise sales ledgers, with no stock items or units.
10. **Party (customer) masters:** built from the invoice's customer fields plus the current customer
    record: address, PIN, state name (from the states table, spelled exactly as Tally expects,
    e.g. "Karnataka"), mobile, email, GSTIN and registration type. Same-name customers get the
    mobile added (rule 10).
11. **GUID prefix `simplek-`:**
    - `simplek-sales-<invoice id>`, `simplek-receipt-<payment id>`.
    - Invoice IDs are UUIDs, so they're unique across businesses.
    - **Never change the prefix after the first export** (rule 4).
12. **Deleted invoices** (CR-25B B1) are never exported. If one was exported before it was deleted,
    show the kit's **red warning**: "Exported to Tally on [date] and later deleted. Cancel it in
    Tally by hand."
13. **Bill-wise credit period:** use the invoice's own due date in days (due date minus invoice
    date), not a fixed 30.

## T3. Database (new migration; unique 14-digit version; dry run first)

- **`tally_exports`:** business, guid (primary key with business), kind, number,
  `first_exported_at`, `last_exported_at`, `count`. The kit's `TallyExport` table, with RLS. Leave
  out the kit's `INSERT` of old Rejwin data.
- **`tally_settings`** (T2.1), with RLS.
- Ledger renames are written to `audit_log` (CR-25B B1) with who, when, the old name and the new
  name, like the kit's rename log.

## T4. Screens (new look, per `UI_REDESIGN_2026-11-25.md`)

1. **Reports → "Export for Tally"** (replaces today's "Export TallyPrime XML" menu item). Based on
   the kit's `web/TallyExportPanel.excerpt.tsx`:
   - a date range with presets;
   - what to include: **Sales** and **Receipts**, as tick boxes;
   - a short explanation: "For TallyPrime: Import > Transactions (with masters). Importing the same
     vouchers again updates them, without duplicates. Purchases are entered in Tally directly."
   - **A check summary before downloading:**
     - the number of vouchers of each kind;
     - quantity sold;
     - taxable value, CGST, SGST, IGST and total;
     - receipts total;
     - **whether these match Simplek's Reports for the same dates** (B2 server totals);
     - the voucher list with "already exported on [date]";
     - the red deleted-after-export warnings.
   - **Download for Tally:** this marks the vouchers exported. The file is named
     `Tally_<Business>_<from>_<to>.xml`.
   - **Accountants with view access can use this screen.** It's for them.
2. **Settings → "Tally settings"** (owner and accountant can edit; based on
   `web/TallySettings.tsx`):
   - company name in Tally;
   - the ledger names: per GST rate (sales local, sales interstate, service sales, CGST, SGST,
     IGST), plus Round off, Cash, Bank, UPI receipts, the customers' group and the units mapping;
   - the stock-items switch (T2.9);
   - each field shows "Standard: …" when changed;
   - **Save changes** and **Reset to standard names**, at the top and the bottom;
   - the **rename log** (who, when, old name, new name) underneath.
3. **Help:** a short "How to import into TallyPrime" panel with steps (Gateway of Tally → Import →
   Transactions → choose the file → masters included). It notes that the company name must match.

## T5. Tests (port the kit's tests; keep every assertion)

- Port `tests/tally.test.ts` and `tests/tally-06.test.excerpt.ts` (TL7a–TL7i and TS7) to Deno
  tests for the edge function:
  - every voucher's top-level amounts add up to **0.00**;
  - receipts are in accounting view with `ALLLEDGERENTRIES.LIST`;
  - GUIDs are stable between exports;
  - masters come before vouchers;
  - names come from the settings;
  - no voucher has an amount of 0;
  - XML escaping is correct.
- **Add Simplek cases:**
  - a mixed 5% + 18% invoice;
  - a services-only invoice and a mixed goods-and-services invoice;
  - an inter-state invoice (IGST);
  - a non-GST business;
  - two partial payments on one invoice, giving two receipts that together equal the total;
  - a round-off invoice;
  - two customers with the same name;
  - a deleted invoice that was exported, giving the warning;
  - the "Ledger lines only" switch.
- Compare the output structure with the kit's `samples/Tally-sample-export.xml` and
  `samples/Tally-Receipts-corrected-example.xml`.

## Done checklist

- [ ] The kit is copied into `docs/reference/tally-integration-kit/` (already done by the owner's
      assistant). Its rules are kept, and the differences from it are listed in `NOTES.md`.
- [ ] Edge function `tally-export`, the migration, and both screens. The old `_exportTallyXml`
      is removed.
- [ ] All tests pass (`flutter analyze` and `flutter test` too).
- [ ] **Generate sample files from a test business** (goods, services, mixed rates, inter-state,
      non-GST, partial payments) into `docs/tally-samples/`. Check them against the kit's samples:
      same tags, same order, same signs, every voucher sums to 0.00.
- [ ] Send the sample files to the owner with the screenshots. He can import one into TallyPrime
      as a quick final check of the Simplek-only parts (several GST rates, services, non-GST).
      This is a normal release check, not a doubt about the kit.
- [ ] Each change committed separately. `CHANGE-STATUS.md` updated. Screenshots sent to the owner
      before pushing to `master`.
