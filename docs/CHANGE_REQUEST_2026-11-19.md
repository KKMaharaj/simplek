# Simplek — Change Request, 19 Nov 2026

**For:** Claude Code, working in `D:\projects\simple_billing` (Flutter app + Supabase).
**From:** the owner, after using build 1.1.0 (20261116) on his phone.
**Read first:** `docs/PROJECT_SUMMARY.md` (how the project is built and released) and the ground
rules in section 9 there (no live-data tests without a backup, migrations with dry runs, secrets
on the server only, higher Android version number for each build).

The **reference invoice** the owner wants copied is saved next to this file:
`docs/reference/invoice-reference-eesha-herbals.pdf`. Open it and look at it before starting change 9.

There are 11 changes, then the done checklist. Work through them in order. Each one says what the
owner asked for, what the code does today, what to build, and how to check it.

**Owner decisions (19 Nov 2026, evening). These are final; don't ask again:**
- **Invoice and quotation numbers:** 2-digit serials for all new documents (change 10).
- **Round off:** round the total to the nearest rupee and show a "Round off" line, exactly as on
  the Eesha Herbals reference (change 9).
- **Theme:** remove the sun/moon icon from the Home top bar as well. The theme setting lives
  only in Settings (change 6).
- **TAX INVOICE or INVOICE** depends only on the GST answer the business gave at sign-up:
  - registered → **TAX INVOICE**, always;
  - not registered → **INVOICE**, with no GST anywhere on it (changes 9 and 11).

---

## 0. Owner actions needed first (Supabase dashboard)

Changes 2 and 3 need emails that show a **code** instead of a link. Neither can work until these
are done. Tell the owner if they are not done yet. Do not try to work around them.

1. **Set up custom SMTP.** Use a sending service, e.g. Resend or Brevo, on a domain the owner
   controls. In the dashboard: Authentication → Emails → SMTP Settings. Without it:
   - Supabase's built-in email sends only about 2 emails an hour for the whole project.
   - It may only deliver to the project's own team addresses.
   - A free-plan project created after 3 June 2026 cannot edit its email templates at all.
2. **Edit the email templates** (Authentication → Emails → Templates) so that **Magic Link**,
   **Confirm signup** and **Reset password** each show the one-time code `{{ .Token }}` in large
   text, with a line such as "Enter this code in Simplek. It expires in 10 minutes." Remove the
   link button, or keep it as a fallback.
3. **Check the code length** under Authentication → Providers → Email (projects created recently
   may default to 8 digits). Set it to 6 if possible. Set the code expiry to about 10 minutes.
   Build the code field for whatever length is configured; don't hard-code 6.
4. Raise the email rate limit (Authentication → Rate Limits) to something sensible, e.g. 60 an hour.

---

## 1. Signature: crop and edit properly

**Owner said:** there is no way to edit or crop the signature. After uploading, it ends up
positioned wrongly ("it goes somewhere else").

**Today:**
- `_pickAndEditImage()` in `lib/main.dart` (around line 710) is the only editor for an uploaded
  signature, logo or QR image. It can rotate and "Crop to square" (a fixed crop from the centre).
  It cannot crop freely.
- A signature photo is wide, so a square centre crop cuts it.
- A photo of a signature on paper keeps its grey paper background. `lib/signature_image.dart`
  then trims around the "ink", which doesn't work on a grey background, so the signature lands
  off-centre or too small.
- The drawn signature (`lib/signature_pad.dart`) cannot be edited after saving.

**Build:**
1. **A real crop editor** for an uploaded signature: drag the corners and edges, pinch or scroll
   to zoom, drag to move, rotate left/right, and Reset.
   - Use a package that works on both Android and web, e.g. `crop_your_image` (pure Flutter).
     `image_cropper` needs native setup and behaves differently on web.
   - Signature aspect: free, with a "Signature shape" preset at about 2.4 : 1, matching the
     200 × 84 pt signature box on PDFs.
2. **Clean background** switch, on by default for signatures. It turns near-white and light-grey
   paper transparent, so only the ink remains. Add a strength slider with a live preview on a
   white and on a chequered background.
3. **Preview on the invoice:** before saving, show the result inside the same box it will use on
   the PDF (with "For BUSINESS NAME" and "Authorised signatory"), so the owner sees exactly where
   it will sit.
4. **Edit later:** in Business Settings and onboarding, the signature tile gets three actions:
   **Edit / crop** (reopens the editor on the current image), **Draw again**, and **Remove**.
5. Use the same editor for the **logo** (free crop, plus a square preset) and the
   **payment QR** (square preset).
6. On the PDF, the signature is centred horizontally in its box, above the signatory line,
   keeping its proportions. It is never stretched, cut off or moved to one side.

**Check:**
- Upload a phone photo of a signature on white paper and on off-white paper. After cropping with
  Clean background on, the PDF shows only the ink, centred, at a readable size.
- Edit an existing signature and save. The PDF changes. The change also appears on the other
  device (web ↔ phone).
- Remove the signature. The PDF shows an empty box and the signatory line, and nothing breaks.
- Works on Android and in the web app.

---

## 2. "Forgot password?" on every login screen

**Owner said:** there is no forgot-password option. Add it.

**Today:** `LoginPage` (`lib/main.dart` around line 2074) has only email, password and "Log in".
There is no reset flow anywhere.

**Build** a code-based reset, not a link, for the same cross-device reason as change 3:
1. Add a **"Forgot password?"** link under the password field on the login screen, on phone and web.
   Show it on the app-lock screen too, under "Log in with password instead".
2. **Screen A, "Reset your password":** an email field (pre-filled from the login screen) and a
   **Send code** button.
   - Calls `auth.resetPasswordForEmail(email)`.
   - Always shows the same message, "If an account exists for this email, we've sent a code",
     so the screen doesn't reveal which emails are registered.
3. **Screen B, "Enter the code":**
   - Code field with paste support and Android one-time-code autofill
     (`autofillHints: [AutofillHints.oneTimeCode]`).
   - **Resend code** with a 60-second countdown, and **Change email**.
   - Verify with `auth.verifyOTP(type: OtpType.recovery, email: ..., token: ...)`.
4. **Screen C, "Set a new password":** New password and Confirm, with the same rules as sign-up
   (at least 8 characters, must match). Save with `auth.updateUser(UserAttributes(password: ...))`.
   Then show "Password changed" and go to Home, now signed in.
5. Friendly errors: wrong code, code expired ("Request a new code"), too many attempts or emails
   ("Please wait a minute and try again"), and no internet. Never show raw exception text.
6. Optional, if quick: **Change password** in Business Settings for a signed-in user, reusing screen C.

**Check:** Request a code on the phone, read the email on a computer, type the code on the phone.
The password changes, and the old password no longer works. Repeat on web. A wrong code and an
expired code each show a clear message.

---

## 3. Sign up with an email code (OTP) instead of a verification link

**Owner said:** the verification link is hard to use. If he opens Gmail on a different device
from the one with the app, tapping "verify" there doesn't verify the app. Send a code he can type in.

**Today:**
- `SignupPage` (around line 2306) calls `signInWithOtp(... emailRedirectTo: _authRedirectUrl)`,
  which sends a magic link.
- `EmailLinkWaitingPage` (around line 2477) waits for the link to open on the same device.
- `PasswordSetupPage` follows.

**Build:**
1. Sign-up keeps its fields (Name, Business name optional, Mobile, Email). Rename the button to
   **Send code**.
   - Call `signInWithOtp(email: ..., shouldCreateUser: true, data: {name, business_name, mobile})`
     **without** `emailRedirectTo`.
2. Replace `EmailLinkWaitingPage` with **"Enter the code sent to <email>"**: the same code field
   as change 2 (paste, autofill, Resend with 60 s countdown, Change email).
   - Verify with `auth.verifyOTP(type: OtpType.email, email: ..., token: ...)`.
3. After a successful code:
   - **New user:** go to `PasswordSetupPage`, then business onboarding, as today.
   - **Email that already has a finished account:** treat it as a login and go straight to Home.
     Don't ask them to set a password again. If the owner prefers, show "You already have an
     account — signed you in".
4. Errors, as in change 2: wrong code, expired code, rate limit, no internet.
5. Leave the old deep-link handling (`simplek://login-callback/` and the web `/app/` redirect) in
   place for one release, so links already in someone's inbox still work. Note in
   `PROJECT_TRACKER.md` that it can be removed later.
6. Update the website's "How it works" text if it mentions verifying by link.

**Check:** Sign up on the phone and read the email on a laptop. Typing the code on the phone
completes sign-up. Same on web. Resend works after 60 s. A wrong code shows an error and does not
create a half-finished account.

---

## 4. Remove "Default place of supply"

**Owner said:** remove the default place of supply; it has no use.

**Keep the Place of supply field on each invoice and quotation.** GST needs it to decide
CGST + SGST versus IGST. Only remove the *business default* setting.

**Today:**
- Onboarding (around line 3233) and Business Settings (around line 5499) both have
  "Default place of supply".
- Invoices and quotations pre-fill their Place of supply from it
  (`BusinessSettings.profile.value['placeOfSupply']`, around lines 7331, 7439, 8604 and 8746).

**Build:**
1. Delete the "Default place of supply" field from onboarding and from Business Settings, with its
   validator ("Select the default place of supply").
2. On a **new** invoice or quotation, Place of supply is filled like this:
   - From the **selected customer's State / UT** (this already happens on customer select,
     around lines 7387, 7663, 8678 and 9064).
   - Before a customer is picked, it falls back to the **business state**.
   - It stays editable.
3. Editing an existing invoice keeps its saved place of supply.
4. Stop reading and writing `placeOfSupply` in the business profile (the `SharedPreferences` key
   and the `place_of_supply` column in `business_profiles`). **Don't drop the database column.**
   Leaving it unused is harmless and avoids a risky migration.

**Check:**
- Onboarding and Settings no longer show the field.
- A new invoice for a Kerala customer, from a Karnataka business, shows Place of supply Kerala
  and charges IGST.
- With no customer selected yet, it shows Karnataka.

---

## 5. Remove "Financial year"

**Owner said:** remove the financial year field; he doesn't think it does anything.

**He's right.** The server works out the financial year from each document's date
(`document_financial_year()` in `supabase/migrations/20260924000000_business_document_numbers.sql`).
The `p_financial_year` argument of `next_invoice_number` and `next_quotation_number` is ignored.

**Build:**
1. Remove the **Financial year** field from onboarding (around line 3249) and Business Settings
   (around line 5514), with its validator.
2. Stop sending `p_financial_year` from the app (around line 7553), and stop saving `financialYear`
   in the profile.
3. Keep the server functions' 3-argument signatures as they are, so older app versions keep working.
4. Don't drop the `financial_year` column.

**Check:**
- New invoices dated 31 Mar 2027 and 1 Apr 2027 still get `…/2026-27/…` and `…/2027-28/01`.
- Onboarding finishes without the field.

---

## 6. Move Appearance and Fingerprint unlock to Settings only

**Owner said:** the Appearance switch and fingerprint/face unlock get too much space. Put them in
Settings; that's enough.

**Today:** both appear in three places:
- the **More** page (`_MorePage`, around lines 1492–1502: "Appearance" heading, `ThemeModeToggle`,
  `AppLockSetting`);
- the wide-screen **sidebar** (`ThemeModeToggle` around line 1342);
- **Business Settings** (around lines 5279–5291).

**Build:**
1. Remove the Appearance section and `AppLockSetting` from the More page, and the theme toggle
   from the sidebar.
2. In Business Settings, put both at the **bottom**, under one small heading, **App preferences**:
   Theme (Light / Dark / Auto) and Fingerprint or face unlock (phone only).
3. **Remove the sun/moon theme icon from the Home top bar** (owner decision: not relevant enough to
   sit on Home). The Home top bar keeps Search and Refresh only.
4. The More page is then: business card, Tools list, Log out.

**Check:** Home, More and the sidebar show no theme or fingerprint controls. Settings shows both at
the bottom, and they still work and are remembered after a restart.

---

## 7. Home → tapping a recent invoice opens *that* invoice

**Owner said:** tapping an invoice under "Recent invoices" opens the full invoice list instead of
the invoice.

**Today:** `lib/modern_ui.dart` line 572 builds
`_RecentInvoiceRow(row: row, onTap: onInvoices)`, so every row opens the list.

**Build:** tapping a row opens the **Invoice view** screen (change 8) for that invoice.
"View all" still opens the list.

**Check:** tap each of the 5 recent invoices. Each one opens its own invoice with the right number
and amount.

---

## 8. Invoices list: tap to open, a Preview action, and an Invoice view screen with every action

**Owner said:** in the full invoice list, tapping an invoice does nothing. It just shows some data,
with no preview. Tapping should open the invoice preview. There should be a **Preview** button,
and the preview should have all the options.

**Today:** in `InvoiceHistoryPage` (around line 8500) the `ListTile` has **no `onTap`**. The only
actions are a ⋮ menu with Edit and Duplicate. Each row shows the number, customer, the raw date
(`2026-11-19`) and the status in capitals, but no amount.

**Build:**
1. **Tap a row → Invoice view.** Load the invoice and its items by id (and its payments, if
   available), then open a full-screen view of the PDF.
   - Reuse `InvoicePdfRenderer` and `_SavedDocumentPreview`.
   - Do not regenerate or re-save anything.
2. **The Invoice view screen** has:
   - **Top bar:** invoice number, status chip (Sent / Partial / Paid), and Close (not
     "Save & Close", because the invoice is already saved).
   - **Action bar:** **Share PDF**, **WhatsApp** (the same 4 options as today), **Email**, **Print**,
     and **Download** on web.
   - **More menu:** **Edit invoice**, **Duplicate invoice**, **Record payment** (pre-selects this
     invoice; hidden when fully paid).
   - A small summary above or below the preview: Total, Paid, Balance due, Due date.
3. **In the list,** add **Preview** as the first item in the ⋮ menu (it opens the same Invoice
   view), before Edit and Duplicate.
4. **Tidy the list rows** to match the Home "Recent invoices" style:
   - customer name as the title;
   - `INV/2026-27/24 • 19/11/2026` as the subtitle;
   - the amount on the right with Indian commas (`₹10,600.21`);
   - a coloured status chip.
5. Do the same for **Quotations**: tap a row opens a Quotation view, with **Preview** first in the
   menu, then the existing status and convert actions.
6. An accountant in view-only mode (`BusinessAccess.readOnly`) gets the view and the share/print
   actions, but not Edit, Duplicate or Record payment.

**Check:**
- Tap any invoice in the list, or on Home: the preview opens within about 2 seconds, and every
  button works.
- Record payment from this screen updates the status chip when you return.
- Works on phone and web.

---

## 9. New invoice PDF design: copy the reference invoice

**Owner said:** he doesn't like the current format. Use the attached invoice (made for
Eesha Herbals by the Cancicare project) as the model:
- the logo, with the business name beside it, top left;
- **TAX INVOICE** top right;
- the whole page inside a border, and every section in its own bordered box;
- clean, elegant, with no layout mistakes, and nothing that looks "auto-generated";
- **non-GST businesses / non-GST supplies show just "INVOICE".**

**Reference:** `docs/reference/invoice-reference-eesha-herbals.pdf` (1 page, A4).
**Code to change:** `InvoicePdfRenderer` in `lib/main.dart` (around line 9668), the quotation PDF
(around line 8095), `lib/signature_image.dart`, `lib/payment_pdf.dart` and
`lib/invoice_palette.dart`.

**What is wrong today** (see `tmp/pdfs/*.pdf`):
- no page border;
- the logo is not placed as in the reference;
- no HSN/SAC column;
- amounts without commas (`Rs. 1180.00`);
- the "Bill to" block has no box;
- on longer invoices the signature can end up alone on an extra page (`tmp/pdfs/white-blue.pdf`
  has a third page holding only "Authorised signatory").

**Layout**, top to bottom, with all boxes the full content width and thin borders in the palette
colour:

1. **Page frame:** a border about 2 pt thick, in the palette's dark colour, around the whole page,
   about 18 pt from the paper edge, **on every page**. Use `pw.MultiPage` with a `pageTheme` whose
   `buildBackground` draws the frame.
2. **Header**, with no box, and a full-width rule under it:
   - **Left:** the logo (about 70 × 70 pt, fitted, not stretched). To its right:
     - **business name** in large bold caps (about 16 pt, palette colour);
     - `GSTIN: <bold>` · `State: Karnataka (29)` (state name with its GST state code);
     - the address over 2–3 lines;
     - `Email: … · Mobile: …`.
   - **Right:** the title, with a short rule under it. The title depends **only** on the business's
     GST registration (`BusinessSettings.isGstRegistered`, the Yes/No asked at sign-up), never on
     the items:
     - registered → **TAX INVOICE** (also when some items are 0%);
     - not registered → **INVOICE**.
   - If there's no logo, the business name starts at the left edge. Leave no empty gap.
   - For a business that isn't registered, leave out the GSTIN line entirely.
3. **Party box**, two columns with a divider:
   - **Left, "Bill to":** customer name in bold, then address, `GSTIN:` (only if the customer has
     one), `Phone:`.
   - **Right:** `Invoice no.`, `Invoice date` (dd/mm/yyyy), `Due date`,
     `Place of supply: Kerala (32)`.
4. **Items table:** a header row filled with the palette colour, with white bold text.
   - Columns: `#` · `Description` · `HSN/SAC` · `Qty` (with unit, e.g. `2 NOS`) ·
     `Rate` (small second line "excl. GST") · `GST` (rate %) · `Amount` (small second line
     "incl. GST").
   - Description may have a small grey second line (e.g. the SKU) if present.
   - Numbers right-aligned; borders on every cell.
   - **The header row repeats on every page.**
   - For a business that isn't registered, leave out the HSN/SAC and GST columns, and use plain
     "Rate" and "Amount".
5. **Words + totals row:**
   - **Left box:** "Amount in words", then the amount (keep `amountInWords()`).
   - **Right:** a bordered totals table:
     - `Subtotal` (small "excl. GST");
     - **`Taxable value`** in bold;
     - then **one line per GST rate**: `CGST @ 9%` and `SGST @ 9%` for intra-state, or
       `IGST @ 18%` for inter-state;
     - **`Round off`**: the difference to the nearest whole rupee, shown with its sign, e.g.
       `Rs. 0.01` or `− Rs. 0.40`. Hide the line when it is 0.00.
     - **`Total payable`** in bold on a light palette-tinted row: the rounded total.
     - If anything is already paid, add `Amount received` and **`Balance due`**.
     - Leave out tax lines for a business that isn't registered.
   - There is no discount line, because Simplek has no discount field. Don't add one now.
   - **How round off works** (owner decision: same as the Eesha Herbals reference):
     - In the invoice and quotation builders: total = taxable value + tax, rounded to the nearest
       rupee, with 50 paise and above rounding up. Show the Round off line and the rounded total
       on screen too.
     - Save the **rounded** amount as `total_amount` (and as `balance_amount` for a new invoice).
       Payments, Home totals, outstanding balances and the UPI QR amount then all use the rounded
       figure.
     - Keep `subtotal`, `tax_amount` and the CGST/SGST/IGST amounts unrounded. GSTR-1 and the
       Tally export keep using them unchanged; the invoice value they report is the rounded total.
     - No new database column is needed. Round off = `total_amount − (subtotal + tax_amount)`,
       worked out when the PDF is drawn. Invoices saved before this change come out at 0.00, so
       the line stays hidden and their totals don't change.
     - Check that `save_invoice` and `convert_quotation_to_invoice` keep the total the app sends.
       If either works out the total again on the server, make it round the same way, in a new
       migration.
   - Amount in words uses the rounded total.
6. **Payment box**, two columns:
   - **Left, "Bank details":** Account name, Bank and branch, A/c No., IFSC.
   - **Right:** the UPI QR (about 70 pt) with the UPI logo under it
     (`assets/branding/upi-logo.png`), and beside it "Scan to pay through UPI",
     `Amount: <balance due>`, `UPI ID: …`.
   - Hide either half if it has no data. Hide the whole box if both are empty.
7. **Terms + signature box**, two columns:
   - **Left:** "Terms and conditions" and the numbered terms.
   - **Right:** `For <BUSINESS NAME>` (bold name), the signature image centred (see change 1),
     a rule, then `Authorised signatory`.
8. **Footer**, centred under the boxes, inside the frame: an optional bold line for the business's
   website or tagline (only if set), then "This is a computer-generated invoice." Add
   `Page x of y` when there's more than one page.

**Rules:**
- **Money:** Indian digit grouping everywhere, `3,33,333.33` style, on the PDF and on screen.
  Embed a Unicode font (e.g. Noto Sans, regular and bold) under `assets/fonts/` so `₹` prints
  instead of `Rs.`.
  - Indian-language customer names (Kannada, Hindi) may still not shape correctly in the `pdf`
    package. Test it, and record the result in `PROJECT_TRACKER.md`; don't block on it.
- **Keep the bottom blocks together:** never split boxes 5–7 across pages, and never leave the
  signature alone on a page. If they don't fit under the table, move them together to the next page.
- **Long text** (addresses, item names, terms) wraps inside its box. Nothing overlaps or runs
  outside the frame.
- **Colours:** keep the 5 palettes (`invoice_palette.dart`). The palette sets the frame, rules,
  table header, titles and tinted total row. Body text stays dark grey or black for reading.
- **Quotation PDF:** same layout, titled **QUOTATION**; `Quotation no.`, `Quotation date`,
  `Valid until` instead of due date; no UPI QR. The bank box is optional.
- **Sample preview** in Settings ("Preview invoice format") uses the new design with sample data.

**Check** by rendering PNGs of these cases and looking at every page:
1. A GST business, intra-state, 1 item.
2. A GST business, inter-state, 3 items with mixed rates (5% + 18%).
3. 30 items: multiple pages, header repeated, frame on every page, bottom blocks kept together.
4. A business that isn't registered (title INVOICE, no GST columns or lines).
5. No logo, no UPI, no bank details.
6. A partly paid invoice (Balance due shown).
7. A long customer address and long item names.
8. A quotation.
9. Round off both ways: 1 × ₹101 @ 5% intra-state (₹106.05 → Round off −0.05, Total ₹106);
   1 × ₹2,666.66 @ 5% intra-state (₹2,799.99 → Round off +0.01, Total ₹2,800, as on the reference).

Compare cases 1 and 2 side by side with the reference PDF. Add a test in `test/` that generates
cases 1, 3 and 4 and checks the page count and that generation doesn't throw.

---

## 10. Invoice and quotation numbers: 2-digit serials

**Owner decision:** use 2-digit serial numbers, like the reference (`EHB/2026-27/19`).

**Today:** the owner's Home screen shows mixed widths: `INV/2026-27/24` and `/23`, but
`INV/2026-27/0022`, `/0021`, `/0020`. Older invoices were numbered with 4 digits. The server
(`allocate_business_document_number`) now pads to 2 digits, which is the format wanted.

**Build:**
1. Check that every place that makes a number (`save_invoice`, `convert_quotation_to_invoice`,
   `next_invoice_number`, `next_quotation_number`, and any fallback in the app) gives
   `PREFIX/YYYY-YY/NN`: 2 digits up to 99, then 100, 101 and so on, with no extra zeros.
2. **Don't renumber existing invoices or quotations.** They are legal documents that have already
   been sent. The old 4-digit numbers stay as they are.
3. The next number continues after the highest serial already used in that financial year, as it
   does today. It must read `0022` and `22` as the same serial, so no number is used twice.
   Add a regression test for this in `supabase/tests/`.
4. Keep the whole number to 16 characters or fewer (a GST rule). Show a warning in Settings if the
   chosen prefix would make it longer.

**Check:** in a test account, the next invoice after `INV/2026-27/0022` and `INV/2026-27/24` is
`INV/2026-27/25`.

---

## 11. Business not registered under GST: no GST anywhere

**Owner said:** sign-up asks whether the business is registered under GST.
- **Registered:** every invoice is a **TAX INVOICE**.
- **Not registered:** never a tax invoice, only **INVOICE**, and no GST.

**Today:** for a business that isn't registered, the invoice and quotation forms still show
"GST rate (%)" on every item, so tax can be charged by mistake (test plan case GST-008). Products
already hide GST for such a business.

**Build**, all driven by `BusinessSettings.isGstRegistered`:
1. **Not registered:**
   - Hide the GST rate field in the invoice and quotation builders, and save the tax as 0
     (`tax_type` `none`).
   - Hide the Customer GSTIN field on invoices.
   - On the PDF: title **INVOICE**, no business GSTIN, no HSN/SAC or GST columns, no tax lines.
   - The invoice still shows Place of supply, Subtotal, Round off and Total payable.
2. **Registered:** keep everything as now. The title is always **TAX INVOICE**.
3. If the business changes its GST registration in Settings, only **new** documents follow the
   new setting. Invoices already saved keep the tax they were saved with. Make sure an old invoice
   never shows tax lines under an "INVOICE" title: use the invoice's own `tax_type`, not the
   current setting, to decide whether tax lines appear on it.
4. Quotations follow the same rules, but keep their title **QUOTATION** either way.

**Check:**
- Account B (not registered): a new invoice has no GST field, and the PDF says INVOICE with no
  GST anywhere.
- Account A (registered): the PDF says TAX INVOICE, including on an invoice where every item is 0%.

---

## Also fix (small, from the owner's screenshot)

- **Home amounts have no commas:** `₹10600.21`. Use the same Indian format helper as change 9,
  e.g. `₹10,600.21`.
- **Invoice list dates are raw ISO** (`2026-11-19`). Show `19/11/2026` (covered in change 8).

---

## Done checklist

- [ ] `flutter analyze`: no new issues. `flutter test`: all pass, plus the new tests (PDF cases,
      code-entry validation, place-of-supply prefill).
- [ ] Tried on the Android phone **and** on the web app (`dart run tool/serve.dart`) for every change.
- [ ] Any database change goes in a new migration with a unique 14-digit version, run with
      `supabase db push --remote --dry-run` first. (None should be needed; don't drop columns.)
- [ ] `PROJECT_TRACKER.md` gets a "November 19 changes" section. Update `docs/PROJECT_SUMMARY.md`
      sections 4 and 7.
- [ ] `docs/Simplek_Test_Plan.xlsx`, if present: update cases AUTH (OTP and forgot password), ONB
      (no default place of supply or financial year), NAV-008 (More page), INV and DOC (preview,
      new PDF layout).
- [ ] Raise `version:` in `pubspec.yaml` above `1.1.0+20261116` (e.g. `1.2.0+20261120`). Build the
      APK, and run `bash tool/build_site.sh` for the web zip.
- [ ] Tell the owner which Supabase dashboard steps (section 0) are still open.
