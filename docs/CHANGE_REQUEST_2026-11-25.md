# Simplek — Change Request, 25 Nov 2026 (sign-up, customers and the business GST rule)

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner, testing sign-up on the **web app** (screenshot: the business details step of
onboarding). The owner confirmed these problems are on the **web**, not in the phone app.
**Read first:** `docs/PROJECT_SUMMARY.md` and the ground rules there, and `BUILD-STANDARDS.md` (project root). Follow the standard for anything this file doesn't specify. Where they differ, this file wins.
`docs/STANDARDS_GAP_REVIEW.md` lists the deliberate differences.
The owner will send more points. Add them to this file as part 2, part 3 and so on.

---

## 0. Background: which build the owner saw, and a version line

The owner's screenshot from the **web** showed **"Default place of supply"**, because the live web
app was still the 16 Nov build. Since the 25 Nov deployment, https://simplek.pages.dev/app/ runs
**1.2.0 (20261120)** (`app/version.json`), so that field and "Financial year" are gone on the web
too.

**Changes 1–4 below are still needed.** As of 25 Nov evening, `lib/main.dart` and
`lib/modern_ui.dart` were unchanged since 20 Nov:
- the GST question is still a `SwitchListTile`;
- `SearchableStateField` still draws `'Select state'` over the label.

Two of the problems below are made worse by the web specifically:
- **The switch sits far away** because web forms stretch across the full browser width (change 1).
- **PAN isn't capitalised** because `textCapitalization` is only a hint to a phone keyboard; it
  does nothing in a browser (change 2).

Fix them for both platforms anyway: the code is shared. Test on **web first**.

**Do:**
1. Add a small **version line**, e.g. "Simplek 1.2.x (build 2026112x)", in two places:
   - at the bottom of Business Settings;
   - in small grey text under the login form.

   Read it from `package_info_plus`, or a constant kept in step with `pubspec.yaml`. Then the owner
   and tester can always see which build they're on.
2. After this change is done: raise the version and build the APK. The web app now deploys by
   itself when `master` is pushed (`.github/workflows/deploy-site.yml`). Remind the owner to
   **install the APK over the old app**, and tell him which version number to look for.

---

## 5. Run the checks before the automatic deploy

**Today:** `.github/workflows/deploy-site.yml` builds and publishes the web app on **every** push to
`master` that touches `lib/`, `website/`, `web/`, `assets/` or `pubspec.*`. It runs **no** checks
first. The web app uses the live database with the owner's real business data, so a push with a
broken change goes straight to real users.

**Build:**
1. In the workflow, add two steps after "Get packages" and before "Build website and web app":
   `flutter analyze --no-fatal-infos` and `flutter test`. If either fails, the job stops and
   nothing is deployed.
2. Leave out tests that need a device or network. `test/website_sample_test.dart` already skips
   unless `SIMPLEK_SITE_SAMPLE=1`.
3. Add a line to `docs/PROJECT_SUMMARY.md` (release section): "Pushing to master deploys the web
   app to real users. Push only finished, tested work. Use a separate branch for anything in
   progress."

**Check:** push a branch with a deliberately failing test and run the workflow by hand on it. The
deploy step must not run. Then remove the failing test.

---

## 1. "Is your business registered under GST?": a clear Yes / No choice

**Owner said:** the toggle is too far away. It's poor design, and normal users won't notice it.

**Today:** onboarding uses a `SwitchListTile` (`lib/main.dart` around line 3103) with
`contentPadding: EdgeInsets.zero`. On a wide web screen the switch sits at the far right edge,
about 1,700 px from the question. It is also **off by default**, so a GST-registered business that
misses it gets set up as not registered.

**Build:**
1. Replace the switch with **two clear choice buttons** directly under the question, left-aligned:
   **Yes, registered** and **No, not registered**. Use a `SegmentedButton` or two `ChoiceChip`s,
   at least 44 px tall.
   - Use the same style as the customer form's "GST registration *" Yes/No choice, so the app is
     consistent.
2. **No default.** The user must pick one. If they continue without choosing, show
   "Select Yes or No".
3. Show the GST fields (registration type, GSTIN, Verify GSTIN) only after **Yes**. They appear
   right below the choice.
4. Do the same in **Business Settings**, wherever GST registration is switched on or off.
5. **Limit the form width on wide screens.** Onboarding and Business Settings forms should be
   centred and at most about **640 px** wide (`ConstrainedBox` / `Center`). Today fields stretch
   across the whole 1,800 px window, and that is part of why the toggle ends up so far away.

**Check:** on web at 1440 px and 1920 px, and on the phone, the Yes/No buttons sit right under the
question. Neither is selected at first. Continuing without a choice shows the error.

---

## 2. PAN in capital letters automatically

**Owner said:** the PAN should switch to upper case as it's typed.

**Today:**
- The onboarding PAN field (around line 3175) only sets
  `textCapitalization: TextCapitalization.characters`. That is only a keyboard *hint*: it does
  nothing on web or with a physical keyboard, and some Android keyboards ignore it.
- The Settings PAN field (around line 5359, `_profileField`) has no capitalisation at all.

**Build:**
1. Give the PAN field the same upper-case `inputFormatters` already used on the GSTIN field (around
   line 3131), plus `FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))` and
   `LengthLimitingTextInputFormatter(10)`. Do this in **onboarding and Settings**.
2. Do the same for every other code-style field that isn't upper case yet:
   - **IFSC** (onboarding around line 3374, Settings around line 5494): max 11 characters;
   - the **customer GSTIN** in the customer form and on invoices: max 15 characters.
3. Put the formatter in one shared helper (e.g. `upperCaseCodeFormatters(maxLength)`), so all
   fields behave the same.

**Check:** typing `abcde1234f` on web and on the phone shows `ABCDE1234F`. The PAN can't go past
10 characters. Spaces and symbols can't be typed.

---

## 3. State fields: "Select state" overlapping the label

**Owner said:** the state fields overlap. "Select state" is drawn on top of "Business state" (and
on top of "Default place of supply" in the old build).

**Cause:** `SearchableStateField` in `lib/modern_ui.dart` (around line 340).
- It builds an `InputDecorator` with `isEmpty: field.value == null`. That makes the label sit
  inside the box like a placeholder.
- But the child **always** draws `Text(field.value ?? 'Select state')`, so the two texts land on
  the same spot.
- This widget is used in **5 places**: onboarding, Settings, the customer form, and the invoice and
  quotation place-of-supply fields. All five have the bug.

**Fix, in the widget, once:**
- When no state is chosen, draw **only** the label. Leave the child text empty, or use a hint that
  only shows when the label has floated.
- When a state is chosen, the label floats to the border and the state name shows inside.
- Simplest way: set `floatingLabelBehavior: FloatingLabelBehavior.always` with
  `hintText: 'Select state'`, and draw the child text only when a value exists.

**Second screenshot from the owner** (`docs/design/issues/2026-11-25-new-customer-overlap.png`,
web, New Customer dialog):
- "Select state" is drawn over "State / Union Territory *". Same bug.
- The **State field is cut off** at the bottom of the dialog, right above Cancel / Save Customer.
  Nothing shows that the form scrolls.

(Change 6 now removes the State field from the customer form completely, so that particular
overlap disappears. Still fix the widget for the other places it's used.)

Fix the dialog as well:
- the form scrolls inside the dialog, with 16 px of space after the last field;
- the dialog has a maximum height (about 85% of the screen);
- the buttons stay fixed below the scrolling area, with a thin divider line above them;
- the last field is never hidden or cut.

Check the same thing on every other form dialog: new product, record payment, accountant access,
and the GSTIN result popup.

**Check:** all 5 places, empty and filled, in light and dark theme, on phone and web. Nothing
overlaps, and nothing is cut off at the bottom of a dialog. Add a widget test that pumps the field empty and finds the label text once and no
overlapping "Select state" text.

---

## 4. Business NOT registered under GST: no state or place of supply questions

**Owner said:** for a business that isn't registered, "Business state", "Default place of supply"
and "Financial year" aren't needed. Remove them from sign-up.

"Default place of supply" and "Financial year" are already gone in 1.2.0 for **everyone**. Check
that nothing is left of them (labels, validators, saved keys) in onboarding, Settings or anywhere
else. Then:

**Build:**
1. **Not registered:**
   - **Superseded by change 11** (owner, 23:31): there is no separate "Business state" field any
     more. State and District are **required dropdowns inside the business address**, for every
     business, registered or not. Don't drop any database column.
2. **Not registered: invoices and quotations.**
   - Hide the **Place of supply** field on the invoice and quotation forms, and skip its
     "Place of supply is required" check (around lines 7694 and 9181).
   - No tax is charged for such a business (change 9 of 19 Nov), so place of supply has no use.
   - On the PDF, leave out the "Place of supply" line. (The "State: … (code)" header line goes for
     **every** business: see change 11.)
   - The server doesn't require `place_of_supply` (no NOT NULL or check in the migrations), so
     saving it empty is fine. Double-check `save_invoice`.
3. **Registered: fill the state from the GSTIN.**
   - The first 2 digits of a GSTIN are the state code (29 = Karnataka, 32 = Kerala, …).
   - As soon as a valid GSTIN is typed, or verified, set the **State dropdown in the business
     address** (change 11) from it and show it **read-only**, with "From your GSTIN" as helper text.
     The District dropdown then lists that state's districts.
   - Then a registered business never has to pick a state by hand, and the state can't disagree
     with the GSTIN.
   - **Decide CGST + SGST versus IGST by comparing state codes** (business GSTIN or state, against
     the place of supply), never typed state names (BUILD-STANDARDS 8.1).
   - **GSTIN validation everywhere** (business, customer, invoice): the pattern **plus the
     checksum** (BUILD-STANDARDS section 1).
     - Show the lookup's real status (Active, Cancelled and so on). Never assume "Active".
     - A failed lookup is never shown as "Verified".
   - Keep the state code → state map in one place: the new `states` master table (change 11).
4. **Switching later in Settings:**
   - **Not registered → registered:** ask for the GSTIN; the state fills from it.
   - **Registered → not registered:** the address State becomes editable again; hide place of
     supply.
   - Saved invoices keep their own place of supply and tax as they were saved.

**Check:**
- **Account B** (not registered): sign-up asks Name, Business name, GST = No, PAN (optional),
  prefixes, the address (with its State and District dropdowns, change 11), mobile and email. No
  separate state field, no place of supply, no financial year. A new invoice
  has no Place of supply field, and its PDF shows none.
- **Account A** (registered): typing GSTIN `29…` fills "Karnataka" read-only. Invoices still
  choose CGST + SGST or IGST correctly from the customer's state.

---

## 6. TOP PRIORITY: the business's GST status decides everything, including the customer form

**Owner said:** the most important setting is on the business profile: is the *business* registered
under GST? If it isn't, it doesn't matter whether a customer is registered. Such a business can never
raise a GST or tax invoice. Its documents are just **INVOICE**, with no GST options anywhere.
Give this rule top importance.

**Rule, to be applied everywhere from one place (`BusinessSettings.isGstRegistered`):**
- **Business not registered** → no GST anywhere in the app or on any document. The title is always
  **INVOICE**.
- **Business registered** → the title is always **TAX INVOICE**. This includes sales to customers
  who aren't registered: those are normal B2C tax invoices with GST charged. Don't confuse the
  customer's registration with the business's.

**Today:** the New Customer dialog (`lib/main.dart` around lines 11096–11390, owner's screenshot)
always opens with **"Is the customer registered for GST?"**, a required Yes/No dropdown. **Every
other field stays hidden until it is answered** (`if (_isGstRegistered != null)`, around line 11330).
For a business that isn't registered, this blocks the form behind a question that doesn't apply.

**Build:**
1. **Customer form, business not registered:**
   - Don't show "Is the customer registered for GST?", the GSTIN field or Verify.
   - Open straight on **Customer name\***, Mobile, Email, Address. **No State field.**
   - Save `gstin` as empty.
2. **Customer form, business registered:**
   - Keep the question, but show it as **Yes / No buttons** (same style as change 1), not a dropdown.
   - Show Name, Mobile, Email and Address **straight away**; don't hide them until the question is
     answered.
   - GSTIN and Verify appear only after **Yes**.
   - **No State field here either** (owner decision, 25 Nov 23:13: "while adding a customer, the
     state of supply doesn't matter; remove this option"). When a GSTIN is entered or verified,
     save the customer's `state` **silently** from the GSTIN's first two digits (29 → Karnataka),
     or from the verified GST data. Use the same state-code map as change 4.
   - A customer without a GSTIN is saved with no state.
2a. **Place of supply moves to the invoice** (GST-registered business only; an unregistered business
   has none, see change 4). On a new invoice or quotation, fill it in this order:
   1. the state from the customer's GSTIN;
   2. otherwise the customer's saved state (older customers keep theirs);
   3. otherwise the **business state**.

   It stays editable on the invoice, using the fixed state picker from change 3. This replaces the
   19 Nov rule "fill from the customer's State / UT". Existing customers keep their saved state;
   don't delete it.
3. **Existing customers that already have a GSTIN,** under a business that isn't registered: keep the
   data, but don't show or print it. The PDF "Bill to" box has no customer GSTIN line for a business
   that isn't registered.
4. **Check every screen against the rule,** and fix any that still show GST for a business that
   isn't registered. For a business that isn't registered:
   - **Onboarding and Settings:** no GST fields. State and District are part of the address
     (change 11).
   - **Products and services:** no HSN/SAC and no GST rate. This already works; keep it.
   - **Customers:** as above.
   - **Invoices and quotations:** no GST rate, no customer GSTIN, no place of supply; tax saved as 0.
   - **PDF:** title INVOICE; no GSTIN lines; no HSN/SAC or GST columns; no CGST/SGST/IGST lines.
   - **Reports:** hide the **GSTR-1** tables and the "GSTR-1 validation" message. Keep the sales,
     collected and outstanding totals, the customer-wise and item-wise sales, and the PDF, Excel
     and CSV exports. The TallyPrime export carries no tax lines.
   - **Search, WhatsApp and email messages:** no "tax invoice" wording.
5. Add one widget test per area that pumps the screen with `isGstRegistered = false` and checks
   that "GST", "GSTIN", "HSN" and "TAX INVOICE" don't appear. (The business name may contain
   letters like "GST"; search for the labels, not raw substrings.)

**Check:**
- **Account B** (not registered): New Customer opens straight on Name, with no GST question and no
  State; every invoice PDF says INVOICE; Reports show no GSTR-1.
- **Account A** (registered): New Customer shows Yes/No buttons with the other fields already
  visible, and no State field.
  - A customer saved with GSTIN `32…` gets Place of supply **Kerala (32)** on a new invoice, with
    IGST.
  - A customer with no GSTIN gets the business state, and the user can change it on the invoice.
  - An invoice to an unregistered customer still says **TAX INVOICE** and charges GST.

---

## 7. Adding a new product (or customer) from inside an invoice must select it completely

**Owner said** (screenshot `docs/design/issues/2026-11-25-new-item-not-selected.png`, web, New
invoice): he typed "Digital Signature Certificate", chose **Add**, and saved the new product. Back
on the invoice it still looks unselected:
- the field still shows "Type to filter saved products or services";
- the dropdown offers the same product again;
- **Rate is empty.**

Once a product is added it should simply be selected.

**Cause, in the code:**
- `AddProductPage` saves with `insert(product)` and **no `.select()`**. With `returnRecord: true`
  it pops the map it sent (`{...?widget.product, ...product}`, around line 10700), which has
  **no `id`**.
- `_selectInvoiceProduct` (around line 8541) then sets `item.productId = null`, so:
  - the line isn't linked to the product;
  - the last-price lookup is skipped;
  - **HSN/SAC is missing on the PDF**, which reads it from the product record.
- `_RecordAutocompleteField` (around line 470) keeps focus after `onSelected(created)`, so the
  options list opens again. Its helper text stays on even when something is selected.
- `_buildItemRow` (around line 9333) puts the "Item 1" row straight on top of the field with no
  gap, so the floating label "Product or service" collides with "Item 1".

**Second report, a screen recording** (`docs/design/issues/2026-11-25-add-item-click-does-nothing.mp4`,
web): the owner typed "E Pass Tokens", and the list showed **Add "E Pass Tokens" · Create a new
record**. He clicked it about 5 times. Each click highlighted it, but nothing happened:
- the list stayed open;
- the Add product form didn't open;
- he never got back to the invoice with the item selected.

Find the cause on web and on phone. Likely candidates:
- **Taps on the `RawAutocomplete` options overlay get lost on Flutter web**, because the text field
  loses focus on pointer-down and the options rebuild. Check whether `onSelected` is reached at all.
- `onAddRequested` fails silently. For example, the insert is rejected because an **archived**
  product with the same name already exists, and the error never reaches the user.
- `created` comes back `null`, so nothing happens.

Every one of these must show the user something: open the form, or show a clear error.

**Fix, together with the redesign:** replace the inline autocomplete dropdown for items (and for
customers) with a **picker**:
- tapping "Product or service" opens it full-screen on phone, or as a dialog on web;
- a search box at the top;
- a big **"+ Add 'E Pass Tokens' as a new item"** button as the first row, whenever the search has
  no exact match;
- then the saved items.
- Choosing an item closes the picker and returns to the invoice with that item **selected**
  (item 3 below).
- **Add** opens the product form with the name pre-filled. Saving returns **straight to the
  invoice** with the new item selected. Cancel returns to the picker with the search kept.
- Back, Escape or ✕ closes the picker with no change.
- If the name matches an **archived** product, offer **"Restore 'E Pass Tokens'"** instead of
  failing.

**Build:**
1. Save new products with `insert(product).select().single()` (and edits with `.select()`). Return
   the **saved row**, including `id`, `selling_price`, `gst_rate`, HSN/SAC and `uqc_code`.
2. After **Add** in an invoice or quotation item row:
   - run the normal selection (`_selectInvoiceProduct`, and the quotation equivalent near line
     7845), so name, rate, GST % and unit fill in at once and the line is linked by `productId`;
   - close the options list and unfocus the field;
   - put the cursor in **Qty**.
3. **Show a selected product as selected,** matching `docs/design/NewInvoice.png`:
   - a compact card with the item name, `HSN/SAC · GST % · ₹rate`, and a **Change** button;
   - no open search box and no "Type to filter…" helper;
   - the search box only comes back after tapping **Change**, or for a free-text line.
   - If the user edits the text of a linked line, clear `productId`, so a renamed line isn't
     treated as the saved product.
4. Do the same for **customers** added from inside an invoice or quotation
   (`_addCustomerFromDocumentBuilder`): return the saved row and select it fully (name, phone,
   email, GSTIN, and the place of supply per change 6).
5. Put 12 px of space between the "Item 1" heading and the field. The new design (labels above
   fields, `UI_REDESIGN_2026-11-25.md`) removes this kind of collision for good.

**Check:**
- On web and phone, in a new invoice, type a product that doesn't exist and choose Add. Save it
  with rate ₹1,500, GST 18% and a SAC code.
  - Back on the invoice the row shows it **selected**, Rate 1,500, GST 18%, and no dropdown.
  - The PDF shows the SAC code.
  - The next invoice suggests ₹1,500 as the last price.
- Repeat in a quotation, and for a new customer.
- Repeat the owner's recording on web: type "E Pass Tokens" and tap Add **once**. The product form
  opens; Save returns to the invoice with the item selected. Also try an archived name.

---

## 8. Remove SKU from the whole app

**Owner said:** SKU isn't useful for his users. Remove it everywhere. Today it prints under the
item name on the PDF ("SKU: DSC", screenshot `docs/design/issues/2026-11-25-sku-on-pdf.png`).

**Remove it from:**
- the **product form** (`_skuController` and its field, around lines 10506–10780); stop sending
  `sku` on save;
- **lists and pickers:** the product subtitle lines, option text such as
  `'… • ${row['sku']} • …'` (around lines 7841 and 9362), and the picker hint
  "Search name, SKU, type, or UQC" (around line 7586, which becomes "Search name, type or unit");
- **search matching** (around lines 3508, 3536, 7591 and 7595);
- **the PDF:** `InvoiceLineItem.sku` and the `note: 'SKU: …'` line (around lines 8389–8408), and
  the quotation PDF equivalent (around lines 7964–8002). The Description cell then shows only the
  item name.
- **exports** (Excel, CSV, Tally), if any of them include it;
- every `select('… sku …')` that only fed the above.

**Keep the `sku` database column.** Don't drop it; old data stays and nothing reads it.

**Check:** nothing in the app or on any PDF says "SKU". Run `grep -ri "sku" lib/`: only the
untouched database field name may remain, and ideally nothing does. Update the test plan's PRD
cases that mention SKU.

---

## 9. Optional short "Description" (up to 300 characters) on invoices and quotations

**Owner said:** add an optional short description to an invoice, e.g. "Digital signature, valid
2 years, for Mr. Ravi Kumar". On the PDF it goes **between Bank details and Terms and
conditions**, neatly aligned.

**Build:**
1. **Database:** a new migration (unique 14-digit version; dry run first) that:
   - adds `description text` (nullable, `check (char_length(description) <= 300)`) to `invoices`
     and to `quotations`;
   - extends `save_invoice` with `p_description text default null`, keeping older app versions
     working;
   - makes `convert_quotation_to_invoice` copy the description across;
   - adds a regression test in `supabase/tests/`.
2. **New and edit screens** for invoices and quotations: one optional field, **Description**,
   below the items and above the totals.
   - Up to 300 characters (owner, 23:29), with a counter. The field grows to at most 3 lines while
     typing.
   - Placeholder: "Optional, e.g. Digital signature, valid 2 years, for Mr. Ravi Kumar".
   - Duplicate copies it.
3. **PDF** (`lib/document_pdf.dart`):
   - When the description isn't empty, add a full-width bordered box titled **Description**,
     between the Bank details / UPI box and the Terms and conditions / signature box.
   - Same width, border colour, padding and title style as its neighbours. Body text the same
     size as the terms. It wraps to at most 3 lines.
   - When empty, no box and no gap.
   - Keep the rule that the bottom boxes stay together on one page.
4. **Invoice view and lists:** show the description as one grey line under the totals strip in the
   Invoice view. It's searchable in Search everything.
5. Not shown in GSTR-1 or the Tally export.

**Check:** create an invoice with and without a description, and check the PDF:
- the box appears in the right place, aligned with the boxes above and below;
- it vanishes when empty;
- it survives Edit, Duplicate and quotation-to-invoice conversion;
- works on phone and web.

---

## 10. PDF: compact, properly aligned payment box, and more items on one page

**Owner said** (screenshots `docs/design/issues/2026-11-25-upi-box-misaligned.png` and
`…-bank-vs-upi-height.png`):
- the UPI half isn't aligned: the QR is in one place, the UPI text somewhere else, and the UPI ID
  is split over two lines;
- the box is much taller than the bank details next to it, which wastes space;
- use the space saved for a longer description (change 9, now up to 300 characters) and for 2–3
  more item rows before the invoice spills onto a second page.

**Cause** (`lib/document_pdf.dart`, `paymentBox()` around lines 684–725):
- The UPI logo is stacked **under** the 70 pt QR, so that column is about 96 pt tall. The bank
  details are about 60 pt.
- The text column is centred against the whole QR + logo column, so it floats.
- `UPI ID:` and the ID are two separate `pw.Text` lines.

**Build:**
1. **UPI half:** a row with the QR on the left and the text on the right, **top edges aligned**.
   - **QR:** 58 × 58 pt (still about 20 mm, which scans reliably), white background, 3 pt
     padding.
   - **Text column** (4 lines, the same size and line spacing as the bank details):
     1. the **UPI logo** (about 11 pt tall) followed by **"Scan to pay through UPI"** in the
        label style, on one line;
     2. `Amount: ₹5,000.00`;
     3. `UPI ID: 9036426630@ybl` on **one line**: never split. If it's very long, shrink that
        line slightly; don't wrap it.
   - Nothing under the QR.
2. **Both halves the same height and vertically centred** inside the box. The box height then
   follows the bank details: 5 lines, about 60–64 pt in all. Use equal padding on both halves and
   keep the divider line between them. With only bank or only UPI, keep the single half's
   compact height.
3. **Tighten the page** so more fits, without looking cramped:
   - gaps between boxes 12 → 8 pt;
   - box padding `fromLTRB(12, 9, 12, 10)` → `fromLTRB(12, 7, 12, 8)`;
   - item rows: keep the current `vertical: 4.5` padding;
   - header logo 70 → 60 pt;
   - terms + signature box: the signature area at most 56 pt tall;
   - footer top padding 10 → 6 pt.
   - Keep the page border and every box border exactly as they are.
4. **Fits-on-one-page target:** an invoice with header, party box, **8 single-line items**,
   totals with CGST/SGST and round off, bank + UPI, a **300-character description**, 4 lines of
   terms and a signature fits on **one A4 page**. More items still flow to page 2, with the bottom
   boxes kept together (as now).
5. Apply the same compact layout to the **quotation PDF** (bank box only; no QR).

**Check:** render PNGs and compare with the owner's screenshots:
- the QR and its text start at the same top line;
- the UPI ID is on one line;
- the payment box is no taller than the bank details;
- the 8-item invoice above is 1 page;
- a 12-item invoice runs onto 2 pages with nothing split.

Add a test in `test/` that generates the 8-item invoice and asserts it is **1 page**, and the
12-item one is 2.

---

## 11. Business address with State and District dropdowns; no "State (code)" line on the PDF

**Owner said** (screenshot `docs/design/issues/2026-11-25-header-state-line.png`):
- the line **"State: Karnataka (29)"** under the business name isn't needed, for GST or non-GST
  businesses. Remove it.
- when entering the business address (in sign-up and in Business profile), give a **State**
  dropdown and a **District** dropdown that depends on the state. Load all Indian states, union
  territories and their districts into the database and use them. **This is compulsory**, and it
  helps GST invoices.

**Today:**
- the business address is one free-text box, printed line by line (6 lines in the screenshot);
- the state is a separate field;
- `document_pdf.dart` (around line 292) prints `'State: ${stateWithCode(businessState)}'` in the
  header.

**Build:**
1. **Master data** (new migration plus seed, like the HSN/SAC master in `supabase/imports/`):
   - **`states` table:** `name`, `gst_state_code` (2 digits, e.g. 29), `type` (state or UT).
     Include every state and union territory.
   - **`districts` table:** `name`, `state_id`. Every district.
   - **Source:** the Government of India's **Local Government Directory (LGD)**,
     https://lgdirectory.gov.in, "Download Directory" for States and Districts. Use the latest
     download; don't type the list by hand.
   - Commit the CSVs to `supabase/imports/` with a README line naming the source and download
     date.
   - Readable by every signed-in user, writable by nobody.
   - Ship a copy as an app asset (`assets/data/states_districts.json`), so the dropdowns work
     offline and on first launch.
   - Use the same `states` data for the GSTIN → state mapping (changes 4 and 6) and for every
     state picker. Replace the hard-coded `_indianStatesAndUnionTerritories` list.
2. **Business address form** (onboarding step 1 and Business Settings). It replaces the single
   "Business address" box and the separate "Business state" field:
   - **PIN code\* first** (BUILD-STANDARDS section 2). When 6 digits are entered:
     - look the PIN up through the project's own server, i.e. a new Supabase edge function like
       `gstin-lookup`, calling `https://api.postalpincode.in/pincode/{PIN}` with a timeout and a
       Retry button;
     - fill City, District and State; offer a choice when there are several post offices;
     - all fields stay editable;
     - if the lookup fails: "We couldn't find this PIN code; please check it", and the user picks
       from the dropdowns.
   - **Address line 1\*** (house or flat, building);
   - **Address line 2** (street, area; optional);
   - **Landmark** (optional);
   - **City / Town\***;
   - **State\*** (searchable dropdown; read-only and filled from the GSTIN for a registered
     business, per change 4);
   - **District\*** (searchable dropdown, listing only the chosen state's districts; disabled
     until a state is chosen; cleared if the state changes);
   - Country is India (fixed, not shown).
   - Max lengths: 150 per address line, 100 for city.
   - Labels above the fields, per the new design. State and District use the fixed picker from
     change 3.
3. **Database:** add `address_line1`, `address_line2`, `city`, `district`, `state`, `pincode` to
   `business_profiles` (keep the old `address` column).
   - **Existing businesses:** copy the old free-text address into `address_line1`.
   - The next time they open Settings, show a short notice: "Choose your district and PIN code to
     complete your address". Saving requires them.
4. **PDF header:**
   - **Remove the "State: … (code)" line** for every business.
   - Print the address compactly as **one comma-separated text that wraps to at most 2 lines**:
     line 1, line 2, city, district (only if different from the city), state, PIN.
     Example: "Malnad Kitchen, Ratnamma Madhava Rao Road, Opp Sarji Mother and Child Care,
     Durgigudi, Tilak Nagara, Shivamogga, Karnataka 577201".
   - Keep the GSTIN line (registered businesses only) and the "Email · Mobile" line.
   - This also saves height for change 10.
5. **Place of supply** on GST invoices keeps its state code, e.g. "Place of supply: Kerala (32)",
   because GST invoices use the state name and code there. Only the business-header line goes.

**Check:**
- Sign up a non-GST business:
  - State, then District, are required;
  - the District list changes with the state (Karnataka → Shivamogga is listed);
  - a PIN like `077201` is rejected.
- A GST business: typing GSTIN `29…` fills State = Karnataka (read-only); District is still chosen.
- PDF header: no "State: Karnataka (29)"; the address is at most 2 lines.
- An existing business sees the "complete your address" notice and its old address is kept.

---

## Done checklist

- [ ] Each change committed separately (`change 25.NN: …`). `CHANGE-STATUS.md` written: number,
      change, status (Done / In progress / Not started / Needs hand test), where to check.
      Placeholders and open questions in `NOTES.md`.
- [ ] `flutter analyze` clean; `flutter test` all pass, plus new tests for the state field, the
      upper-case formatters and the GSTIN → state mapping.
- [ ] Tried by hand on web (1440 px and phone width) and on the Android phone.
- [ ] Version raised in `pubspec.yaml`, APK built, site zip built. Version line visible in
      Settings and on the login screen.
- [ ] `PROJECT_TRACKER.md` updated. Test plan `docs/Simplek_Test_Plan.xlsx`: update ONB-001,
      ONB-002, ONB-006, ONB-007 and the GST cases for non-registered businesses.
- [ ] Deploy workflow runs `flutter analyze` and `flutter test` before publishing (change 5).
- [ ] Every screen checked against the business-GST rule, with the new widget tests (change 6).
      Do change 6 together with changes 1 and 4, since they touch the same forms.
- [ ] Adding a product or customer from inside an invoice or quotation selects it completely,
      with rate, GST %, HSN/SAC and the link to the saved record (change 7).
- [ ] No "SKU" anywhere in the app or on PDFs (change 8). Optional Description field saved,
      editable, copied on duplicate and convert, and printed between Bank details and Terms
      (change 9). Migration dry-run first.
- [ ] Payment box compact and aligned; an 8-item invoice with a 300-character description fits
      on one page (change 10).
- [ ] States and districts loaded from LGD (with source noted). Business address has required
      State and District dropdowns. No "State (code)" line in the PDF header (change 11).
- [ ] After pushing, check https://simplek.pages.dev/app/version.json shows the new version. Tell
      the owner to install the APK over the old app, and which version number to expect.
