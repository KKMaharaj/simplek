# Simplek — New look for the phone app and web app (25 Nov 2026)

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner. The current app feels like "a horrible black and blue terrain". He wants it
light and colourful, in three colours, with clear feedback on every press, and with **no
overlapping text anywhere**.

**The design to copy** is in `docs/design/`, one PNG per screen:
- `Main.png`: the style guide (colours, type, fields, buttons in every state, list row, bottom bar);
- the phone screens: `Login`, `Onboarding`, `Home`, `Invoices`, `InvoiceView`, `NewInvoice`,
  `Quotations`, `ItemPicker`, `Customers`, `NewCustomer`, `Items`, `Payments`, `Reports`, `More`, `Settings`;
- `WebHome.png`: the web app with its sidebar.

The owner also has the live design canvas: https://claude.ai/artifact/3qe9xJds4ZEvm29QT1RYVt
(private to him).

Follow `BUILD-STANDARDS.md` sections 4, 6 and 7 (buttons and feedback, responsive design, accessibility) for anything not shown in the PNGs.

**Do this after** `docs/CHANGE_REQUEST_2026-11-25.md` (changes 1–6). The new look restyles the
same screens, so finish those fixes first. This change is **look only**: don't change what any
screen does, what it saves or its business rules.

---

## 1. Colours: three brand colours, used the same way everywhere

Same family as the website, so the app and site match.

| Token | Hex | Use |
|---|---|---|
| `navy` | `#0B1A33` | Text and headings; the Home "To collect" card; secondary buttons; selected filter chip; the GST "Yes/No" choice when selected |
| `navy2` | `#12306B` | Hover/pressed navy; tiles inside the navy card; invoice-preview accents |
| `orange` | `#F26B1D` | Primary buttons, the Create/New buttons, focus ring, key highlights. **Text on orange is navy** (5.7:1), never white |
| `orangeText` | `#C2410C` | Orange used as text on white (links, "View all", section labels, Log out) |
| `orangeTint` | `#FFF1E8` | Selected bottom-bar pill, "Partial" chip, "To collect" stat, chosen payment method |
| `sky` | `#7CCBFF` | Accents on navy, chart bars, ticks |
| `skyTint` / `skyLine` / `skyText` | `#E8F5FF` / `#BFE6FF` / `#1D6FA3` | "Paid" chip, info boxes, outline-button borders, verified GSTIN |
| `navyTint` | `#E7ECF5` | "Sent" chip, read-only fields (e.g. state from GSTIN) |
| `page` / `line` / `slate` | `#F7F9FC` / `#E2E8F0` / `#475569` | Page background, borders, secondary text |
| `danger` | keep the current red | **Errors only** |

Rules:
- **Remove** `SimplekColors.heroGradient` and the violet colour (`#7A4DF6`). No gradients anywhere.
- The violet, green and amber icon colours on Home go too. Quick-action tiles cycle
  orange tint, sky tint and navy tint, as in `Home.png`.
- Status chips (one helper):
  - **Paid** and **Accepted**: sky tint with sky text;
  - **Partial**: orange tint with orange text;
  - **Sent**: navy tint with navy2 text;
  - **Draft** and **Expired**: grey `#F1F5F9` with slate text.
  - Each chip has a small dot before the word.
- **Light theme is the default** for new installs, and for anyone currently on Auto or Dark.
  Theme stays selectable in Settings → App preferences.
  - The dark theme gets restyled too: page `#0B1A33`, cards `#12306B`, same orange and sky
    accents, white text.
  - It must look as intentional as the light one, and must not be the old near-black blue.

## 2. Type

- **Fraunces** (600) for screen titles ("Invoices", "Set up your business") and the business name
  on Home.
- **Inter** for everything else: 700 for money, 600 for names and labels, 400–500 for body text.
- Bundle both as **TTF files in `assets/fonts/`** (OFL licence; add the licence files) and
  declare them in `pubspec.yaml`. Don't download fonts at runtime: the app must look the same
  offline and on first launch.
- Dates on screens: **DD MMM YYYY** ("19 Nov 2026"). On PDFs: DD/MM/YYYY (BUILD-STANDARDS
  sections 1 and 8.1). The PNGs show dd/mm/yyyy in lists: follow this rule instead.
- Money: Indian commas everywhere (`₹10,600.21`), using the existing helper in `lib/money.dart`.

## 3. Components (match `Main.png`)

- **Buttons:**
  - Primary: orange with navy text.
  - Secondary: navy with white text.
  - Outline: white, `skyLine` border, navy text.
  - Text: orange text.
  - At least 48 px tall, 12 px corner radius (not full pills).
  - Labels never wrap: one line, and long labels shorten with "…".
- **Press feedback, on every tappable thing** (buttons, list rows, chips, tabs, cards):
  1. scale to **0.98** for about 80 ms (BUILD-STANDARDS section 4) (`AnimatedScale`, or a shared `Pressable` wrapper);
  2. colour deepens one step (orange → `#C2410C` with white text; navy → `#050C1A`;
     outline → `skyLine` fill);
  3. list rows flash `skyTint`;
  4. **phone only:** `HapticFeedback.lightImpact()`.

  Build this once in a shared widget and use it everywhere. Don't hand-tune each screen.
- **Other states** (BUILD-STANDARDS section 4):
  - **keyboard focus:** a visible 2 px orange outline;
  - **disabled:** 50% opacity plus a tooltip or helper saying why;
  - after an action, a toast for about 3 seconds ("Invoice saved");
  - loading lists show skeleton rows, never a blank page;
  - empty lists show a short message plus the next action ("No invoices yet. Create your first
    invoice").
- **Loading on a button:** the button shows a spinner, its label changes ("Saving…"), and it
  ignores further taps until done. This also stops double invoices.
- **Fields:**
  - The **label sits above the box** as a separate `Text` (13 px, 600, navy, with an orange `*`
    if required). Hint text sits inside the box.
  - **Don't use `labelText` / floating labels anywhere.** Floating labels are the main cause of
    the overlapping text the owner reported. Example: `SearchableStateField` draws
    "Select state" on top of its own floating label.
  - White box, 1 px `line` border, 12 px radius, 48 px tall. **Input text 16 px**, so phones don't
    zoom in.
  - On focus: 2 px orange border plus a soft orange ring.
  - Error text in red below the box. Helper text in slate below the box.
- **GST "Yes / No"** and similar choices: two buttons side by side. The selected one is navy
  with a sky tick (`Onboarding.png`, `NewCustomer.png`).
- **Bottom bar (phone):**
  - white; the selected tab has an orange-tint pill behind an orange icon, with a bold navy
    label;
  - other tabs are slate;
  - 5 tabs as today.
- **Floating action button:** orange, navy text, label always visible ("Create",
  "New customer", "Add item", "New quotation").
- **Cards:** white, 1 px `line` border, 16 px radius, no heavy shadow.
- **Screen top bar:** Fraunces title on the left; square 44 px outline icon buttons on the right;
  a square back button on the left where needed.
- **Web sidebar:** white, not navy (`WebHome.png`). Shown at **1024 px and wider**. Below 1024 px,
  a ☰ button opens a full-width slide-in panel, closed with ✕, a link or Escape (BUILD-STANDARDS
  section 6). Phones keep the bottom bar.
  - Orange "Create" button at the top.
  - The selected item has an orange-tint background.
  - The business card and Log out sit at the bottom.

## 4. Screen notes (what the PNGs show)

- **Login:** a navy top panel with the logo and "Simple lekka for your business.", and a white
  card overlapping it with Email, Password and Remember me. **No "Forgot password" yet** (that
  was postponed). Show the version line at the bottom.
- **Onboarding:** step bar (Business / Terms / Branding); GST Yes/No; GSTIN with Verify; PAN in
  capitals; Back and Continue fixed at the bottom.
  - The address is split into Address line 1, Address line 2, City, **State** and **District**
    dropdowns, and PIN (change 11 of 25 Nov). State is read-only from the GSTIN for a registered
    business.
  - The PNG still shows a single "Business state" box: follow change 11.
- **Home:**
  - Business name as the title. Search and Refresh in the top bar. **No sun/moon icon.**
  - Navy "To collect" card with two small tiles and an orange "New invoice" button.
  - Four quick-action tiles.
  - Recent invoices. **Tapping one opens that invoice.**
- **Invoices:** search box; filter chips (All, Unpaid, Partial, Paid); two stat tiles; rows
  grouped by month; orange "Create" button.
- **Invoice view:**
  - Top: number, customer and status chip.
  - Total / Paid / Balance due strip.
  - A preview of the PDF.
  - Bottom: WhatsApp, Share PDF, Print and Email, plus a full-width "Record payment".
- **Item and customer picker** (fixes the owner's "Add does nothing" recording, CR-25 change 7):
  no inline dropdown under the field. A full-screen picker on phone, or a dialog on web, with:
  - a search box;
  - an orange "+ Add '…' as a new item" first row;
  - the saved items below, with name, HSN/SAC · GST % · rate.

  Choosing or adding returns to the invoice with the item selected, shown as the compact card in
  `NewInvoice.png`. See `ItemPicker.png`.
- **New invoice:** customer card with "Change"; date fields; item cards with − / + quantity
  steppers (no SKU anywhere); an optional one-line **Description** field below the items
  (change 9 of 25 Nov); totals card with Round off and an orange "Total payable"; "Save" and
  "Save and preview" fixed at the bottom.
- **Customers / Items / Quotations:** same list style, coloured initial or icon tiles, "… due"
  amounts in orange text, "All paid" in sky text.
- **New customer:** a bottom sheet with **no State field** (owner decision).
  - For a GST-registered business it shows the GST Yes/No question with every other field
    already visible. The state is taken from the GSTIN automatically.
  - For an unregistered business there is no GST question (change 6 of 25 Nov).
- **Record payment:** navy invoice card; big amount field with "Full amount" and "Half"; the
  payment method as a 3-column grid of tiles, chosen one orange-tinted; "Balance after this
  payment".
- **Reports:** period button; four tiles (navy, sky, orange, white); bar chart in sky with the
  current week in orange; "GSTR-1 is ready" card (hidden for an unregistered business); export
  buttons.
- **More:** navy business card; tool rows with coloured icon tiles; Log out in orange text.
  Theme and fingerprint are **not** here.
- **Settings:** Branding (signature with Edit/crop, Draw again, Remove; invoice colour swatches);
  Tax and numbering; **App preferences at the bottom** (Theme: Light/Dark/Auto; Fingerprint or
  face unlock); version line.

## 5. No overlapping text: rules and an automatic check

Rules:
1. Labels go above fields, never floating inside (see section 3). This removes the
   label-plus-hint overlap entirely.
2. Every `Text` in a row with limited width gets `maxLines` and
   `overflow: TextOverflow.ellipsis`. Names, numbers, dates and amounts never wrap into each
   other. Amounts and invoice numbers stay on one line.
3. No fixed heights on anything that holds text. Use `minHeight` / padding instead of
   `SizedBox(height: …)` around text.
4. Nothing positioned with `Stack`/`Positioned` over text. Fixed bottom bars reserve their
   height with padding at the bottom of the scrolling content, so the last field is never
   hidden behind them.
5. Respect the system font size: up to 1.3× must still fit.

Automatic check:
- Add `test/layout_overflow_test.dart`. It pumps every main screen, with sample data and the
  network mocked, at:
  - phones: 320×640, 360, 375, 390 and 414 wide;
  - tablets: 768 and 1024;
  - web: 1280, 1366, 1440 and 1920;
  - and it fails on horizontal scroll (BUILD-STANDARDS section 6);
  - text scale 1.0 and 1.3;
  - light and dark theme.
- It fails on any `RenderFlex overflowed` or other layout exception (`tester.takeException()`).
- Add a widget test that pumps every field type empty and filled, and checks the label text
  appears once and doesn't share its position with the hint.

By hand: on the phone and on web, open every screen. Take screenshots at the largest system font
size and send them to the owner.

## 6. Where to change things

- `lib/app_theme.dart`: new colour tokens, `ThemeData` for light and dark, an input theme with no
  floating label, button themes, chip theme.
- `lib/modern_ui.dart`: shared widgets:
  - `Pressable`, `FieldLabel` + field;
  - `StatusChip`, `YesNoChoice`;
  - `SectionCard`, `ListRowTile`;
  - `BottomBar`, `CreateButton`;
  - Home's money card.

  Also fix `SearchableStateField` here.
- `lib/main.dart`: switch each screen over to the shared widgets. Keep logic untouched.
- Website (`website/index.html`): already uses these colours. No change.

## Done checklist

- [ ] Every screen in `docs/design/` matches on phone and web, in light and in the restyled dark
      theme.
- [ ] No floating labels left (`grep labelText lib/` finds none in screens).
- [ ] `test/layout_overflow_test.dart` passes at all sizes and text scales. `flutter analyze`
      is clean and `flutter test` passes.
- [ ] Press feedback (scale, colour, haptic on phone) works on buttons, rows, chips and tabs.
- [ ] Screenshots of every screen sent to the owner before pushing to `master`. Pushing deploys
      the web app to real users.
- [ ] Version raised; APK built; `PROJECT_TRACKER.md` updated.
