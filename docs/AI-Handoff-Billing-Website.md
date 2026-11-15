# AI handoff: business profile and billing website

Prepared for a new billing-only e-commerce website, based on the Simplek application. Last reviewed against the Simplek source on 15 November 2026 (commit `bbec152`). Section 16 lists what changed since the 4 October 2026 version.

## 1. Copy this brief to the next AI

Build a responsive, authenticated billing module for my e-commerce website, using the existing website's technology stack where possible. Reuse the business-profile experience and billing behavior described below. This is not a request to build a storefront, shopping cart, stock-management system, shipping platform, or payment gateway unless separately requested.

Prioritize business onboarding, editable business settings, bank and tax lookups, payment QR generation, customer/product selection, invoice creation, preview, download, and sharing. Keep quotations optional. Protect each business's data and preserve historical invoices when profiles, customers, or products change.

Use this document as a specification, not as proof that every feature already exists. Read section 15 before reusing any behavior: it lists current Simplek defects that must not be reproduced. Features are labeled **Existing**, **New addition**, or **Production improvement**. Do not invent API capabilities, expose API secrets, or present generated QR codes as confirmed payments. Deliver working integrations, migrations, tests, setup instructions, and clear statements about anything requiring a provider account or credentials.

Terminology: the user's reference to “UKD” is interpreted here as **UPI ID**, the payment address used to generate the QR code.

## 2. What actually exists today

| Capability | Verified current behavior | Website treatment |
|---|---|---|
| Business onboarding/settings | Owner/business identity, tax settings, contacts, bank details, branding, terms, payment QR | Reproduce the experience |
| IFSC lookup | Razorpay IFSC endpoint fills bank name and branch | Reuse via a backend adapter |
| GSTIN lookup | Supabase Edge Function calls gstinapi.in; fills business/customer name and address | Reuse with server-side credentials |
| PIN-code lookup | No implementation found in current application source | Add explicitly; see section 6 |
| UPI QR | Locally generated from UPI ID, payee name, INR | Reproduce; no API needed to draw the QR |
| Branding | Logo, uploaded/drawn signature, uploaded QR; private cloud media storage | Use browser uploads and private object storage |
| Invoice appearance | Five palettes and a real sample invoice preview | Reproduce in settings |
| Payment terms | Separate invoice/quotation terms; editable defaults | Copy into each new document |
| Due date | Invoice date plus configured number of days | Do not confuse with a fixed day of the month |
| Numbering | Owner-, document-type-, and financial-year-specific allocation | Adapt ownership to the website's business model |
| Delete customer/product | Archive active catalogue entry; retain historical records | Preserve this behavior |
| Sharing | Android attachment sharing plus WhatsApp chat/message options | Implement a browser-specific equivalent |
| Invoice save | One database transaction (`save_invoice`), retry-safe through a client-chosen invoice id | Reuse the function or reproduce its guarantees |
| Quotation conversion | One database transaction (`convert_quotation_to_invoice`); a repeat returns the same invoice | Reuse if quotations are in scope |
| Payments | Manual payments through `record_invoice_payment`, which checks ownership and ignores a repeated request id | Reuse; there is no payment history or reversal yet |

“Existing” means found in source, not that a provider's live account, credits, or every device behavior was revalidated for this document.

## 3. Business onboarding and editable settings

### Suggested onboarding sequence

1. Sign up/sign in; establish the business owner or membership.
2. Enter business identity and tax details. If GST-registered, enter and verify GSTIN.
3. Configure invoice/quotation prefixes, due-date defaults, and terms.
4. Add business logo, signature, payment details, and UPI ID or uploaded QR.
5. Preview a sample invoice, choose a palette, and save the profile.
6. Allow all applicable settings to be revisited from Business Profile & Settings.

The current mobile flow requires GST verification before advancing when GST-registered. Do not silently replace verification failure with a success state. Decide explicitly whether the website may save an unverified draft profile during provider downtime.

### Field inventory

| Group | Fields |
|---|---|
| Identity | Owner name, business name, business address |
| Contacts | Business phone, email |
| Tax | GST-registered yes/no, GSTIN, PAN, GST registration type, business state, default place of supply |
| Documents | Invoice prefix, optional quotation prefix, financial-year display, default due-after days, invoice terms, quotation terms |
| Bank | IFSC, bank name, branch, account number |
| Payments | UPI ID, optional uploaded payment QR |
| Branding | Logo, uploaded or drawn signature |
| Appearance | Invoice palette; application light/dark/system theme is a separate setting |
| New address fields | Address lines, PIN code, locality/post office, city/town, district, state, country |

Keep account numbers, IFSC, PIN codes, phone numbers, and GSTIN as strings. Account numbers must not lose leading zeros. Do not infer the bank-account holder's identity from IFSC.

Use searchable state/union-territory selection and controlled values rather than spelling-dependent tax comparisons. Keep profile contact information distinct from authentication credentials: editing a business email must not implicitly change login identity.

### Defaults and historical documents

**Existing:** terms and due dates are copied into new invoices and can be edited. Despite the old database field name `default_due_day`, the present implementation means **days after invoice date**, with a default of seven days. The original column constraint is 1–31.

**Production improvement:** use an unambiguous field such as `default_due_after_days`. If a fixed monthly due day is wanted, model it as a separate mode and define short-month handling. Store the computed date on the invoice.

Changing defaults must not silently rewrite issued invoices. Existing sample interest/payment wording is business-specific, not a universal legal requirement; let the merchant review and replace it.

## 4. IFSC lookup: exact existing mechanism

**Existing input flow**

1. Trim the input and convert it to uppercase.
2. Apply the current syntax check: `^[A-Z]{4}0[A-Z0-9]{6}$`.
3. When valid, request `GET https://ifsc.razorpay.com/{IFSC}`.
4. Map `BANK` to bank name and `BRANCH` to branch.
5. Show loading, success, invalid/not-found, or temporary-unavailable feedback. Bank and branch remain form fields.

The settings implementation suppresses repeated requests for the same code and prevents overlapping requests. Its duplicate-request suppression should not be copied without fixing retry-after-failure and input-change handling.

**Important boundary:** IFSC identifies a bank branch. It does not retrieve an account number, account balance, account-holder name, or prove ownership. Those details are not filled by our IFSC integration.

**Website contract — proposed**

```http
GET /api/lookups/ifsc/{ifsc}
```

```json
{
  "found": true,
  "ifsc": "<normalized code>",
  "bankName": "<BANK>",
  "branch": "<BRANCH>"
}
```

Debounce completed input, validate again on the server, use a timeout, cache branch metadata, and discard responses for an older input. Provide Retry after a failure. Preserve manual entries during outages rather than erasing the form. A lookup failure must never be labeled “verified.”

Provider reference: [Razorpay IFSC API repository](https://github.com/razorpay/ifsc-api). Its API documentation also lists branch metadata beyond the two fields currently consumed; add extra mappings only if needed.

## 5. GSTIN lookup: exact existing mechanism

**Existing frontend flow**

- Trim and uppercase GSTIN.
- Apply `^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`.
- Call the Supabase Edge Function `gstin-lookup` with JSON `{ "gstin": "<entered GSTIN>" }`.
- Require a successful response with a `data` object.
- Prefer `trade_name` for the displayed business/customer name; fall back to `legal_name`.
- Fill the returned `address` when present; display returned registration status.
- **Known defect, do not copy:** the onboarding success message shows `active` when the provider returns no status (`lib/main.dart`, `_verifyGstin` in onboarding).
- Existing screens title-case returned names/addresses. For the website, preserve the original legal name as well; cosmetic normalization must not corrupt legal identity.

**Existing server flow**

```http
GET https://www.gstinapi.in/v1/gstin/{GSTIN}?include=profile
x-api-key: <server-side GSTINAPI_KEY>
```

The key is read from the server environment, not from the app. The function permits POST and CORS preflight, validates GSTIN again, and proxies a successful provider response. It has up to three attempts for HTTP 429/502 and caught network exceptions, with 300 ms and 600 ms backoff between attempts. Other provider errors are mapped to readable messages: invalid input, configuration error, exhausted credits, deactivated account, not found, busy, or provider unavailable.

The current function logs remaining credits when provided. It does not implement a complete application-level authentication/rate-limiting policy by itself; verify gateway and server configuration instead of assuming it is protected.

**Important boundaries**

- This is a third-party service integration, not a direct government API connection implemented by Simplek.
- A regex match is format validation, not checksum validation, registration verification, or proof of ownership.
- A successful lookup is not necessarily an active registration. Store and display the actual returned status; do not default an unknown status to “active.”
- Although the request asks for profile data, our current form consumes principally GSTIN, name, address, and status. Do not claim all returned fields are already stored.

**Production improvements**

Use a normalized response containing requested GSTIN, returned GSTIN, legal/trade names, address, status, provider, and checked-at timestamp. Clear verification when GSTIN changes. Handle missing optional data, inactive registrations, mismatched returned GSTIN, and stale responses explicitly. Add authentication, per-user rate limits, provider timeouts, redacted logs, and a short-lived cache appropriate to the provider's terms. Keep credentials in managed server secrets.

Provider reference: [GSTIN API documentation](https://www.gstinapi.in/docs). Recheck account setup, pricing, quotas, and response schema before deployment; this document does not promise free or unlimited access.

## 6. PIN-code autofill — new addition, not an existing feature

Add this to business, customer, and billing/shipping address forms as appropriate. Do not present it as a feature already found in Simplek.

**Proposed behavior**

1. Accept a six-digit Indian PIN code as a string; initial format check `^[1-9][0-9]{5}$`.
2. Once complete, request a backend lookup, for example `GET /api/lookups/pincode/{pincode}`.
3. A candidate upstream endpoint is `https://api.postalpincode.in/pincode/{pincode}`.
4. Interpret the upstream array's `Status` and `PostOffice` collection, not just HTTP 200.
5. Offer locality/post-office choices where multiple results exist. Fill district, state, and country from the selected result.
6. Leave street, building, house number, floor, and landmark for the user. Keep city/town editable: a post-office name or district is not automatically the customer's city.

The [provider response for PIN 110001](https://api.postalpincode.in/pincode/110001), checked while preparing this document, returns multiple post offices and fields including `Name`, `District`, `State`, `Country`, and `Pincode`. The provider's documentation homepage could not be retrieved during this review. Treat this as a candidate integration, not a production SLA or an official India Post service endorsement.

Use a replaceable provider adapter. Verify licensing, availability, quotas, and accuracy before relying on it. Handle empty/error responses, null fields, timeouts, and manual entry. PIN lookup cannot validate a complete delivery address or guarantee courier serviceability. Debounce, cache, and reject stale responses just as for IFSC.

## 7. UPI ID to payment QR

**Existing:** generation is local. No payment-provider lookup is needed to render the image.

Normalize by trimming and lowercasing the payment address. The current syntax check is `^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$`; treat it as a basic input check, not proof that the address exists.

Build a URI with a proper URL/query encoder:

```text
upi://pay?pa=<UPI_ID>&pn=<PAYEE_NAME>&cu=INR
```

`pa` is the payment address, `pn` is the business/payee name when present, and `cu` is INR. Encode that string as a QR image. The Flutter implementation uses `qr_flutter`; PDF output renders a 400-pixel PNG with medium error correction. Browser code should use a maintained browser-compatible QR library rather than Flutter-specific APIs.

Display a preview in settings and include it in the invoice payment section. Render dark QR modules against a white background with adequate quiet space, including in dark mode. Do not obscure the code with branding. The current PDF shows a payment caption and a UPI logo below it.

**Current priority:** valid UPI ID → generated QR; otherwise uploaded QR → fallback; otherwise omit the QR. State that priority in the UI so merchants know which code is being printed.

**Not implemented by this QR:** current URI generation has no invoice-specific amount/reference and no payment verification or automatic reconciliation. Scanning the QR or opening a payment app must not mark an invoice paid. Add gateway/webhook verification or explicitly recorded manual payments separately if needed.

An amount-specific QR is an optional enhancement requiring testing against the chosen UPI/payment integration, not a capability to claim as already built.

## 8. Branding, templates, and media

Provide upload/replace controls for logo, signature, and payment QR, plus a browser canvas for drawing a signature. Preview images before saving. Include the saved branding and bank details in PDFs; omit empty optional fields instead of printing empty labels.

Existing media storage uses the private Supabase `business-media` bucket with PNG/JPEG/WebP types and a 5 MiB limit. Paths are scoped to the authenticated owner, and row-level storage policies restrict access. Profile rows store object paths. The mobile app downloads local copies; the website should use authorized access or short-lived signed URLs, not device file paths.

Validate content type and file signature server-side, restrict dimensions, and avoid unsanitized SVG/HTML uploads. Keep signatures and bank details private. For reproducible historical invoices, version or snapshot branding rather than overwriting the only asset used by old documents.

### Invoice palettes implemented

| ID | Display name | Paper | Ink |
|---|---|---|---|
| `white-red` | White & red | `#FFFFFF` | `#9F1239` |
| `white-blue` | White & blue | `#FFFFFF` | `#1E3A8A` |
| `cream-blue` | Cream & blue | `#FFF4DC` | `#173B67` |
| `yellow-blue` | Light yellow & blue | `#FFF9C4` | `#163A70` |
| `white-green` | White & dark green | `#FFFFFF` | `#14532D` |

Default: white/blue. Settings preview must use the actual document renderer and current form values. Label it SAMPLE and never save it as a real invoice or consume a document number.

The current palette preference is in authenticated user metadata plus a user-scoped cache. For a website with staff or multiple stores, store it on the business profile instead, so appearance belongs to the business rather than an individual staff login.

## 9. Billing behaviors worth carrying forward

- Search customers by name/contact/GSTIN. Provide an inline Add customer dialog; do not require users to type database IDs.
- Search products/services, add an item inline, and support multiple invoice rows with a plus button.
- Each row has description, quantity, rate, GST rate, and calculated amount. Preserve entered values when adding rows or navigating through the form.
- Product/service classification uses the HSN/SAC master. GST product forms search active master entries after at least three characters and require selection. UQC is selected from approved units. Do not invent codes or infer GST rate from HSN/SAC; current rates are entered separately.
- Current calculation baseline: taxable value = quantity × rate; tax = taxable value × GST percentage / 100; total = taxable value + tax. The app splits tax into CGST/SGST when its state comparison indicates intra-state, otherwise IGST.
- Treat that simple state comparison as existing application behavior, not complete tax advice. For the new e-commerce context, have the applicable place-of-supply, shipping, discount, rounding, and tax rules reviewed before production. Use decimal money arithmetic and a documented rounding policy.
- **Existing rounding, do not copy:** Simplek calculates in floating point and lets the database round each stored field to two decimals separately. Components can then disagree with the total: 5% GST on ₹101 is ₹5.05, but CGST and SGST are each stored as ₹2.53. Round once, in paise, and derive one component as the remainder.
- Display available customer name/address/GSTIN/phone on separate Bill To lines. Omit missing details.
- Include amounts in words using Indian rupees/lakh/crore/paise, consistent with printed totals.
- Show seller details, document number/date, due date, recipient, place of supply, line items, tax breakdown, totals, bank/UPI details, terms, and signature as applicable. Assess additional required fields for the actual business; a generated PDF is not proof of statutory compliance.
- Persist invoice and items before presenting a saved preview. **Existing:** `save_invoice(p_invoice_id, p_header, p_items, p_is_edit, p_number_prefix)` writes the header, replaces the items and allocates the number in one transaction. Any failure leaves the previous invoice, its items and the number counter unchanged. The client generates the invoice id before the first attempt, so a retry after a lost response returns the saved invoice instead of creating another. The server decides status, balance and paid amount; the client cannot set them. `sent` means finalized/unpaid, not proof that an email or WhatsApp message was sent.
- The function runs with the caller's permissions, so row-level security still applies. Its accepted header and item fields are listed in `supabase/migrations/20261106_atomic_invoice_payment_saves.sql`; the website must send the same shape or wrap the function in its own API.
- **Existing gap:** editing an invoice to a total below the amount already paid marks it paid with a zero balance, and the overpayment is not shown anywhere. Decide whether the website should block that edit or record a credit.
- Update dashboard/list data after saves, edits, archival, and sync. Ignore out-of-order refresh responses.
- Use archive/soft-delete for customers/products so old invoices and quotations remain intact.

### Recording payments

**Existing:** `record_invoice_payment(p_invoice_id, p_amount, p_payment_method, p_payment_date, p_reference_number, p_notes, p_client_request_id)` locks the invoice, rejects amounts above the outstanding balance and sets the status to `partial` or `paid`. Methods are `cash`, `upi`, `bank_transfer`, `card` and `cheque`.

- It bypasses row-level security, so it checks ownership itself: another business's invoice is reported as "Invoice not found". It is closed to anonymous callers.
- Send a new `p_client_request_id` for each payment the user submits and reuse it on retries. A repeated id returns the original payment, even if that payment settled the invoice.
- **Gaps:** clients cannot read the `payments` table (it has no read policies), so there is no payment history, edit or reversal. The mobile app does not capture reference or notes. Add these explicitly if the website needs them, keeping any new function's ownership check.

### Historical snapshots

**Production improvement:** store seller, buyer, item descriptions, tax settings, payment details, terms, and template version on the issued invoice. Current source does not fully snapshot everything: some previews read the current business profile and customer records. Do not reproduce that limitation as a historical-data guarantee.

## 10. Numbering, tenancy, and data model

Current numbering is separate by authenticated user, document type, and April–March financial year. New owners/years start at `01`; existing owners continue after their highest relevant number. Examples are `INV/2026-27/01` and `QTN/2026-27/01`. Existing documents are not renumbered.

Allocation runs on the database, not by counting frontend rows. A counter row is updated atomically. **Existing:** invoice saves and quotation conversion allocate the number inside the same transaction, so a failed save does not use up a number.

Prefixes accept 1–20 letters, digits or hyphens. Indian GST rules limit an invoice serial number to 16 characters, so a long prefix or a five-digit sequence (`INV/2026-27/10000` is 17) can exceed it. Have the limit confirmed and enforce it on the server.

Unique indexes enforce owner + financial year + normalized document number. Optional manual numbers receive the same protection; duplicate attempts show red errors and do not save. Case and surrounding whitespace must not bypass uniqueness. Do not reset counters on sign-out/sign-in.

The current model effectively uses one business per user. For shared staff access or multiple e-commerce stores, introduce `business_id` and a membership/role table. Scope counters, documents, customers, products, settings, and media to that business. Staff sharing one business must share one sequence; unrelated businesses must not.

### Logical entities

| Entity | Purpose |
|---|---|
| Business profile | Identity, addresses, tax configuration, contacts, bank/UPI details, defaults, palette, media references |
| Business membership (new if needed) | Authorized user, business, role |
| Customer | Contact/address/GST details and archival state |
| Product/service | Name, type, price, UQC, HSN/SAC, configurable tax rate, archival state |
| Invoice + invoice items | Number/date/status/totals and immutable issued-document snapshots |
| Quotation + items (optional) | Separate document sequence, validity, terms, conversion state |
| Document counter | Business, document type, financial year, last allocated number |
| Payment record | Invoice reference, amount, date/method, reconciliation reference; `client_request_id` (existing) prevents double recording |
| Media | Private business-scoped assets and historical versions |
| Lookup metadata (recommended) | Provider, normalized input, verification status/time; avoid storing unnecessary raw personal data |

For integration with existing e-commerce orders, add a unique business/order billing reference or idempotency key so webhook retries cannot bill the same order twice. This is a proposed website addition, not existing order integration.

## 11. Browser sharing and security requirements

Provide PDF download as a reliable baseline. Sanitize document numbers before using them as filenames: `INV/2026-27/01` must not become a directory path. Use `application/pdf`, sensible filenames, loading indicators, duplicate-click protection, and visible failure messages.

**Do not copy mobile sharing assumptions into a website.** Current Android code uses FileProvider URIs and native intents; those are not browser APIs. Feature-detect browser file sharing and provide download/manual-attach fallback. Email attachments require a suitable server mail service or user attachment workflow; do not assume a `mailto:` link attaches a PDF.

WhatsApp chat/message links and PDF file sharing are separate capabilities. Do not promise a browser can reliably open one chosen client chat with a local PDF already attached. Offer clear chat/message and share/download actions. Fully automated WhatsApp document delivery would be a separate approved business-messaging integration with its own setup, consent, and provider rules.

Never ship GST provider secrets or Supabase service-role keys to the frontend. Enforce authorization server-side and in database/storage policies. Configure CORS for intended origins, rate-limit lookups, bound external requests, redact sensitive logs, and partition/clear caches per authenticated business. A hidden frontend field is not an authorization boundary.

## 12. Acceptance tests for the next AI

1. A new user can create, save, reopen, and edit a business profile without another business's data appearing.
2. IFSC lookup normalizes lowercase input, fills bank/branch, handles not-found/outage/retry, and never overwrites newer input with an old response.
3. GSTIN lookup fills supported fields; invalid, inactive, missing-key, out-of-credit, rate-limited, and unavailable states are distinct. Changing GSTIN clears verification.
4. PIN lookup supports multiple post offices and manual address completion. It never invents a street address or equates a district with a city.
5. Generated QR decodes to the intended UPI ID/name/currency, scans in light/dark displays and PDF print, and does not imply successful payment.
6. Logo/signature/QR survive another login/device through authorized storage access.
7. Each palette preview matches the final invoice and does not allocate a number.
8. Due-date/terms defaults apply to new invoices and remain editable; old issued documents do not change when settings change.
9. Two businesses can each start at 01. Two staff members in the same business cannot allocate duplicate numbers, including concurrent saves.
10. Duplicate manual numbers are rejected at database level with visible red feedback. Financial-year boundaries are tested at 31 March/1 April.
11. Failed/retried saves do not create duplicate invoices or partially issued documents.
12. Archiving customers/products removes them from new-document lists but preserves historical invoice contents.
13. Customer/item changes refresh the dashboard without a manual refresh.
14. PDF download and available share paths work with slash-containing numbers; unavailable sharing features fall back clearly.
15. Forms, tax selectors, QR previews, and buttons remain readable at small widths, in dark mode, and with enlarged text.
16. Cross-business reads/writes and unauthorized media downloads fail in server/database tests, not merely UI tests.
17. Another business cannot record a payment on an invoice, and a retried payment with the same request id is recorded once.
18. Dashboard totals, reports and GSTR-1 include every invoice in the selected period, however many there are.
19. A quotation for a GST-registered customer converts to a B2B invoice that keeps the customer's GSTIN.

## 13. Existing source map for reuse

Paths are relative to the Simplek repository. The new AI may not have these files; this document contains the essential behavior, and these references identify where to inspect if the repository is supplied.

- `lib/main.dart`: `_BusinessOnboardingPageState`, `BusinessSettings`, `_BusinessSettingsPageState`, `_CustomerFormDialogState`, `_lookupIfsc`, `_verifyGstin`, invoice/quotation builders, dashboard refresh, archival controls.
- `supabase/functions/gstin-lookup/index.ts`: provider proxy, validation, secret name, retries, and error mapping.
- `docs/gstin-lookup.md`: provider secret/deployment setup. Supply a new project's own credentials; never copy private keys into this handoff.
- `lib/payment_pdf.dart`: UPI QR construction and PDF rendering/fallback.
- `lib/invoice_palette.dart`: the five exact palettes.
- `lib/document_defaults.dart`: separate editable invoice/quotation defaults.
- `lib/document_text.dart`: Indian amount-in-words and number-input validation.
- `lib/document_sharing.dart`, `lib/whatsapp_contact.dart`, Android `MainActivity.kt`: mobile sharing and phone normalization; redesign the platform layer for web.
- `supabase/migrations/20260830_business_profiles.sql`, `20260830_business_tax_and_numbering.sql`: profile schema and tax-related fields.
- `supabase/migrations/20260901_business_media_storage.sql`: private storage layout and policies.
- `supabase/migrations/20260924_business_document_numbers.sql`: per-owner/year counters, uniqueness, compatible RPCs, customer archival field.
- `supabase/tests/20260924_document_regressions.sql`: rollback-only numbering/isolation/archive regression checks.
- `supabase/migrations/20261106_atomic_invoice_payment_saves.sql`: `save_invoice`, `convert_quotation_to_invoice` and the ownership-checked `record_invoice_payment`.
- `supabase/tests/20261106_atomic_saves_regressions.sql`: rollback-only checks for payment ownership, retries, failed-save rollback and conversion.
- `lib/offline_queue.dart`: the mobile app's offline queue. Mobile-only; a website should not copy it unless it needs offline support.
- `docs/hsn-sac-master-import.md`: master-data import process; source tax classifications from a maintained authoritative dataset rather than AI-generated lists.

## 14. Deliverables requested from the implementing AI

Produce the billing-only web interface, reusable profile/lookup components, server adapters, database migrations and policies, a shared calculation/document model, invoice preview/download, and automated acceptance tests. Include setup instructions and an environment-variable template containing names/placeholders only. Document remaining provider approvals, credentials, deployment steps, and device/browser tests honestly.

Do not add unrelated commerce features. Do not mark API integrations, payment verification, legal compliance, or direct WhatsApp attachment delivery as complete based only on mockups or successful UI rendering.

## 15. Known limitations in Simplek: do not reproduce

These were found by reading the source. Fix them in the website rather than copying the behavior.

| Area | Current behavior | Website requirement |
|---|---|---|
| Dashboard totals | Total sales and outstanding add up only the newest 100 non-draft invoices | Aggregate on the server across all invoices |
| Reports and GSTR-1 | Load the newest 500 invoices and 5,000 unfiltered line items, then filter by period in the app; older periods can be silently incomplete | Filter and aggregate by period on the server; never truncate filing data without saying so |
| Quotation conversion | Quotations have no GSTIN field, so a converted invoice has none and is reported as B2C until edited | Store the buyer GSTIN on quotations and carry it over |
| Money arithmetic | Floating point, rounded per stored field (see section 9) | Integer paise with one documented rounding rule |
| Sign-out | Bank, UPI and PAN values stay in device storage under keys not tied to a user, and a new user without a saved profile can see them | Scope cached profile data to the business and clear it on sign-out |
| PDF text | Built-in Helvetica font: amounts print as `Rs.` instead of `₹`, and non-Latin names (for example Hindi or Malayalam) probably do not render; not tested | Embed a Unicode font and test Indian scripts |
| GSTIN status | Unknown status shown as `active` (section 5) | Show the returned status, or "unknown" |
| Payments | No history, edit, reversal, reference or notes (section 9) | Add if needed |
| Database schema | The repository's migrations cannot build the database: no migration creates `customers`, `products` or `invoice_items`; `invoices.created_at`, which the dashboard sorts by, is in none of them; several files share a date-only version; and `20260829_payment_schema_compatibility.sql` sorts before the migration that creates `payments` | Take a schema dump of the live project as the starting point and keep complete, uniquely versioned migrations |

## 16. Changes since the 4 October 2026 version

- Commit `bbec152` (6 November 2026) added `save_invoice` and `convert_quotation_to_invoice`, and closed a hole in `record_invoice_payment`, which had let any caller, including anonymous ones, record payments on any invoice whose id they knew. Sections 2, 9 and 10 now describe these as existing behavior.
- Its migration was tested only on a local Postgres built from the repository's migrations. Confirm it has been applied to the live project before relying on it. The new mobile app cannot save invoices without it.
- Added: the GSTIN `active` default defect (section 5), the existing rounding behavior (section 9), the 16-character invoice number check (section 10), known limitations (section 15) and acceptance tests 17–19.
