# Simplek — Change Request, 26 Nov 2026: "made with Simplek" link in the PDF footer (v2)

**For:** Claude Code, working in `D:\projects\simple_billing`.
**From:** the owner.
**Size:** small. You can do it in the middle of a bigger item. Commit it on its own.

## What the owner wants

Every invoice and quotation PDF ends with "This is a computer-generated invoice." He wants it to
also say the document was made with Simplek. Tapping or clicking the word **"Simplek"** in the
PDF opens **https://simplek.in**. The web address itself is not printed.

The domain isn't live yet, but this is the final address. Use it now, not any temporary
address the website has today.

## Where

`lib/document_pdf.dart`, the `footer()` method (section "8. Footer", around line 811). Invoices and
quotations share it, so this one change covers both. Today it has:

```dart
pw.Text(
  'This is a computer-generated '
  '${data.isQuotation ? 'quotation' : 'invoice'}.',
  style: const pw.TextStyle(fontSize: 8, color: muted),
),
```

## The new line

> This is a computer-generated invoice, made with **Simplek**.

- For a quotation, the word is "quotation", as today.
- Only the word "Simplek" is a link, to `https://simplek.in`. Don't print "simplek.in" anywhere
  on the line.
- Keep the 8 pt size and the `muted` colour for the rest of the line. Make "Simplek" `ink` and
  bold, so it reads as a link on screen and still reads clearly when printed. No underline.
- Keep it on one line on A4. Keep the business's own tagline above it and "Page x of y" below it,
  as today.

## How

- Add one constant, for example `const kSimplekWebsite = 'https://simplek.in';`, in
  `document_text.dart`, and use it for the link. Then the address is changed in one place if it
  ever changes.
- Build the line with `pw.RichText` and `pw.TextSpan`s. Give the "Simplek" span
  `annotation: pw.AnnotationUrl(kSimplekWebsite)`. If the `pdf` package version in `pubspec.yaml`
  doesn't support that, put the pieces in a `pw.Row` and wrap the "Simplek" text in
  `pw.UrlLink(destination: kSimplekWebsite, child: ...)`.
- Only the PDF changes. Don't change the WhatsApp or share text, the on-screen invoice preview, or
  the payment receipt.
- This is Simplek's own line, not a business setting. Businesses can't turn it off or edit it.
  It's not shown in Settings.

## Done checklist

- [ ] The footer shows the new line on invoices (GST and non-GST) and quotations, including on
      multi-page documents.
- [ ] Opened in a PDF viewer on a phone and on a computer, tapping "Simplek" opens `https://simplek.in`.
- [ ] A test generates an invoice PDF and checks that it contains the link to
      `https://simplek.in`. Use an uncompressed PDF in the test if needed.
- [ ] `flutter analyze` and `flutter test` pass. One commit, with `CHANGE-STATUS.md` updated.
- [ ] Before pushing to `master`, a screenshot of the footer is sent to the owner.
