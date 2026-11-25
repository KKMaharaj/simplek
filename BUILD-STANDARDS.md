# Standard build rules for websites and web apps

> Copied into this project from the owner's PDF "Standard-build-rules.pdf" (Version 3, 22 Oct 2026) on 25 Nov 2026. The original PDF is in `docs/standards/`. Where this text and the PDF differ, the PDF wins.

Give this file to the coding agent at the start of every project · Version 3 · 22 October 2026

### How to use this file
- Put this file in the project root as BUILD-STANDARDS.md . Add this line to AGENTS.md (or the first prompt): “Follow BUILD-STANDARDS.md in everything you build, unless the project’s own requirements say otherwise.”
- The project’s own requirements win when they differ from this file. Everything not mentioned in them follows this file.
- The rules are written for India-based businesses (₹, GST, PIN codes, UPI, DPDP Act). Skip the parts that don’t apply.
- Do not stop to ask about anything covered here. Where a real value is missing (an address, a key, a number), use an obvious placeholder, make it editable in the admin settings, and list it in NOTES.md under “Replace before launch”.

## 1. Forms and field validation
Every form, every field, every time.
- Validate both in the browser (instant feedback) and on the server (the real check). Never trust the browser alone.
- Show the error under the field, in red, in plain words (“Enter a 10-digit mobile number”), and give the field a red border. Also show a short summary at the top for long forms, and move focus to the first wrong field.
- Validate when the user leaves a field and again on submit. Don’t show errors before the person has typed anything.
- Mark required fields with * and say “(optional)” on optional ones.
- Trim spaces before saving. Store emails in lowercase.
- Keep everything typed when the form fails or the server returns an error. Never clear a form on error.
- Max lengths on every text field (name 100, address line 150, notes 1,000), matching the database.
- Numbers: quantities are whole numbers of 1 or more; money is never negative; percentages are 0 to 100.
- Dates: block future dates where they make no sense (purchase date, date of birth) and past dates where those make no sense (delivery date). Use a date picker; display as DD MMM YYYY (21 Oct 2026).
- Duplicates: warn before saving something that already exists (the same invoice number, mobile number or email), with “Add anyway” and “Cancel”.
- Unsaved changes: warn before leaving a form with unsaved changes.
- Use the right keyboard on phones: inputmode="numeric" for numbers, type="email" , type="tel" . Input text at least 16 px, so phones do not zoom in.
- Use the correct autocomplete value on every field ( name , email , tel , street-address , postal-code , username , current-password , new-password , one-time-code ).

### Standard formats (India)
- **Mobile**: 10 digits, starts with 6–9. Accept +91 / 0 / spaces and normalise to 10 digits. Store as +91XXXXXXXXXX
- **Email**: Standard email check; lowercase
- **PIN code**: 6 digits, not starting with 0
- **GSTIN**: 15 characters, pattern ^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$ , plus the checksum. The first 2 digits give the state
- **PAN**: ^[A-Z]{5}[0-9]{4}[A-Z]$
- **IFSC**: ^[A-Z]{4}0[A-Z0-9]{6}$ . Look up the bank and branch to auto-fill them
- **Name**: Letters, spaces, dot, apostrophe and hyphen; 2–100 characters

## 2. Address fields
- PIN code first. When 6 digits are entered, auto-fill City/District and State (India Post PIN code API, or a stored PIN table as the fallback). Keep the filled fields editable. If the lookup fails, let the person type them and say “We couldn’t find this PIN code; please check it.”
- Fields: Full name, Mobile, Address line 1 (house/flat, building), Address line 2 (street, area), Landmark (optional), PIN code, City, District, State (drop-down of states and union territories), Country (default India).
- Customers can save several addresses, choose a default, and edit or delete them. Billing address “Same as delivery address” is ticked by default.
- The business’s own address comes from settings, never typed into the code.

## 3. Login, passwords and sessions
- Eye icon on every password box to show or hide the password. It must be a real button with the label “Show password” / “Hide password”.
- Browser “Save password?” must work on every login, signup, set-password and change-password form: a real <form> with a username field ( autocomplete="username" ) and a password field ( autocomplete="current-password" , or new-password on signup and change password); stable id and name attributes; the form actually submits (a full navigation, or a successful fetch followed by a page navigation); on change-password and set-password forms, include the username as a hidden autocomplete="username" field; this can only be confirmed by a hand test in normal Chrome (not Incognito) on a laptop and an Android phone. Never mark it done without that test.
- Password rules: at least 8 characters, with a letter and a number. Show the rules under the box before the person types. Store with bcrypt or argon2, never readable.
- OTP: 6 digits, valid for 5–10 minutes, resend allowed after 30 seconds with a visible countdown, at most 5 tries, then a wait. Use autocomplete="one-time-code" so phones fill it from the SMS.
- Forgot password: mobile or email → OTP → new password → logged in. The same flow serves first-time staff who have never set a password.
- Limit login attempts: after 5 wrong tries, a short lockout with a clear message. Never say whether the mobile or the password was the wrong one.
- After login or signup, return the person to the page they came from ( ?next=/path ). Accept only relative paths starting with a single / , to block redirects to other sites. Signup ends logged in, with no second login.
- Sessions: httpOnly, Secure, SameSite cookies held on the server. Customer timeout and staff timeout are set per project (typical: customers 30 minutes idle with “Remember me”, staff 8–15 hours).
- One login page for staff; the role is recognised from the account, with no role picker.
- Logout in exactly one obvious place per layout (the side menu on desktop, the top bar or menu on phones).
- Never two Logout buttons on one screen.

## 4. Buttons and feedback
Every button and link has:
- **State**: What the person sees
- **Hover**: Colour change
- **Pressed**: Slightly darker, scales to 98% for a moment
- **Keyboard focus**: A visible 2 px outline
- **Busy**: A spinner, the button disabled, so it cannot be pressed twice
- **Disabled**: 50% opacity, “not allowed” cursor, and a tooltip saying why

- Every action that calls the server shows Busy until the answer comes back.
- After the action, show a toast for about 3 seconds (“Saved”, “Added to cart”, “Order marked as shipped”). Errors show in red and leave the button usable.
- After saving, the page shows its new state. Old buttons that no longer apply are hidden (for example, no “Save and add” once it’s added). Status bars show what’s done and by whom.
- Destructive actions (delete, cancel, refund) ask for confirmation, naming what will happen. Prefer “deactivate” over deleting records that have history.
- Loading: skeleton placeholders, not blank pages. Empty states: a short message and the next action (“No orders yet. Create the first offline invoice”).
- Friendly 404 and error pages with a way back home.

## 5. Lists, tables, search and exports
- Server-side pagination on every list that can grow: 25 rows by default, with a choice of 10 / 25 / 50 / 100 remembered per user. “Showing 26–50 of 287” and ‹ Prev 1 2 3 … Next ›; on phones, “Page 2 of 12”.
- Search and filters cover the whole list, not just the visible page. Changing a filter goes back to page 1.
- Page, filters and sort are kept in the URL, so Back and refresh return to the same view.
- Totals, statistics and charts use all the matching rows, not just the visible page.
- Sort by clicking column headers. Date filter presets: Today, Last 7 days, This month, This quarter, This year, Custom.
- Export to Excel and PDF includes every row matching the filter, with the filter and date printed at the top.
- Bulk actions (Print all, Export) confirm the count first (“Print 287 orders?”).
- Tables: sticky header; wide tables scroll sideways inside their own box; on phones, rows can become cards.
- Status shown as coloured badges with words. Colour is never the only signal.

## 6. Responsive design (every page, every screen)
- Test at 1920, 1440, 1366, 1280 (desktop), 1024, 768 (tablet) and 414, 390, 375, 360 (phone).
- No horizontal page scroll at any width. Add an automated test that fails if scrollWidth > innerWidth on any route.
- Tap targets at least 44 px. Body text at least 15 px on phones.
- Grids reduce their columns (4 → 2 → 1). Side-by-side panels stack on phones.
- Below 1024 px: a ☰ menu button with a full-width slide-in panel (close with ✕, a link, or the Escape key). Staff side menus become slide-in panels.
- Fixed bottom bars (Add to cart, Save) are never covered by banners or chat buttons.
- Header logo and menu sit on one row on desktop and never overlap the hero image.

## 7. Accessibility
- Every input has a visible <label> . Every image has meaningful alt text (empty alt for decoration).
- Text contrast at least 4.5:1. Never white text on light colours.
- Everything works with the keyboard. Focus is always visible. Dialogs trap focus and close with Escape.
- A “Skip to content” link exists but stays hidden until it is focused with the Tab key.
- Respect prefers-reduced-motion . Give large animations a pause button.
- Use proper headings in order: one h1 per page, then h2 , h3 .

## 8. Money, GST, the business profile and invoices

### 8.1 Money and tax rules
- Store money as integers in paise, never floats. Round only when displaying, with one documented rounding rule.
- Show Indian grouping: ₹1,23,456.00.
- Check that the ₹ sign looks right in the chosen font, on screen and in PDFs. Some fonts (DM Sans, for example) draw it oddly. If so, use a unicode-range that leaves U+20B9 to a fallback font such as Noto Sans.
- GST: taxable value = quantity × rate (less discount); tax = taxable value × GST % ÷ 100. CGST + SGST (half each) when the seller and the place of supply are in the same state; IGST otherwise. Compare state codes (from the GSTIN or a state drop-down), never typed state names.
- Discounts come off the taxable value before GST, each on its own invoice line. Write down the order when there are several (for example, automatic discount first, then the coupon).
- Amount in words in Indian style (lakh, crore, paise), matching the printed total: “Rupees Fifty Three Thousand One Hundred Only”.
- Store times in UTC; display in IST. Dates on documents use DD/MM/YYYY.
- Keep GSTIN, PAN, IFSC, PIN codes, phone and account numbers as text, never numbers, so leading zeros are never lost.

### 8.2 Business profile: the details asked for before the first invoice
Whenever a project can generate invoices (or quotations, receipts or labels), build an Admin > Business Profile
and Settings page. Ask for these details in a short set-up flow the first time, and let them be edited later. The
“Create invoice” button stays disabled, with a message saying which details are missing, until the required ones
(marked *) are filled in.
- **Group**: Fields
- **Identity**: Business / trade name*, legal name, owner or proprietor name, constitution (proprietorship, partnership, LLP, private limited)
- **Address**: Address line 1*, line 2, landmark, PIN code* (auto-fills district and state), city*, district, state*, country. The address registered for GST is used on invoices; a different “display address” for the website is allowed
- **Contact**: Phone / customer care number*, WhatsApp number, email*, website
- **Tax**: GST-registered yes/no*, GSTIN (with lookup, see below), PAN, state and state code (from the GSTIN), default GST % and HSN/SAC for the main products, composition scheme yes/no
- **Group**: Fields
- **Bank**: IFSC* (auto-fills bank name and branch), bank name, branch, account name*, account number* (typed twice to confirm), account type
- **Payments**: UPI ID (makes the QR automatically), or an uploaded QR image; payment gateway settings (see 9.1); email, WhatsApp and SMS settings (see 13.1)
- **Documents**: Invoice prefix (for example INV ), quotation prefix, credit note prefix, financial-year format ( 2026-27 ), default due days (for example 7), default terms and conditions (editable list), footer note, whether to show bank details and QR on paid invoices
- **Branding**: Logo (PNG/JPG/WebP, up to 5 MB), signature (upload or draw on screen), “Authorised signatory” label, invoice colour (see 8.4)
- **Licences**: Any numbers the business must print: FSSAI, drug licence, AYUSH, MSME/Udyam, CIN, patent, and so on. Each one has a “show on invoice” switch

Lookups (all run through the project’s own server, with a timeout, a Retry button, and the fields left editable if the
lookup fails):
- IFSC → bank and branch: https://ifsc.razorpay.com/{IFSC} . An IFSC identifies a branch only. It never proves the account number or holder.
- GSTIN → legal name, trade name, address and status, through a paid GSTIN API with the key kept on the server.
- Show the status returned (Active, Cancelled and so on); never assume “Active”. A lookup failure is never labelled “verified”.
- PIN code → post office, district, state: https://api.postalpincode.in/pincode/{PIN} . Offer a choice when there are several post offices.
Preview: the profile page shows a live SAMPLE invoice using the real invoice template and the values being typed.
It is marked “SAMPLE”, never saved, and never uses up an invoice number.
Editing safety: changing the profile never changes invoices already issued. Each invoice stores a snapshot of
the seller details, buyer details, items, tax, bank/UPI, terms, logo and template version at the moment it was issued.

### 8.3 Invoice layout (A4, the standard format)
From top to bottom:

1. Header. Left: the logo, then the business name (large, in the invoice colour), the address, phone, email, and GSTIN in bold. Right: “TAX INVOICE” in large bold capitals. Use “INVOICE” when the business is not GST-registered, “BILL OF SUPPLY” for exempt or composition-scheme sales, and “CREDIT NOTE” for credit notes.
2. Details row. Left, “Bill to”: customer name (bold), address, phone, and the customer’s GSTIN if any. Add a “Ship to” block when the delivery address is different. Missing details are left out, never printed as empty labels. Right: Invoice no., Invoice date, Due date, Place of supply (state and code), and the order or reference number if any.
3. Items table, with a header row in the invoice colour and white text: columns: # · Description (with HSN/SAC under it) · Qty · Rate · Discount (only when used) · GST % · Amount; amounts are right-aligned. Long descriptions wrap; the table continues onto the next page with the header repeated.
4. Totals block, right side: Subtotal (taxable value); each discount on its own line; CGST and SGST, or IGST; shipping or other charges; round-off if used; a line, then Total payable in bold, in the invoice colour. For paid invoices also show Amount paid and Balance due.
5. Amount in words, full width.
6. Payment section (unpaid invoices): Bank details: Bank, Branch, Account name, A/c No., IFSC, UPI ID; the UPI QR with “Scan to pay through UPI” and the UPI logo under it, bottom left; paid-online invoices instead show “Paid online via [gateway]”, the payment ID and the date, with no QR and no bank details; QR priority: a valid UPI ID makes the QR, else the uploaded QR image, else no QR. Until a real UPI ID is set, print a SAMPLE QR that no UPI app can pay.
7. Terms and conditions: a numbered list from the profile, editable per invoice.
8. Signature, bottom right: the signature image above “Authorised signatory”, with the business name.
9. Footer, centred and small: “This is a computer-generated invoice.”

Rules:
- The invoice is saved before it is shown or sent: save it, then preview, print, download, email or WhatsApp it.
- Generated as a PDF on the server, with the same look on screen, print and download. It fits A4 with 15 mm margins and prints in bulk.
- File name: INV-2026-27-0028_Customer-Name.pdf .
- Cancelled invoices are never deleted or renumbered: they are marked “CANCELLED” across the page, with a linked credit note.
- The same template, with its title changed, is used for quotations, proforma invoices, receipts and credit notes.
See sample-invoice.png (supplied with this file) for the layout in the default colours.

### 8.4 Invoice colours
The business picks one colour scheme in the Business Profile. It applies to the business name, “TAX INVOICE”, the
table header, the total and the headings. It is saved on the business (not on one staff member), and shown in the
live preview.
- **Name**: Paper                                      Ink (main colour)
- **White and red**: #FFFFFF                                     #9F1239
- **White and blue (default)**: #FFFFFF                                     #1E3A8A
- **Cream and blue**: #FFF4DC                                     #173B67
- **Light yellow and blue**: #FFF9C4                                     #163A70
- **White and dark green**: #FFFFFF                                     #14532D
- **Brand colour**: #FFFFFF                                 The project’s own brand colour, if it passes 4.5:1 contrast on white

- Body text stays dark grey or black for easy reading. The colour is used for headings and accents only.
- The QR is always black on white.

Every scheme must print clearly on a black-and-white printer.

### 8.5 Numbering, saving and reports
- Invoice numbers come from a database counter, separate for each business, each document type and each financial year (April–March): INV/2026-27/0001 , QTN/2026-27/0001 , CN/2026-27/0001 .
- Numbers are given out atomically (no two invoices get the same number), never reused, never edited after issue, and checked for uniqueness (case and spaces ignored).
- Saving an invoice and its items is one transaction, safe to retry. A double click or a network retry never creates two invoices.
- Customers and products are archived, not deleted, so old invoices stay intact.
- Creating an invoice: search customers by name, mobile or GSTIN, with “+ Add customer” without leaving the page; search products, with “+ Add product”; add rows with a + button; entered values are kept when moving around the form.
- Reports: sales and GST summaries by date, GSTR-1 JSON, Tally XML, and Excel/PDF exports.

### 8.6 GST reports and GSTR-1 (only when the business is GST-registered)
Build this when the Business Profile says “GST-registered: Yes”. Hide it completely when it says No.
Reports page (Accounts and Admin):
- Period picker: monthly, or quarterly for QRMP filers (a setting in the profile, “GSTR-1 filing: Monthly / Quarterly”), plus a custom range.
- Sales summary: invoices, credit notes, taxable value, CGST, SGST, IGST, cess and total, by day and by tax rate.
- GSTR-1 preparation, with every table the return needs, each one viewable on screen and downloadable:
- **Table**: What goes in it
- **B2B (4A, 4B)**: Invoices to customers with a GSTIN: GSTIN, name, invoice number, date, value, place of supply, reverse charge Y/N, rate-wise taxable value and tax
- **B2CL (5)**: Inter-state invoices to unregistered customers above the current limit (₹1 lakh per invoice at the time of writing; keep the limit as a setting)
- **B2CS (7)**: All other sales to unregistered customers, summed by place of supply and rate
- **CDNR / CDNUR (9B)**: Credit and debit notes, to registered and to unregistered customers, linked to the original invoice
- **Exports (6A)**: Only if the business exports: with or without tax payment, shipping bill details
- **Nil, exempt and non-GST (8)**: Sales at 0% or exempt, if any
- **HSN summary (12)**: Grouped by HSN/SAC, unit (UQC), quantity, taxable value and tax, with separate B2B and B2C tabs, and the number of HSN digits required by turnover (a setting: 4 or 6)
- **Documents issued (13)**: For each series: first and last number, total issued, cancelled, and net issued

Outputs:

JSON in the format the GST portal’s offline tool accepts, for upload;
- an Excel workbook with one sheet per table, for the accountant;
- Tally XML for the books.
Checks before export (shown as a list of warnings, with links to the invoices concerned):
- GSTIN format and checksum; place of supply missing; a rate that is not a valid GST rate;
- HSN missing; a credit note with no original invoice; gaps or duplicates in invoice numbers; invoices dated in a period already exported.
After filing:
- Lock the period. Invoices in it can no longer be edited. Corrections are made with credit or debit notes (or amendments in a later return), never by editing a filed invoice.
- Record the date and the user who exported each return.
Related rules to switch on only if they apply (as settings, checked with the business’s accountant):
- e-invoicing (IRN and signed QR on the invoice) when turnover is above the government limit; e-way bill details for goods moved above the value limit; reverse charge; cess.
Tax rules and limits change. Keep every limit and rate in settings or a dated table, never in code, and note in NOTE
S.md that the accountant should confirm them before launch.

## 9. Payments and payment gateways

### 9.1 Settings asked for in the Business Profile (when a gateway is used)
- **Field**: Notes
- **Gateway**: Razorpay (default in India), or Cashfree, PhonePe, PayU or Stripe. Build behind one payment adapter so the gateway can be changed
- **Mode**: Test / Live. Live shows a warning and asks for confirmation before switching
- **Key ID (test and live)**: Stored as a setting; shown in the browser only as the public key
- **Key secret (test and live)**: Secret: stored encrypted, never sent to the browser, shown masked ( ••••1234 ) after saving, with a “Replace” button
- **Webhook secret**: Secret, the same handling
- **Webhook URL**: Shown read-only for copying into the gateway dashboard ( https://site/api/payments/webhook )
- **Checkout name, logo and theme colour**: What the customer sees on the payment window
- **Payment methods**: UPI, cards, net banking, wallets, EMI: on/off as the gateway allows
- **Field**: Notes
- **Auto-capture**: On (default)
- **Refunds allowed by**: Roles allowed to issue refunds
- **“Test connection” button**: Creates and cancels a ₹1 test order, and confirms the webhook has arrived

### 9.2 How a payment must work
1. The server creates the order (amount in paise, receipt = our order number) and saves it as “Payment pending”. The amount is always worked out on the server, never taken from the browser.
2. The browser opens the gateway checkout with the gateway’s order ID.
3. On success, the browser sends the payment ID, order ID and signature. The server verifies the signature with the key secret, then marks the order Paid, creates the invoice and sends the messages. All of this happens once only.
4. Webhooks ( payment.captured , payment.failed , order.paid , refund.processed and so on) are verified with the webhook secret and processed idempotently: the same event arriving twice changes nothing. A webhook marks the order Paid even if the customer closed the browser before step 3.
5. Failed or abandoned payments: the order stays “Payment pending” for 30 minutes, then “Payment failed”. Stock reserved for it is released. The customer sees “Payment failed. Try again” with the cart kept.
6. Refunds go through the gateway’s API. Record the refund ID and status (initiated, processed or failed), update the status from the webhook, and create the credit note.
7. Never store card numbers, UPI PINs or bank logins. The gateway handles them.

### 9.3 Reports and checks
- A payments list: our order number, gateway payment ID, method, amount, gateway fee and GST on the fee (from the settlement report, if available), status and date.
- Reconciliation: paid orders with no invoice, and gateway payments with no order, are listed as warnings.
- Test mode and live mode are clearly separated: a visible “Test mode” banner; test data never mixed into live reports; test shortcuts (fixed OTPs, fake payments) impossible in live mode.

## 10. Files, uploads, images and PDFs
- Uploads: state the allowed types and size (for example JPG, PNG or PDF, 10 MB). Check the real file type on the server. Store privately and serve through expiring signed links after a login check.
- On phones, allow taking a photo directly: accept="image/*,application/pdf" with camera capture.
- Show a preview, the file name and a remove button. Allow several files when it makes sense.
- Images: serve WebP or AVIF with a JPG/PNG fallback, resized to the space they fill, and lazy-loaded below the first screen. Keep any single image under about 300 KB where possible.
- Downloads: Content-Disposition: attachment with a friendly file name, and show the size (“PDF, 5.7 MB”).
- Compress large PDFs (aim under 6 MB).
- Generated PDFs (invoices, labels, reports) are made on the server, print correctly on A4 or A5, and work in bulk.

## 11. Security
- Check the role on the server for every page and every API call. Hiding a button is not security.
- Passwords hashed; secrets and API keys only in environment variables; nothing secret in the browser code.

- Rate-limit login, OTP, signup, contact forms and any public endpoint. Add a honeypot field or CAPTCHA to public forms if spam appears.
- Use the ORM or parameterised queries (no SQL built from text). Escape all output. Add CSRF protection on cookie sessions.
- Security headers: HTTPS only (HSTS), Content-Security-Policy, X-Frame-Options, Referrer-Policy.
- No personal data in URLs or query strings. No open redirects.
- Audit log for important actions (refunds, edits to invoices, exports, role changes, prescription or medical data changes): who, what, when.
- Access log for sensitive data (health, ID documents): who viewed, printed or downloaded it.
- Backups run daily, and a restore has been tested at least once.

## 12. Privacy: DPDP Act 2023 and DPDP Rules 2025
- A Privacy Notice page in plain English, linked from the footer, signup, checkout and the cookie banner. Name the business (the Data Fiduciary), what is collected, why, who receives it, how long it is kept, and rights and contact.
- Have a lawyer approve it.
- Consent: a tick box that is not ticked in advance, at signup and checkout. Collect separate consent for sensitive data (health, ID). Store each consent with the date, time, notice version and source.
- Customer rights on the account page: download my data, correct, delete account, withdraw consent (as easy as giving it), nominate a person, raise a grievance. An admin queue with a 30-day due date for each request.
- Retention: a daily clean-up job deletes data when its period ends. Warn inactive accounts 48 hours before deleting them. Keep tax records for the legal period, and anonymise rather than delete them.
- Keep security and access logs for at least 1 year.
- Breach plan ( docs/BREACH-RESPONSE.md ): contain it, assess it, inform affected people without delay, and report to the Data Protection Board within 72 hours.
- Children: accounts for 18+ only, unless the project needs a parent-consent flow.
- Cookie notice: if only essential cookies are used, an information bar with OK. If analytics or ads are added, a real Accept/Reject banner, and no tracking before Accept.
- Collect only what the purpose needs (data minimisation).

## 13. Email, WhatsApp and SMS integration

### 13.1 Settings asked for in the Business Profile
- **Channel**: Fields
- **Email**: Provider (SMTP, Amazon SES, SendGrid, Brevo, Zoho, Gmail/Google Workspace), host, port, username, password or API key (secret, masked), From name (the brand), From address, Reply-To (a real inbox), BCC copy to the business (on/off)
- **WhatsApp**: Provider (Meta WhatsApp Cloud API, or Gupshup, Interakt, AiSensy, Wati), WhatsApp Business number, Phone number ID and WhatsApp Business Account ID, access token (secret, masked), webhook verify token, and the approved template name and language for each message
- **SMS (if used)**: Provider, API key (secret), DLT entity ID, sender ID (header), and the DLT template ID for each message
- **Each channel**: “Send test message” button, to a number or email typed by the admin; status “Connected” or the exact error

### 13.2 Which message goes out, and through which channel
- An admin matrix of events × channels, each with an on/off tick box: events: OTP, order confirmed, invoice, shipped, delivered, cancelled/refunded, password changed, enquiry received, staff alerts, reorder reminders and so on; channels: Email, WhatsApp and SMS.
- OTP: WhatsApp or SMS first, with email as the fallback. Order messages go by email (with the invoice PDF) and WhatsApp.
- Staff alerts (new order, low stock, enquiry) go to the numbers and emails listed in settings.

### 13.3 Templates and content
- Email templates: responsive (single column, max 600 px, inline styles); work in Gmail on phone and laptop, and in dark mode; logo header, clear subject, business footer with contact details; a plain-text version as well.
- WhatsApp templates must be approved by Meta before use, in the right category: Authentication for OTPs, Utility for order updates, Marketing for offers. Keep the template text, variables and approval status in the code ( templates/whatsapp.md ) and in settings. Messages outside a template are allowed only within 24 hours of the customer’s last message.
- SMS in India: every template is registered on DLT, and the text sent must match it exactly.
- Attachments: invoices go as a PDF attachment by email. On WhatsApp, send them as a document, or as a short-lived signed link, never a permanent public link.
- Never put sensitive data in messages: health details, prescriptions, passwords, full ID or account numbers.

### 13.4 Sending reliably
- Messages go through a queue (a background job), never inside the web request, so a slow provider never slows the page.
- Retry failed sends 3 times with increasing waits, then mark them “Failed” and show them to Admin.
- Delivery status from provider webhooks (sent, delivered, read, failed, bounced) is stored on each message.
- “Messages sent” page for Admin: every message, with time, event, channel, recipient, status and error; View the exact content, and Resend; search, date filter and pagination.
- Duplicates: the same event sends once only (idempotency key per event and recipient).
- In test mode, messages are recorded, not sent (visible in Messages sent), unless the admin uses “Send test message”.
- Quiet hours for marketing messages (for example 9 am to 9 pm IST). OTPs and order updates are sent at any time.

### 13.5 Consent and opt-out
- Transactional messages (OTP, order updates, invoice) need no extra consent.
- Marketing on WhatsApp, SMS or email needs a separate, unticked opt-in, stored with its date.
- Every marketing email has an unsubscribe link. WhatsApp and SMS replies of STOP are honoured automatically.
- The sending domain has SPF, DKIM and DMARC set up, so mails don’t land in spam. Check this before launch.

## 14. Business details, content and settings
- One source of truth: the business name, legal name, address, GSTIN, phones, emails, website, bank details, UPI ID, licence numbers, logos and social links live in Admin > Business Profile and Settings, and every page, email, invoice and label reads from there. Never hard-code them.
- Feature switches and values the business may change (discount %, minimum quantity, show/hide a badge, session length) are settings, not code.
- Use the exact spelling and wording the client gives. Keep apostrophes consistent. Check the whole site for old names before launch.
- Health, finance or legal claims need the client’s approval (and a lawyer where relevant). Never add claims of your own.
- Standard pages: Home, About, Contact (with a working enquiry form that emails the business), Privacy Notice, Terms, Refund/Cancellation, Shipping. Plus the footer with contact details and a “Designed by” credit if required.
- SEO basics: unique page titles and meta descriptions, Open Graph image, sitemap.xml , robots.txt , favicon set (16, 32, 180, 512), clean URLs with redirects when they change.

## 15. Staff and admin panels
- One login, role-based menus; each role sees only its own pages, enforced on the server.
- Dashboard: key numbers for the selected dates, with charts that use all the data.
- User settings: add or deactivate staff, set roles, reset passwords. No hard limit on the number of users of a role unless asked.
- Every list follows section 5. Every form follows section 1. Every action follows section 4.
- Page action buttons (Create, Export) at the top right, aligned with the heading.

## 16. Testing and quality
- Automated tests: API tests for every rule (prices, tax, permissions, validation), and end-to-end tests for the main journeys (signup, login, buy, pay, admin actions).
- A test that opens every route at every width and fails on horizontal scroll.
- Seed data: an admin from environment variables, plus optional demo data for testing (clearly marked).
- Screenshots of every page at 1366 and 390 px, saved for review.
- A testing checklist for non-technical testers: an Excel sheet with steps, the expected result, a Pass/Fail column, a “Problems found” sheet, and the test logins.
- Some things can only be confirmed by hand (Chrome password saving, real payments, real emails). List them as “Needs hand test”, never “done”.

## 17. Deployment and running
- Settings and secrets through environment variables. A .env.example lists every variable.
- Database migrations run automatically and safely on deploy (with retries, and a direct connection when the database uses a pooler).
- A health-check URL. Error logging (Sentry or similar). Uptime monitoring.
- HTTPS on the real domain, with www and non- www both working.
- Free hosting tiers sleep. Warn the client about the first-load delay, or use a paid tier for launch.
- A rollback plan: the previous version can be redeployed in minutes.

## 18. How the coding agent should work
- Work through the request without stopping to ask. Use placeholders for missing values (see the top of this file).

- Commit each change separately, with a clear message ( change 05.12: … ). Run its checks before committing, then deploy.
- Keep the documents current: REQUIREMENTS.md (what the system does), TECHNICAL-SPEC.md (how), NOTES.md (decisions, placeholders, “Replace before launch”, “Needs client’s confirmation”).
- After each change request, write a CHANGE-STATUS.md table: number, change, status (Done / In progress / Not started / Needs hand test), and where to check it.
- Update the design screens when screens change.
- Never mark something done that wasn’t tested. Never delete data or history to make a change easier; deactivate or hide instead.
- Never remove an existing feature unless the request says so.

## 19. Launch checklist
- All placeholders in NOTES.md “Replace before launch” are filled with real values.
- Test passwords changed; demo data removed; the admin’s password is strong.
- Payment gateway, WhatsApp, SMS and email switched to live keys; “Test connection” and “Send test message”
pass; one real payment and refund done; WhatsApp templates approved.
- If GST-registered: a GSTR-1 export checked by the accountant; GST limits and rates in settings confirmed.
- Real emails arrive (not in spam); SPF, DKIM and DMARC set for the sending domain.
- Domain and HTTPS working; old URLs redirect.
- Privacy Notice, Terms, Refund and Shipping pages approved by the client.
- Backups running; a restore tested.
- Hand tests done: password saving, phone layout, printing invoices and labels.
- Error logging and uptime alerts going to the right person.


