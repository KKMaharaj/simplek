# Simplek website — Change Request, 19 Nov 2026 (part 1)

**For:** Claude Code, working in `D:\projects\simple_billing`.
**File to change:** `website/index.html`. It is the whole public site: one static page, no framework.
**Preview:** `dart run tool/serve.dart`, then open http://localhost:8080.
**Publish:** `bash tool/build_site.sh`, then upload `build/simplek-site.zip` to Cloudflare Pages
(project `simplek`).
**Don't touch the app** (`lib/`) in this change. The website only.

The owner will send more website points. They will be added to this file as part 2, part 3 and so on.

---

## 1. New message: stop saying "sales invoices only"

**Owner said:**
- Saying "sales invoices only" everywhere makes Simplek sound like it couldn't do more. It sounds
  as if we can't build purchases or inventory.
- Present it the other way round. Full accounting software asks for a lot:
  - purchases take a lot of time to enter;
  - stock needs knowledge and staff;
  - most businesses never keep these up;
  - so most of the features go unused, the software feels like a headache, and the reports end up
    incomplete.
- Many businesses buy full accounting software just to send invoices. That's a waste of money and
  time.
- Invoicing is the step every business can't skip: no invoice, no payment.
- Simplek is the simple tool for exactly that, and anyone can use it.

**Do:**
1. **Remove** every "sales invoices only" or "only for sales" phrase. Today it's in:
   - the hero badge ("Sales invoices only. Free for 30 a month.");
   - the hero paragraph ("Simplek does one job: your GST sales invoices. No purchase entries, no
     stock registers…");
   - the "Why it's called Simplek" block ("It is only for creating sales invoices…");
   - the features heading ("Everything a sales invoice needs. Nothing it doesn't.").
2. **Remove** the **"What it leaves out"** list (Purchase invoices / Stock and inventory / Ledgers
   and full accounting / Anything you'd need training for).
3. **Use the copy below.** Small wording fixes are fine; keep the meaning. Never put Simplek down,
   and don't name competitors.

### Hero
- Eyebrow: **GST billing for Indian businesses**
- Headline: **Invoices in a minute.** with the second line in orange: **No accounting software needed.**
- Paragraph: "Create a GST invoice, share it on WhatsApp, and get paid. Your accountant gets GSTR-1
  and Tally files, ready to use."
- Buttons: **Start free** (orange, primary) and **Log in** (outline).
- Line under the buttons: "Free for 30 invoices a month · Android app and web · A login for your
  accountant"

### New section: "Why pay for a full accounting suite just to send invoices?"
Put it straight after the hero. Use three cards, in a calm, factual tone:

1. **Big software, small use.** "Full accounting packages are built for accountants. Most owners
   only ever open the invoice screen, but pay for, and click past, everything else."
2. **Hours of data entry.** "Purchases, stock and expenses need daily entry and trained staff. When
   they fall behind, the reports are wrong anyway."
3. **Invoicing can't wait.** "No invoice, no payment. Billing should be the fastest thing on your
   phone, not something you have to learn."

Closing line under the cards: "Simplek does the part every business needs every day: correct, good-looking
GST invoices, payments and dues. Everything else goes to your accountant in the formats they
already use: GSTR-1, TallyPrime, Excel."

### New section: "Why the name Simplek?"
This replaces the old "Why it's called Simplek / Simple, on purpose." block.
- Heading: **Simple + Lekka**
- Text: "In Kannada, ಲೆಕ್ಕ (lekka) means accounts, the everyday calculations of a business.
  Simplek is simple lekka: your business's numbers, kept simple."
- Show "Simple + Lekka = Simplek" visually: two words joined, with the "k" in orange.
- The Kannada word needs a font that has Kannada, e.g. Noto Sans Kannada (only the characters
  used). Check that it renders on Android Chrome and on Windows.

### Features
- Heading: **Everything you need to bill. Nothing you don't.**
- Keep the six feature cards: GST invoices, Quotations, Payments, Share anywhere, Ready for your
  accountant, A login for your accountant. Update them to match the app as it is now:
  - "Share anywhere": "Clean, bordered invoices with your logo, signature and UPI QR. Share by
    WhatsApp or email, or print."
  - "GST invoices": add "Round-off and amount in words, done for you".
- Keep the "Coming soon" AI card as it is.

### Pricing, How it works, Phone and web
Keep the content. Reword only where it says "sales invoices".
Final call-to-action: **"Your next invoice could be out in a minute."** with a **Start free** button.

### Optional: short FAQ above the footer
Include this only if it fits the design.
- "Does Simplek do purchases and stock?" → "Simplek focuses on invoices, quotations and payments.
  Your accountant can take everything into TallyPrime in one export."
- "Is my data safe?" → "Your data is stored in the cloud, not on one phone. Only you and the
  people you invite can see it."
- "Can my accountant see my invoices?" → "Yes. Give them their own view-only login and remove it
  any time."

### Page title and description
- `<title>`: **Simplek: GST invoicing made simple**
- Add `<meta name="description">`: "Create GST invoices in a minute, share them on WhatsApp and get
  paid. Free for 30 invoices a month. Android app and web."

---

## 2. New colours and a premium look (three colours)

**Owner said:** the current colours look too basic, "too AI". He wants a premium look, using
orange, light blue and one more colour: three colours in all.

**Today:** the site uses a blue-to-purple gradient (`#3B5BFD → #6A4DF4`) on the logo badge,
buttons and highlights, plus green and amber, and a system font. The blue-violet gradient is what
reads as "AI template".

**Palette.** Use only these three brand colours, plus white and greys:

| Role | Colour | Use |
|---|---|---|
| Midnight navy | `#0B1A33` (and `#12306B`, the logo's navy, for hover or secondary navy) | Hero and footer background, headings, body text on light backgrounds |
| Saffron orange | `#F26B1D` | Primary buttons (**navy text on orange**, 5.7:1 contrast), key words in headlines, small accents. For orange *text* on white use `#C2410C` (5.2:1). |
| Sky blue | `#7CCBFF`, tint `#E8F5FF`, border `#BFE6FF` | Accents on navy, light section backgrounds, card borders, icons. For blue text on white use `#1D6FA3`. |
| Neutrals | `#FFFFFF`, `#F7F9FC`, slate `#475569` for secondary text | Page and card backgrounds |

The logo already uses this family (navy `#12306B`, blue `#3E7BE0`, orange `#F5A623`), so the logo
stays as it is.

**Design rules, so it doesn't look AI-made:**
- **No gradients.** No glow blobs, glassmorphism, neon, or purple. Use flat colour blocks.
- **Real product, not decoration.**
  - The hero shows the real app on a phone frame next to a real invoice made with the new PDF
    design (`lib/document_pdf.dart`).
  - Generate a PNG of a sample invoice from **made-up data** (e.g. "Malabar Traders"), never real
    customers. Save it as `website/invoice-sample.png` (and `.webp`).
  - **Don't use the Eesha Herbals reference invoice.** It holds a real business's bank details.
- **Typography:**
  - Headings in a refined serif, e.g. **Fraunces** (weights 500/600); body in **Inter**
    (400/500/600).
  - Self-host the font files (woff2) in `website/fonts/`, with `font-display: swap`. No calls to
    Google Fonts at runtime.
  - Large, confident headings (hero about 56px desktop / 36px phone) and generous line height.
- **Section rhythm:** navy hero → white "Why pay…" → `#E8F5FF` features → white name section →
  `#F7F9FC` pricing → navy final call-to-action and footer.
- **Cards:**
  - white, a 1px `#BFE6FF` or `#E2E8F0` border, radius 10–12px, a very soft shadow or none;
  - icons as simple line icons (inline SVG) in navy or orange;
  - no emoji.
- **Orange is rare.** Use it for primary buttons, one highlighted word or line per heading at most,
  the "Most popular" plan badge and small markers. It must not become the background of big areas.
- **Pricing:** the Unlimited card has a navy background with white text and an orange "Most
  popular" badge. Free stays white.
- **Header:** a sticky white header with a hairline bottom border once you scroll (navy over the
  hero at the top is fine). Show the logo, the menu, **Log in** (text) and **Start free**
  (orange button).
- **Dark mode:** remove the automatic dark colour scheme (`prefers-color-scheme: dark`). The navy
  sections give enough contrast, and one look keeps the brand consistent.
- **Motion:** at most a subtle fade-up of sections on scroll, and it must respect
  `prefers-reduced-motion`.

**Accessibility and quality checks:**
- All text meets WCAG AA contrast. The pairs above are already checked.
- The page works from 360px to 1440px wide with no sideways scrolling. Buttons are at least
  44px tall on phones.
- The page loads fast: compress images, use no framework, keep the whole page under about 1.5 MB.
- Every "Start free" button still goes to `app/?signup=1`, and every "Log in" goes to `app/`.

**Done when:**
- [ ] No mention of "sales invoices only" and no "What it leaves out" list anywhere on the page.
- [ ] "Why pay for a full accounting suite…" and "Simple + Lekka" sections are added. The Kannada
      word renders on Android Chrome and Windows Chrome/Edge.
- [ ] Only navy, orange and sky blue (plus neutrals). No gradients, no purple.
- [ ] Screenshots at 390px and 1440px sent to the owner for approval **before** uploading to
      Cloudflare.
- [ ] After approval: `bash tool/build_site.sh`, upload `build/simplek-site.zip`, and add a line
      to `PROJECT_TRACKER.md`.
