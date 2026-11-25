# Simplek against BUILD-STANDARDS.md: gap review (25 Nov 2026)

Written from the code (build 1.2.0), `docs/PROJECT_SUMMARY.md` and the open change requests.

**Covered by** says whether an open change file already fixes the gap:
- **CR-25** = `docs/CHANGE_REQUEST_2026-11-25.md`
- **CR-25B** = `docs/CHANGE_REQUEST_2026-11-25_STANDARDS.md` (owner's decisions, 25 Nov 23:42)
- **UI-25** = `docs/UI_REDESIGN_2026-11-25.md`
- **—** = not requested yet. **The owner decides** which of these become change requests.
  Claude Code: don't fix the "—" items unless a change request asks.

## A. Deliberate differences (the owner's decisions win over the standard)

| Standard | Simplek, on purpose |
|---|---|
| 8.3.6: UPI logo under the QR | Logo beside "Scan to pay", to keep the payment box compact (CR-25 change 10). |
| 8.3.5: amount in words full width; HSN under the description | Layout copied from the owner's approved reference: words beside the totals, HSN in its own column. |
| 8.1 / 8.2: business state and code printed in the header | Header "State (code)" line removed (CR-25 change 11). Place of supply keeps its code. |
| 1: notes up to 1,000 characters | Invoice description up to 300 characters (CR-25 change 9). |
| 3: OTP sign-up and Forgot password | Postponed until the owner has a domain and custom email (owner, 19 Nov). When built, follow section 3: 6 digits, 5–10 minutes, resend after 30 s, at most 5 tries. |
| 8.2: per-invoice snapshot; invoices never edited or deleted after issue | Owner: businesses may edit and delete their invoices. GST businesses get a warning; delete is a soft delete with Undo (CR-25B B1). |
| 10: PDFs generated on the server | Generated in the app, so they work offline on the phone. The same code is used on web and phone. |

## B. Gaps that matter before more customers use it

| # | Standard | Simplek today | Covered by | Priority |
|---|---|---|---|---|
| B1 | 8.2 Editing safety: each invoice keeps a **snapshot** of seller, buyer, items, tax, bank/UPI, terms, logo | The PDF is drawn from the **current** business profile and the product's current HSN, so editing the profile or a product changes old invoices | Owner's decision: warning only (CR-25B B1) | — |
| B2 | 5: totals and statistics use **all** matching rows | Home adds up the newest 100 invoices; Reports and GSTR-1 the newest 500 | CR-25B B2 | — |
| B3 | 8.1: one documented rounding rule; CGST + SGST must equal the tax | CGST/SGST can be 1 paisa off (e.g. 5% on ₹101) | CR-25B B3 | — |
| B4 | 1 / 8.2: GSTIN pattern **plus checksum**; lookup shows the real status and is never "verified" on failure | Pattern only; the lookup shows "Active" when the provider sends no status | CR-25 change 4 (added today) | — |
| B5 | 8.5: invoices not edited after issue; cancel = "CANCELLED" with a credit note | Issued invoices can be edited freely; no cancel or credit note | — | Medium (needed before GST filing support) |
| B6 | 8.6: GSTR-1 tables B2B, **B2CL, B2CS, HSN summary, Documents issued**, portal JSON, period lock after filing | Only B2B/B2C lists and Excel/CSV/Tally exports | — | Medium |
| B7 | 2: **PIN code first**, auto-filling district and state (India Post API), with a landmark field | Free-text address | CR-25 change 11 (updated today) | — |
| B8 | 8.1: CGST/SGST versus IGST decided by comparing **state codes**, never typed names | Check the code: it may compare state names | CR-25 changes 4, 6, 11 (updated today) | — |
| B9 | 4: Busy state, 98% press, 2 px focus outline, disabled at 50% with a reason, ~3 s toast, skeleton loading, empty states with a next action | Partly | UI-25 (updated today) | — |
| B10 | 6: sidebar only from 1024 px, ☰ slide-in menu below; an automatic "no sideways scroll" test at all listed widths | Sidebar from 900 px; no such test | UI-25 (updated today) | — |
| B11 | 1: dates on screen as **DD MMM YYYY** ("21 Nov 2026"); DD/MM/YYYY on documents | dd/mm/yyyy everywhere | UI-25 (updated today) | — |
| B12 | 1: warn on duplicates (same mobile or email) with "Add anyway"; warn on unsaved changes | Not present | — | Medium |
| B13 | 3: password rule "8+ characters **with a letter and a number**", shown before typing; real eye button | 8+ characters only | — | Medium |
| B14 | 5: server-side pagination, 25 rows, page/filter in the URL | Lists load up to 200 rows at once | CR-25B B2 | — |

## C. Needed before launch or paid plans

| # | Standard | Simplek today | Priority |
|---|---|---|---|
| C1 | 12 DPDP: Privacy Notice page; unticked consent box at sign-up; download / correct / delete my data; grievance contact; breach plan | CR-25B B4 (core duties apply from May 2027) | — |
| C2 | 11: audit log for invoice edits, exports, accountant access changes | None | Medium |
| C3 | 11 / 17: daily backups and one tested restore; error logging (e.g. Sentry); uptime check; written rollback plan (Cloudflare Pages can redeploy an earlier version) | Manual backups only (`backups/20261115_*`). Nightly encrypted backup plus a user download are in CR-25B B5. Error logging and uptime monitoring are still open | — |
| C4 | 8.2: business profile fields: legal name, constitution, WhatsApp number, website, account number typed twice, licence numbers with "show on invoice", composition scheme (then **BILL OF SUPPLY**), show bank/QR on paid invoices | Most missing | Medium |
| C5 | 8.3: PDF file name `INV-2026-27-0028_Customer-Name.pdf` | `invoice_INV_2026-27_01.pdf` | Low |
| C6 | 1: store mobiles as `+91XXXXXXXXXX` | 10 digits | Low (only if messaging is added) |
| C7 | 13: email and WhatsApp sent by the server, with templates, a queue and delivery status | The phone's share sheet and the user's mail or WhatsApp app | Later |
| C8 | 17 / launch: real app ID (not `com.example.simplek`) and a release signing key | Debug key, example ID. **The owner's developer will handle this** | — |
| C9 | 18: `REQUIREMENTS.md`, `TECHNICAL-SPEC.md`, `NOTES.md`, and `CHANGE-STATUS.md` after each change request | `PROJECT_SUMMARY.md` and `PROJECT_TRACKER.md` only | Low (`CLAUDE.md` now asks for `CHANGE-STATUS.md` and `NOTES.md`) |

## D. Already in line with the standard

- GST rules: CGST + SGST within a state, IGST otherwise.
- Indian number grouping, and amount in words in lakh and crore.
- Atomic invoice numbering per business, document type and financial year; double-tap-safe saves.
- Customers and products archived, not deleted.
- Five invoice colour schemes matching section 8.4.
- IFSC lookup.
- Sample invoice preview in Settings.
- Accountant view-only access checked on the server.
- Tester checklist in Excel (`docs/Simplek_Test_Plan.xlsx`).
