# Simplek — UI/UX Redesign Brief

Updated: 16 September 2026

## 1. Purpose and instructions for the receiving AI

Redesign the UI and UX of **Simplek**, an existing mobile-first Indian invoicing application. This document is a portable design handoff, not a request to build a different product or replace its backend.

Produce a polished, practical design that can be handed back to the original Flutter developer for implementation. Preserve the business workflows and requirements below. Improve layout, visual hierarchy, navigation, consistency, accessibility, and ease of use.

If you receive only this document, do not claim that you modified or tested the real application. Return design specifications, mockups, and reusable components. If generating code, prefer Flutter/Dart. A web prototype is acceptable as a clearly labelled visual reference, not as a replacement for the Flutter app.

Do not add paid subscriptions, AI assistants, inventory purchasing, payroll, new tax rules, or other unrelated product features. Label any optional suggestions separately. Never invent production credentials, customer data, API responses, or payment details.

## 2. Product and users

- **Name:** Simplek. Always show the full name, not “Simp...” or another abbreviation.
- **Tagline:** Invoicing made easy.
- **Primary platform:** Android phone. Flutter also provides the foundation for other screen sizes.
- **Users:** Small business owners, service providers, traders, and businesses such as catering companies.
- **Main jobs:** Maintain customers and products/services; create quotations and invoices; share PDFs; record payments; review outstanding balances and reports.
- **Context:** Indian rupees, Indian states and Union Territories, GSTIN, HSN/SAC, CGST/SGST/IGST, bank details, and UPI payments.
- **Design character:** Clear, trustworthy, comfortable, businesslike, and modern. Avoid ornamental dashboards that make everyday billing slower.

## 3. Existing implementation and boundaries

The following is the implementation baseline, not a mandate to retain its current visual appearance:

| Area | Existing implementation |
| --- | --- |
| UI | Flutter/Dart, Material 3; most screens currently in `lib/main.dart` |
| Backend | Supabase authentication, database, storage, and functions |
| Persistence | Shared preferences, secure storage, and existing offline/cache helpers |
| Documents | `pdf` and `printing` packages; document bytes also used for sharing |
| Media | Image selection/editing, business logo, signature, uploaded payment QR |
| Payments | UPI QR generation and uploaded QR fallback |
| Android sharing | Native bridge in `android/app/src/main/kotlin/com/example/simplek/MainActivity.kt` |
| Terms | `lib/document_defaults.dart` |
| PDF payment section | `lib/payment_pdf.dart` |
| Tests | `test/widget_test.dart`, `test/requested_changes_test.dart` |

Preserve authentication, record IDs, database relationships, access policies, numbering, tax calculations, offline behavior, and platform sharing integration. A UI redesign must not disable row-level security or put privileged database keys in the app. Do not change stored values merely to simplify a mockup.

## 4. Current visual baseline

- Primary light-theme seed: `#3157A4` (blue).
- Light app background: `#F6F7FB`.
- Light cards and filled inputs: white.
- Existing shapes: roughly 12 px input/button corners and 16 px cards.
- Existing layout rhythm: commonly 16 px page padding, 12–16 px gaps.
- Appearance choices: **System default**, **Light**, and **Dark**; choice is saved locally and updates the app immediately.
- Existing branding files: `assets/branding/simplek-logo-hd.png` and `assets/branding/simplek-app-icon-hd.png`.
- UPI asset: `assets/branding/upi-logo.png`; source information is in `assets/branding/UPI-SOURCE.md`.

You may refine colors, typography, spacing, and component styling. Preserve the Simplek name and logo identity unless a separate branding concept is explicitly labelled as optional. Do not redraw or stylize the UPI logo.

## 5. Navigation and screen inventory

Current main navigation is a dashboard drawer containing:

1. Dashboard
2. Customers
3. Products & Services
4. Invoices
5. Quotations
6. Payments
7. Reports
8. Business Profile & Settings
9. Log out

Other screens include splash, login, account creation, email-link waiting, password setup, business onboarding, global search, customer history, record editors, and document previews.

A redesigned navigation model is welcome. For example, a bottom navigation bar plus a “More” destination may reduce drawer use. This is a proposal, not existing behavior. If changing navigation, supply a complete destination mapping; do not lose any screen or bury invoice creation behind several taps.

## 6. Screen specifications

### A. Splash and account access

- Splash shows Simplek branding and “Invoicing made easy”.
- Current requested splash duration is 2.6 seconds before the transition; no loading spinner beneath the branding.
- Keep login, signup, email confirmation/link waiting, and password setup understandable and separate where needed.
- Show field validation, password visibility controls, progress, retry, and recovery actions clearly.
- Do not expose technical authentication errors as the primary user-facing copy.

### B. Business onboarding

Current sections: Business details; Terms and conditions; Branding and payments.

Preserve these inputs and capabilities:

- Owner name and business name.
- GST registration choice and registration type.
- GSTIN verification and auto-filled business details for registered businesses.
- PAN, required business state, default place of supply.
- Financial year, invoice prefix, quotation prefix.
- Business address, mobile number, email.
- Editable invoice and quotation default terms.
- Logo upload/edit, signature upload/drawing, UPI ID, generated/uploaded QR.
- IFSC lookup, bank name, branch, account number.

Use clear steps and progress. Long forms must remain scrollable with the keyboard open. State selection must include every Indian state and Union Territory and must not truncate long option labels.

### C. Dashboard

- Full Simplek name in the top app bar.
- Clear access to global search, refresh, and settings without crowding the title.
- Summary cards: Total Sales, Outstanding, Invoices, Customers.
- Quick actions include invoice creation, adding a customer, adding a product/service, and recording a payment.
- Recent invoices with number, customer, date, and amount.
- Empty state explaining how to create the first record.
- Loading, refresh failure, cached/offline states where relevant.

Use readable financial values. Large amounts must not overflow small cards. Do not introduce decorative or nonfunctional action icons.

### D. Customers list and history

- Search/filter customer names; expose Add Customer prominently.
- Each record needs readable identification, edit access, and customer-history access.
- Customer history includes associated documents/payment information available in the current app.
- Design empty, loading, error, offline/cached, and populated states.

### E. Create/edit customer

The first question is **“Is this customer registered under GST?”**, with a clear Yes/No choice.

**Yes:** Show GSTIN first, with Verify. Successful lookup auto-fills available name/address/state information. Keep the resulting fields reviewable.

**No:** Show manual entry directly without making GSTIN compulsory.

Fields: customer name, mobile number, email, address, required State / Union Territory; GSTIN required for the registered path. Preserve existing validation.

Requirements:

- State is compulsory; use a searchable selector if possible.
- Avoid a long question embedded as a single-line dropdown placeholder.
- GST verification results appear above the current form in a popup and automatically close after two seconds, including validation/failure messages. Do not put them behind the customer dialog.
- Show lookup progress separately; keep returned information visible in the fields after the popup closes.
- Save and Cancel must be reachable on a small phone with the keyboard open.
- A full-screen editor or generous bottom sheet is an acceptable redesign of the current dialog.

### F. Products & Services list and editor

- Searchable list, clear Add and Edit actions.
- Item type: Product or Service.
- Product/service name, optional SKU/item code, selling price, unit of measurement.
- HSN lookup for products and SAC lookup for services; show the selected classification and description clearly.
- GST percentage is entered manually; do not invent a rate from the classification.
- Preserve existing classification-search behavior and validation.

Keep long descriptions readable without making every field excessively tall. Separate basic item details from tax classification.

### G. Invoice and quotation builders

Design these as a consistent family of screens, with document-specific dates and labels.

Suggested order:

1. Customer selection and contact summary.
2. Document dates and place of supply.
3. Product/service line items.
4. Totals and tax breakdown.
5. Editable terms.
6. Save actions.

Customer selector:

- Dropdown/picker with type-to-filter matching.
- Visible Add New Customer action.
- Saving a customer from inside either builder must immediately select the returned customer and make it available without leaving/reopening the builder.
- Customer state automatically becomes place of supply when that customer is selected. Keep place of supply editable through the state/UT selector.
- Show appropriate customer contact/GST details without overwhelming the form.

Item selector:

- Dropdown/picker with type-to-filter product/service matching.
- Visible Add New Product/Service action.
- Saving a new item from inside either builder must immediately select it in the originating row and fill its relevant saved details. Use the returned record, not an exact-name lookup.
- Preserve other form entries while adding a customer or item.

Line items:

- Product/service, quantity, rate, GST percentage, calculated row total.
- Add another item and remove-row actions.
- Distinguish editable values from calculated totals.
- Preserve the existing calculation, rounding, tax, and validation logic.
- Display subtotal, applicable CGST/SGST or IGST, and document total clearly.

Dates: invoice date and due date for invoices; quotation date/validity where applicable for quotations.

Final actions are **Save & Close** and **Save & Next**, not standalone Preview and Save Draft buttons.

| Action | Required result |
| --- | --- |
| Save & Close | Validate and save, then return to the dashboard |
| Save & Next | Validate and save, then show the saved document preview |
| Save failure | Keep the editor and all entered data; show an actionable error |
| Saving | Disable repeat submissions and show progress |
| Edit existing record | Update that record without creating a duplicate |

### H. Invoice and quotation previews

- Title: Invoice Preview or Quotation Preview.
- **Close** in the top-right, returning to the dashboard.
- Main area: readable PDF preview with available zoom/scroll behavior.
- Full-width **Save & Add New Invoice** or **Save & Add New Quotation** above the Print action.
- This action opens a fresh builder of the same type. The previous document is already saved; do not create another copy.
- Print, WhatsApp, Email, and Share PDF remain discoverable.
- Do not restore the unused debug/orientation toggle previously removed from the preview toolbar.
- On narrow screens, wrap or stack actions; never split “WhatsApp” into awkward fragments.

Sharing boundary:

- Invoice email/WhatsApp actions must preserve attachment generation and customer recipient handling.
- External apps control their final recipient confirmation and send screens; do not promise silent delivery or show “Sent” merely because a share sheet opened.
- Current quotation Email/WhatsApp code still uses text-link launch paths, while Share PDF exports the file. Treat attachment parity as a known implementation gap to flag, not functionality that a visual mockup has fixed.

### I. Payments

- Select an outstanding invoice, enter payment amount, choose payment method, and record payment.
- Make the selected invoice and its outstanding amount easy to identify.
- Preserve payment validation and its relationship to the saved invoice.
- Include no-outstanding-invoices, saving, success, and failure states.

### J. Reports

- Preserve the existing reporting, date filters, exports, tax breakdowns, and data-validation feedback.
- Existing reports include GST-oriented information such as B2B/B2C supplies and customer/item summaries.
- Prioritize headline totals and readable drill-down lists; complex tables can use controlled horizontal scrolling.
- Clearly distinguish empty results from failed data loading.
- Do not represent exported reports as successfully filed tax returns.

### K. Business Profile & Settings

Organize the current fields into approachable sections:

- Appearance: System default / Light / Dark.
- Business identity and contact details.
- GST, state, and document numbering.
- Branding: business logo and signature.
- Payments: bank details, IFSC lookup, UPI ID, payment QR.
- Document defaults: payment due days and separate invoice/quotation terms.

Changing appearance updates the app immediately and persists across launches. System default follows the device setting. Do not use hardcoded white cards with dark-theme text or hide saved values on focus.

## 7. PDF design requirements

PDFs are printable business documents, not screenshots of the app UI. Keep a white print background in both app themes.

Invoice content includes business identity/contact/GST details, logo when supplied, invoice number and dates, customer details, place of supply, item table, taxes/totals, payment details, terms, payment QR, and signature where available.

Quotation content includes business identity, quotation reference/date/validity, customer, item table, total, saved terms, and the payment QR section when payment information is configured. Do not claim every invoice-only field already exists on quotation PDFs; label proposed parity changes.

Payment section:

- Use the existing business UPI ID to generate the QR, or the existing uploaded QR fallback.
- Below the QR show **“Scan to pay through UPI”** and the bundled UPI logo.
- Do not obscure the QR or remove its clear surrounding space.
- Do not display a fabricated QR when payment details are absent.
- Preserve aspect ratios of logo, QR, and signature.

Require clean A4 pagination, long-name/address wrapping, repeated table headers where appropriate, readable amounts, and no overlap between terms, payment section, and signature. Any redesigned PDF must be rendered and visually checked separately from the mobile UI.

## 8. Default terms: preserve this copy

These are the requested defaults, not advice about their legal enforceability. Users can edit terms. Existing custom defaults and saved document terms must not be overwritten by a visual redesign.

### Quotation

```text
1. This quotation is valid for 30 days from the date of issue.
2. Prices and availability are subject to confirmation.
3. Taxes will be charged as applicable.
4. Work or supply begins after accepting the quotation by making advance payment
```

### Invoice

```text
1. Payment is due by the due date shown on the invoice.
2. 18% p.a Interest will be charged on the invoice amount if the amount is not paid within due date.
3. No reduction in the invoice amount will be entertained.
4. Subject to local jurisdiction.
```

## 9. Design-system deliverables

Provide a coherent token set, with explicit Light and Dark values:

- Primary, secondary, background, surface, border, text, muted text, success, warning, and error colors.
- Typography scale: page title, section heading, body, field label, helper/error, monetary total.
- Spacing scale, page gutters, corner radii, border widths, elevation, icon sizes.
- Buttons: primary, secondary, text, destructive, loading, disabled.
- Inputs: default, focused, filled, required, invalid, disabled.
- Searchable customer/product/state selectors, date pickers, dialogs, sheets, cards, list rows, totals panels, and empty/error/offline states.

Suggested usability targets, not a claim of current certification:

- At least 48 logical pixels for primary touch targets.
- Body text generally 14–16 logical pixels or larger; retain comfortable readability.
- Aim for at least 4.5:1 normal-text contrast and 3:1 large-text/UI contrast.
- Support font scaling; test at 200% without clipped values or inaccessible actions.
- Do not use color alone to communicate status.
- Give icons semantic labels and maintain sensible focus order.
- Respect safe areas, Android back navigation, keyboard insets, and screen-reader semantics.

## 10. Responsive layout and required states

Produce representative layouts at approximately 360 px, 390 px, and 430 px phone widths, plus a wider tablet layout. Stress-test a 320 px width rather than designing only for a large phone.

- Prefer single-column long forms on phones.
- Only put fields side by side where both labels and values fit comfortably.
- Keep monetary totals prominent without reducing them to tiny text.
- Use searchable, scrollable lists for long option sets.
- Ensure sticky save actions never cover the last field or keyboard-focused input.
- Put loading/errors close to the relevant task; do not discard entered form data.

For each major screen show: populated, empty, loading, error, disabled/saving, and offline/cached states where supported. Also show long names, large currency amounts, long state/UT names, and an open keyboard on a customer/document form.

## 11. Acceptance checklist

- [ ] Full Simplek title fits on a small dashboard.
- [ ] No overflow stripes, clipped dropdowns, hidden validation, or overlapping controls.
- [ ] All navigation destinations remain reachable.
- [ ] Customers, products/services, invoices, and quotations retain edit entry points.
- [ ] GST Yes/No changes the customer form appropriately.
- [ ] GST result popup is visible over the editor and closes after two seconds.
- [ ] Required state selection and automatic place-of-supply behavior remain intact.
- [ ] Newly created customers and items select immediately in both document builders.
- [ ] Save & Close and Save & Next work as specified and preserve input on failure.
- [ ] Preview Close and Save & Add New have correct destinations and do not duplicate records.
- [ ] Print/share actions remain usable on narrow phones.
- [ ] All three appearance modes are specified; PDF pages remain print-friendly.
- [ ] QR caption/logo are readable and QR scan space is preserved.
- [ ] Existing custom terms, saved data, numbering, and tax calculations are not changed.
- [ ] Empty/error/loading/offline behavior is represented honestly.

## 12. What to return to the original developer

Return a package that includes:

1. `DESIGN_PROPOSAL.md`: design direction, rationale, screen inventory, and changes from this baseline.
2. Design tokens in a readable table and, ideally, JSON or Dart theme definitions.
3. Light and Dark mockups for Dashboard, Customer Editor, Item Editor, Invoice Builder, Quotation Builder, Preview, and Settings; supplementary screens as available.
4. Component specifications with all important interaction states.
5. Navigation and interaction notes for add/select/save/close/add-new flows.
6. Exported assets with filenames, dimensions, source/licensing notes; no unlicensed replacements for official marks.
7. Flutter component code if available, clearly separated from mock services and sample data.
8. A short list of unresolved questions, implementation gaps, and optional enhancements.

Use fictional sample data such as “Sample Catering Co.” and “Sample Customer”. Do not copy real account numbers, GSTINs, signatures, or contact details from screenshots into shared mockups.

## 13. Copy-and-paste prompt

> Redesign Simplek using the attached DESIGN.md as the functional contract. It is an existing Flutter invoicing app for Indian small businesses. Create a cohesive, mobile-first UI/UX with Light, Dark, and System modes, readable forms, searchable record selectors, and clear invoice/quotation workflows. Preserve the required behaviors, data model boundaries, document actions, and payment/PDF constraints. Distinguish existing functionality from proposed changes and known gaps. Return the design package specified in section 12 so I can give it back to my Flutter developer. Do not claim the real app is implemented or tested unless you actually have and use its source project.
