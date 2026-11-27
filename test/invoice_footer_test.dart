// Change request 26 Nov 2026, invoice footer: every invoice and quotation PDF
// ends with "This is a computer-generated invoice, made with Simplek.", where
// only the word "Simplek" links to https://simplek.in, on every page.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/document_pdf.dart';
import 'package:simplek/document_text.dart';
import 'package:simplek/money.dart';

const _profile = <String, String>{
  'name': 'Malnad Kitchen',
  'businessState': 'Karnataka',
  'address': 'Sagar Road, Shivamogga',
  'phone': '9000000000',
  'invoiceTheme': 'cream-blue',
};

PdfDocumentData _document(
  int items, {
  PdfDocumentKind kind = PdfDocumentKind.invoice,
  bool gst = true,
}) {
  final lines = [
    for (var i = 0; i < items; i++)
      PdfLineItem(
        description: 'Item ${i + 1}',
        quantity: 1,
        unit: 'NOS',
        rate: 100,
        taxable: 100,
        gstRate: gst ? 18 : 0,
        tax: gst ? 18 : 0,
        hsn: '30049011',
      ),
  ];
  final exact = lines.fold<double>(0, (sum, item) => sum + item.amount);
  return PdfDocumentData(
    kind: kind,
    number: 'INV/2026-27/30',
    date: DateTime(2026, 11, 26),
    secondDate: DateTime(2026, 12, 3),
    placeOfSupply: 'Karnataka',
    customerName: 'Asha Rao',
    customerAddress: '12 Market Road, Shivamogga',
    customerGstin: '',
    customerPhone: '9845333655',
    items: lines,
    total: roundToRupee(exact),
    paid: 0,
    terms: '',
    gstDocument: gst,
  );
}

int _pages(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length;

int _links(Uint8List pdf) => RegExp(
  r'/URI\s*\(https://simplek\.in\)',
).allMatches(String.fromCharCodes(pdf)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the address is kept in one place', () {
    expect(kSimplekWebsite, 'https://simplek.in');
  });

  for (final (name, kind, gst) in [
    ('GST invoice', PdfDocumentKind.invoice, true),
    ('non-GST invoice', PdfDocumentKind.invoice, false),
    ('quotation', PdfDocumentKind.quotation, true),
  ]) {
    test('$name: one Simplek link on its one page', () async {
      final pdf = await buildDocumentPdf(
        _document(2, kind: kind, gst: gst),
        _profile,
        compress: false,
      );
      expect(_pages(pdf), 1);
      expect(_links(pdf), 1);
    });
  }

  test('a multi-page invoice has the link on every page', () async {
    final pdf = await buildDocumentPdf(
      _document(40),
      _profile,
      compress: false,
    );
    final pages = _pages(pdf);
    expect(pages, greaterThan(1));
    expect(_links(pdf), pages);
  });

  test('the footer line reads "…, made with Simplek." and links only the '
      'word', () {
    final source = File('lib/document_pdf.dart').readAsStringSync();
    expect(source, contains("made with '"));
    expect(source, contains("text: 'Simplek'"));
    expect(source, contains('annotation: pw.AnnotationUrl(kSimplekWebsite)'));
    expect(source, isNot(contains("'simplek.in'")));
  });
}
