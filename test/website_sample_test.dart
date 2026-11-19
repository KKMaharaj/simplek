// Writes the sample invoice shown on the website, from made-up data only.
// Skipped in normal runs. Regenerate with:
//   SIMPLEK_SITE_SAMPLE=1 flutter test test/website_sample_test.dart
// It writes build/website-sample/invoice-sample.pdf; tool notes in
// PROJECT_TRACKER.md (19 Nov website) explain how it becomes a PNG/WebP.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/document_pdf.dart';
import 'package:simplek/money.dart';

// Clearly dummy identifiers: no real GSTIN, bank account or UPI ID.
const _profile = <String, String>{
  'name': 'Malabar Traders',
  'gstin': '32AAAAA0000A1Z5',
  'businessState': 'Kerala',
  'address': '14 Market Road, Kozhikode - 673001, Kerala',
  'email': 'accounts@example.com',
  'phone': '90000 00000',
  'bankName': 'Sample Bank',
  'bankBranch': 'Kozhikode',
  'bankAccount': 'XXXXXXXX4321',
  'ifsc': 'SMPL0000000',
  'invoiceTheme': 'white-blue',
};

PdfLineItem _item(
  String name,
  double qty,
  double rate,
  double gst,
  String hsn,
) {
  final taxable = qty * rate;
  return PdfLineItem(
    description: name,
    quantity: qty,
    unit: 'NOS',
    rate: rate,
    taxable: taxable,
    gstRate: gst,
    tax: taxable * gst / 100,
    hsn: hsn,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'website sample invoice',
    () async {
      final items = [
        _item('Steel almirah, 4 shelves', 2, 8475, 18, '94032090'),
        _item('Office chair, mesh back', 4, 2118.64, 18, '94013000'),
        _item('Delivery and fitting', 1, 500, 18, '996511'),
      ];
      final exact = items.fold<double>(0, (sum, item) => sum + item.amount);
      final pdf = await buildDocumentPdf(
        PdfDocumentData(
          kind: PdfDocumentKind.invoice,
          number: 'MT/2026-27/24',
          date: DateTime(2026, 11, 19),
          secondDate: DateTime(2026, 11, 26),
          placeOfSupply: 'Kerala',
          customerName: 'Kiran Stores',
          customerAddress: '2 Beach Road, Kannur - 670001, Kerala',
          customerGstin: '32BBBBB1111B1Z5',
          customerPhone: '90000 00001',
          items: items,
          total: roundToRupee(exact),
          terms:
              '1. Goods once sold will not be taken back.\n'
              '2. Subject to Kozhikode jurisdiction.',
          gstDocument: true,
        ),
        _profile,
      );
      await Directory('build/website-sample').create(recursive: true);
      await File('build/website-sample/invoice-sample.pdf').writeAsBytes(pdf);
    },
    skip: Platform.environment['SIMPLEK_SITE_SAMPLE'] != '1',
  );
}
