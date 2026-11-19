/// Invoice and quotation PDFs, laid out after the Eesha Herbals reference:
/// a frame on every page, a header with the logo and title, bordered boxes
/// for the parties, items, totals, payment and terms, and the bottom boxes
/// kept together so the signature is never left alone on a page.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_text.dart';
import 'invoice_palette.dart';
import 'money.dart';
import 'payment_pdf.dart';
import 'platform/local_files.dart';
import 'signature_image.dart';

enum PdfDocumentKind { invoice, quotation }

class PdfLineItem {
  const PdfLineItem({
    required this.description,
    required this.quantity,
    required this.rate,
    required this.taxable,
    this.tax = 0,
    this.gstRate = 0,
    this.unit = '',
    this.hsn = '',
    this.note = '',
  });

  final String description;

  /// Small grey second line under the description, e.g. the SKU.
  final String note;
  final String hsn;
  final double quantity;
  final String unit;

  /// Price per unit before GST.
  final double rate;
  final double gstRate;
  final double taxable;
  final double tax;
  double get amount => taxable + tax;
}

class PdfDocumentData {
  const PdfDocumentData({
    required this.kind,
    required this.number,
    required this.date,
    required this.items,
    required this.total,
    required this.gstDocument,
    this.secondDate,
    this.placeOfSupply = '',
    this.customerName = '',
    this.customerAddress = '',
    this.customerGstin = '',
    this.customerPhone = '',
    this.paid = 0,
    this.terms = '',
    this.sample = false,
  });

  final PdfDocumentKind kind;
  final String number;
  final DateTime date;

  /// Due date for an invoice, valid-until date for a quotation.
  final DateTime? secondDate;
  final String placeOfSupply;
  final String customerName;
  final String customerAddress;
  final String customerGstin;
  final String customerPhone;
  final List<PdfLineItem> items;

  /// The amount payable as saved: rounded to the rupee for documents made
  /// since 19 Nov 2026, exact for older ones (whose round off is then 0).
  final double total;
  final double paid;
  final String terms;

  /// True for a GST document: the business is registered, or the document
  /// was saved with tax. Decides the title, GST columns and tax lines.
  final bool gstDocument;

  /// Settings preview with sample data.
  final bool sample;

  bool get isQuotation => kind == PdfDocumentKind.quotation;
  double get subtotal => items.fold(0, (sum, item) => sum + item.taxable);
  double get balanceDue => total - paid < 0 ? 0 : total - paid;
}

class _Fonts {
  _Fonts(this.regular, this.bold);
  final pw.Font regular;
  final pw.Font bold;
}

_Fonts? _fonts;

Future<_Fonts> _loadFonts() async => _fonts ??= _Fonts(
  pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')),
  pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')),
);

bool _sameState(String a, String b) =>
    a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ==
    b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Builds the PDF for [data] using the business [profile].
Future<Uint8List> buildDocumentPdf(
  PdfDocumentData data,
  Map<String, String> profile, {
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final fonts = await _loadFonts();
  final palette = InvoicePalette.resolve(profile['invoiceTheme']);
  final logoBytes = await readLocalFile(profile['logoPath']);
  final signature = await loadPdfSignature(profile['signaturePath']);
  final qr = data.isQuotation
      ? null
      : await paymentQrImage(
          profile,
          amount: data.balanceDue > 0 ? data.balanceDue : null,
        );
  final upiLogo = qr == null ? null : await upiLogoImage();
  final layout = _Layout(
    data: data,
    profile: profile,
    palette: palette,
    logo: logoBytes == null ? null : pw.MemoryImage(logoBytes),
    signature: signature,
    qr: qr,
    upiLogo: upiLogo,
  );
  final pdf = pw.Document(
    title: '${layout.title} ${data.number}',
    author: profile['name'] ?? 'Simplek',
    creator: 'Simplek',
  );
  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 30),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold)
            .copyWith(
              defaultTextStyle: pw.TextStyle(
                fontSize: 9.5,
                color: _Layout.text,
                lineSpacing: 1.5,
              ),
            ),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(
            color: palette.pdfPaper,
            padding: const pw.EdgeInsets.all(18),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: palette.pdfInk, width: 2),
              ),
            ),
          ),
        ),
      ),
      footer: layout.footer,
      build: (context) => [
        layout.header(),
        pw.SizedBox(height: 12),
        layout.partyBox(),
        pw.SizedBox(height: 12),
        layout.itemsTable(),
        pw.SizedBox(height: 12),
        // Boxes 5-7 move to the next page together rather than split.
        pw.Container(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              layout.wordsAndTotals(),
              if (layout.paymentBox() case final payment?) ...[
                pw.SizedBox(height: 12),
                payment,
              ],
              pw.SizedBox(height: 12),
              layout.termsAndSignature(),
            ],
          ),
        ),
      ],
    ),
  );
  return pdf.save();
}

class _Layout {
  _Layout({
    required this.data,
    required this.profile,
    required this.palette,
    required this.logo,
    required this.signature,
    required this.qr,
    required this.upiLogo,
  });

  final PdfDocumentData data;
  final Map<String, String> profile;
  final InvoicePalette palette;
  final pw.MemoryImage? logo;
  final pw.MemoryImage? signature;
  final pw.MemoryImage? qr;
  final pw.MemoryImage? upiLogo;

  static const text = PdfColor.fromInt(0xFF1F2430);
  static const muted = PdfColor.fromInt(0xFF5B6170);

  PdfColor get ink => palette.pdfInk;
  PdfColor get tint => PdfColor(
    ink.red * 0.1 + 0.9,
    ink.green * 0.1 + 0.9,
    ink.blue * 0.1 + 0.9,
  );
  pw.BorderSide get line => pw.BorderSide(color: ink, width: 0.8);

  String get businessName {
    final name = (profile['name'] ?? '').trim();
    return name.isEmpty ? 'Your Business Name' : name;
  }

  String get businessState => (profile['businessState'] ?? '').trim();

  bool get intraState =>
      data.placeOfSupply.trim().isEmpty ||
      _sameState(data.placeOfSupply, businessState);

  String get title => data.isQuotation
      ? 'QUOTATION'
      : (data.gstDocument ? 'TAX INVOICE' : 'INVOICE');

  pw.TextStyle get label =>
      pw.TextStyle(fontWeight: pw.FontWeight.bold, color: ink);

  pw.Widget _box(pw.Widget child, {pw.EdgeInsets? padding}) => pw.Container(
    padding: padding ?? const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
    decoration: pw.BoxDecoration(border: pw.Border.fromBorderSide(line)),
    child: child,
  );

  /// Two halves inside one bordered box, with a divider between them. A
  /// table sizes the row to the taller half and draws the divider itself.
  pw.Widget _split(pw.Widget left, pw.Widget right, {int leftFlex = 1}) =>
      pw.Table(
        border: pw.TableBorder.all(color: ink, width: 0.8),
        columnWidths: {
          0: pw.FlexColumnWidth(leftFlex.toDouble()),
          1: const pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: left,
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: right,
              ),
            ],
          ),
        ],
      );

  // 2. Header -------------------------------------------------------------
  pw.Widget header() {
    final gstin = (profile['gstin'] ?? '').trim();
    final contact = [
      if ((profile['email'] ?? '').trim().isNotEmpty)
        'Email: ${profile['email']!.trim()}',
      if ((profile['phone'] ?? '').trim().isNotEmpty)
        'Mobile: ${profile['phone']!.trim()}',
    ].join(' · ');
    final state = businessState.isEmpty
        ? ''
        : 'State: ${stateWithCode(businessState)}';
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: ink, width: 1.6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 70,
              height: 70,
              alignment: pw.Alignment.center,
              child: pw.Image(logo!, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 12),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  businessName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                    lineSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 4),
                if (data.gstDocument && gstin.isNotEmpty)
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'GSTIN: $gstin',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        if (state.isNotEmpty) pw.TextSpan(text: ' · $state'),
                      ],
                    ),
                  )
                else if (state.isNotEmpty)
                  pw.Text(state),
                if ((profile['address'] ?? '').trim().isNotEmpty)
                  pw.Text(profile['address']!.trim()),
                if (contact.isNotEmpty) pw.Text(contact),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.only(bottom: 4),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: ink, width: 2),
                  ),
                ),
                child: pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 17,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                    lineSpacing: 1,
                  ),
                ),
              ),
              if (data.sample)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 5),
                  child: pw.Text(
                    'SAMPLE – not a real document',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: muted,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // 3. Parties ------------------------------------------------------------
  pw.Widget partyBox() {
    final noun = data.isQuotation ? 'Quotation' : 'Invoice';
    final customer = data.customerName.trim();
    return _split(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(data.isQuotation ? 'Quotation for' : 'Bill to', style: label),
          pw.Text(
            customer.isEmpty ? '-' : customer.toUpperCase(),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: ink),
          ),
          if (data.customerAddress.trim().isNotEmpty)
            pw.Text(data.customerAddress.trim()),
          if (data.customerGstin.trim().isNotEmpty)
            pw.Text('GSTIN: ${data.customerGstin.trim().toUpperCase()}'),
          if (data.customerPhone.trim().isNotEmpty)
            pw.Text('Phone: ${data.customerPhone.trim()}'),
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$noun no.: ${data.number}'),
          pw.Text('$noun date: ${displayDate(data.date)}'),
          if (data.secondDate != null)
            pw.Text(
              '${data.isQuotation ? 'Valid until' : 'Due date'}: '
              '${displayDate(data.secondDate)}',
            ),
          if (data.placeOfSupply.trim().isNotEmpty)
            pw.Text('Place of supply: ${stateWithCode(data.placeOfSupply)}'),
        ],
      ),
      leftFlex: 1,
    );
  }

  // 4. Items --------------------------------------------------------------
  pw.Widget _cell(
    String value, {
    String? sub,
    pw.TextAlign align = pw.TextAlign.left,
    bool header = false,
  }) {
    final crossAxis = switch (align) {
      pw.TextAlign.right => pw.CrossAxisAlignment.end,
      pw.TextAlign.center => pw.CrossAxisAlignment.center,
      _ => pw.CrossAxisAlignment.start,
    };
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
      child: pw.Column(
        crossAxisAlignment: crossAxis,
        children: [
          pw.Text(
            value,
            textAlign: align,
            style: header
                ? const pw.TextStyle(
                    color: PdfColors.white,
                  ).copyWith(fontWeight: pw.FontWeight.bold)
                : null,
          ),
          if (sub != null && sub.isNotEmpty)
            pw.Text(
              sub,
              textAlign: align,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: header ? PdfColors.white : muted,
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget itemsTable() {
    final gst = data.gstDocument;
    final headers = <pw.Widget>[
      _cell('#', header: true),
      _cell('Description', header: true),
      if (gst) _cell('HSN/SAC', header: true, align: pw.TextAlign.center),
      _cell('Qty', header: true, align: pw.TextAlign.right),
      _cell(
        'Rate',
        sub: gst ? 'excl. GST' : null,
        header: true,
        align: pw.TextAlign.right,
      ),
      if (gst) _cell('GST', header: true, align: pw.TextAlign.center),
      _cell(
        'Amount',
        sub: gst ? 'incl. GST' : null,
        header: true,
        align: pw.TextAlign.right,
      ),
    ];
    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(24),
      1: const pw.FlexColumnWidth(4.2),
      if (gst) ...{
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.3),
        4: const pw.FlexColumnWidth(1.8),
        5: const pw.FlexColumnWidth(0.9),
        6: const pw.FlexColumnWidth(2),
      } else ...{
        2: const pw.FlexColumnWidth(1.3),
        3: const pw.FlexColumnWidth(1.8),
        4: const pw.FlexColumnWidth(2),
      },
    };
    return pw.Table(
      border: pw.TableBorder.all(color: ink, width: 0.8),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: ink),
          children: headers,
        ),
        for (final (index, item) in data.items.indexed)
          pw.TableRow(
            children: [
              _cell('${index + 1}'),
              _cell(
                item.description.trim().isEmpty ? '-' : item.description,
                sub: item.note,
              ),
              if (gst) _cell(item.hsn, align: pw.TextAlign.center),
              _cell(
                [
                  plainQuantity(item.quantity),
                  if (item.unit.trim().isNotEmpty) item.unit.trim(),
                ].join(' '),
                align: pw.TextAlign.right,
              ),
              _cell(rupees(item.rate), align: pw.TextAlign.right),
              if (gst) _cell(percent(item.gstRate), align: pw.TextAlign.center),
              _cell(
                rupees(gst ? item.amount : item.taxable),
                align: pw.TextAlign.right,
              ),
            ],
          ),
      ],
    );
  }

  // 5. Amount in words and totals -------------------------------------------
  /// Tax lines grouped by rate, split CGST/SGST or IGST, in paise.
  List<(String, int)> taxLines() {
    if (!data.gstDocument) return const [];
    final byRate = <double, int>{};
    for (final item in data.items) {
      if (item.tax == 0) continue;
      byRate.update(
        item.gstRate,
        (paise) => paise + toPaise(item.tax),
        ifAbsent: () => toPaise(item.tax),
      );
    }
    final rates = byRate.keys.toList()..sort();
    return [
      for (final rate in rates)
        if (intraState) ...[
          ('CGST @ ${percent(rate / 2)}', (byRate[rate]! + 1) ~/ 2),
          (
            'SGST @ ${percent(rate / 2)}',
            byRate[rate]! - (byRate[rate]! + 1) ~/ 2,
          ),
        ] else
          ('IGST @ ${percent(rate)}', byRate[rate]!),
    ];
  }

  pw.TableRow _totalRow(
    String name,
    String value, {
    String? sub,
    bool bold = false,
    bool tinted = false,
  }) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: bold ? ink : text,
    );
    return pw.TableRow(
      decoration: tinted ? pw.BoxDecoration(color: tint) : null,
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(10, 5, 8, 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: style),
              if (sub != null)
                pw.Text(
                  sub,
                  style: const pw.TextStyle(fontSize: 7.5, color: muted),
                ),
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(8, 5, 10, 5),
          child: pw.Text(value, textAlign: pw.TextAlign.right, style: style),
        ),
      ],
    );
  }

  pw.Widget wordsAndTotals() {
    final taxable = toPaise(data.subtotal);
    final taxes = taxLines();
    final taxPaise = taxes.fold<int>(0, (sum, line) => sum + line.$2);
    final roundOff = toPaise(data.total) - taxable - taxPaise;
    final rows = <pw.TableRow>[
      _totalRow(
        'Subtotal',
        rupees(taxable / 100),
        sub: data.gstDocument ? 'excl. GST' : null,
      ),
      if (data.gstDocument)
        _totalRow('Taxable value', rupees(taxable / 100), bold: true),
      for (final (name, paise) in taxes) _totalRow(name, rupees(paise / 100)),
      if (roundOff != 0) _totalRow('Round off', rupees(roundOff / 100)),
      _totalRow(
        data.isQuotation ? 'Quotation total' : 'Total payable',
        rupees(data.total),
        bold: true,
        tinted: true,
      ),
      if (!data.isQuotation && data.paid > 0) ...[
        _totalRow('Amount received', rupees(data.paid)),
        _totalRow('Balance due', rupees(data.balanceDue), bold: true),
      ],
    ];
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _box(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Amount in words', style: label),
                pw.Text(amountInWords(data.total)),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 18),
        pw.Expanded(
          child: pw.Table(
            border: pw.TableBorder.all(color: ink, width: 0.8),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
            },
            children: rows,
          ),
        ),
      ],
    );
  }

  // 6. Payment ------------------------------------------------------------
  pw.Widget? paymentBox() {
    final bankName = (profile['bankName'] ?? '').trim();
    final branch = (profile['bankBranch'] ?? '').trim();
    final account = (profile['bankAccount'] ?? '').trim();
    final ifsc = (profile['ifsc'] ?? '').trim();
    final upi = (profile['upiId'] ?? '').trim();
    final hasBank =
        bankName.isNotEmpty || account.isNotEmpty || ifsc.isNotEmpty;
    final bankLine = [
      if (bankName.isNotEmpty) bankName,
      if (branch.isNotEmpty)
        branch.toLowerCase().contains('branch') ? branch : '$branch Branch',
    ].join(', ');
    final bank = !hasBank
        ? null
        : pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Bank details', style: label),
              pw.Text('Account name: $businessName'),
              if (bankLine.isNotEmpty) pw.Text('Bank: $bankLine'),
              if (account.isNotEmpty) pw.Text('A/c No.: $account'),
              if (ifsc.isNotEmpty) pw.Text('IFSC: ${ifsc.toUpperCase()}'),
            ],
          );
    final upiBlock = qr == null
        ? null
        : pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                children: [
                  pw.Container(
                    width: 70,
                    height: 70,
                    color: PdfColors.white,
                    padding: const pw.EdgeInsets.all(3),
                    child: pw.Image(qr!, fit: pw.BoxFit.contain),
                  ),
                  if (upiLogo != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Image(upiLogo!, width: 64, fit: pw.BoxFit.contain),
                  ],
                ],
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Scan to pay through UPI', style: label),
                    if (data.balanceDue > 0)
                      pw.Text('Amount: ${rupees(data.balanceDue)}'),
                    if (upi.isNotEmpty) ...[
                      pw.Text('UPI ID:'),
                      pw.Text(upi.toLowerCase()),
                    ],
                  ],
                ),
              ),
            ],
          );
    if (bank == null && upiBlock == null) return null;
    if (bank == null) return _box(upiBlock!);
    if (upiBlock == null) return _box(bank);
    return _split(bank, upiBlock);
  }

  // 7. Terms and signature -------------------------------------------------
  pw.Widget termsAndSignature() {
    final terms = data.terms.trim();
    return _split(
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (terms.isNotEmpty) ...[
            pw.Text('Terms and conditions', style: label),
            pw.Text(terms),
          ],
        ],
      ),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.RichText(
            textAlign: pw.TextAlign.center,
            text: pw.TextSpan(
              children: [
                const pw.TextSpan(text: 'For '),
                pw.TextSpan(
                  text: businessName.toUpperCase(),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pdfSignatureBlock(signature, lineColor: ink),
        ],
      ),
    );
  }

  // 8. Footer -------------------------------------------------------------
  pw.Widget footer(pw.Context context) {
    final tagline = (profile['tagline'] ?? profile['website'] ?? '').trim();
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (tagline.isNotEmpty)
            pw.Text(
              tagline,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: ink),
            ),
          pw.Text(
            'This is a computer-generated '
            '${data.isQuotation ? 'quotation' : 'invoice'}.',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
          if (context.pagesCount > 1)
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: muted),
            ),
        ],
      ),
    );
  }
}
