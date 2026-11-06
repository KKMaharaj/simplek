import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:simplek/invoice_palette.dart';
import 'package:simplek/whatsapp_contact.dart';
import 'package:simplek/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'WhatsApp numbers normalize without corrupting international numbers',
    () {
      expect(whatsappNumber('98765 43210'), '919876543210');
      expect(whatsappNumber('+91 (98765) 43210'), '919876543210');
      expect(whatsappNumber('0091 9876543210'), '919876543210');
      expect(whatsappNumber('09876543210'), '919876543210');
      expect(whatsappNumber('+44 7700 900123'), '447700900123');
      expect(whatsappNumber(''), isNull);
      expect(whatsappNumber('123abc456789'), isNull);
      const message = 'Hello, PFA invoice INV/2026-27/1 & kindly pay.';
      final uri = whatsappChatUri('919876543210', message);
      expect(uri.path, '/919876543210');
      expect(uri.queryParameters['text'], message);
    },
  );

  test('five readable palettes and stable default', () {
    expect(InvoicePalette.options.map((p) => p.id).toSet().length, 5);
    expect(InvoicePalette.resolve(null).id, 'white-blue');
    expect(InvoicePalette.resolve('unknown').id, 'white-blue');
    for (final palette in InvoicePalette.options) {
      final contrast =
          (palette.paperColor.computeLuminance() + .05) /
          (palette.inkColor.computeLuminance() + .05);
      expect(contrast, greaterThan(7));
    }
  });

  test(
    'all five real invoice PDFs render with multi-page line items',
    () async {
      final items = List.generate(48, (i) {
        final item = InvoiceLineItem();
        item.productController.text = 'Example product ${i + 1}';
        item.quantityController.text = '2';
        item.rateController.text = '500';
        item.gstRateController.text = '18';
        return item;
      });
      try {
        for (final palette in InvoicePalette.options) {
          final page = InvoicePreviewPage(
            customerName: 'Sample Customer',
            customerAddress: 'Customer Road\nMumbai, Maharashtra',
            customerGstin: '27ABCDE1234F1Z5',
            customerPhone: '9876543210',
            customerEmail: '',
            placeOfSupply: 'Maharashtra',
            invoiceDate: DateTime(2026, 9, 22),
            dueDate: DateTime(2026, 9, 29),
            terms: 'Please pay within seven days.',
            items: items,
            invoiceNumber: 'SAMPLE-001',
            balanceDue: 56640,
            previewProfile: {
              'name': 'Sample Business',
              'address': 'Sample Road, Mumbai',
              'businessState': 'Maharashtra',
              'invoiceTheme': palette.id,
              'bankName': 'Sample Bank',
              'bankAccount': '0000000000',
              'ifsc': 'SAMPLE',
            },
          );
          final bytes = await InvoicePdfRenderer(page).build(PdfPageFormat.a4);
          expect(bytes.take(4).toList(), [37, 80, 68, 70]);
          final output = File('tmp/pdfs/${palette.id}.pdf');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(bytes);
        }
      } finally {
        for (final item in items) {
          item.dispose();
        }
      }
    },
  );
}
