import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/document_pdf.dart';
import 'package:simplek/money.dart';

const _gstProfile = <String, String>{
  'name': 'Eesha Herbals',
  'gstin': '29EMLPS9051L1Z1',
  'businessState': 'Karnataka',
  'address':
      'Ground Floor, G1, "Banashree", Kolluraiah Street, SPM Road, '
      'near Sri Panduranga Vittal Temple, Shivamogga - 577202, Karnataka',
  'email': 'orders@example.com',
  'phone': '9108504009',
  'bankName': 'HDFC Bank',
  'bankBranch': 'Shivamogga',
  'bankAccount': '50200124616049',
  'ifsc': 'HDFC0000839',
  'upiId': 'shop@hdfcbank',
  'invoiceTheme': 'white-blue',
  'logoPath': 'assets/branding/simplek-app-icon-hd.png',
};

const _plainProfile = <String, String>{
  'name': 'Malnad Kitchen',
  'businessState': 'Karnataka',
  'address': 'Sagar Road, Shivamogga',
  'phone': '9000000000',
  'invoiceTheme': 'cream-blue',
};

PdfLineItem _item(
  String name,
  double qty,
  double rate,
  double gst, {
  String hsn = '30049011',
}) {
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

PdfDocumentData _invoice(
  List<PdfLineItem> items, {
  String place = 'Karnataka',
  bool gst = true,
  double paid = 0,
  String address = '12 Market Road, Raichur, Karnataka 584101',
  PdfDocumentKind kind = PdfDocumentKind.invoice,
}) {
  final exact = items.fold<double>(0, (sum, item) => sum + item.amount);
  return PdfDocumentData(
    kind: kind,
    number: kind == PdfDocumentKind.invoice
        ? 'INV/2026-27/25'
        : 'QTN/2026-27/04',
    date: DateTime(2026, 11, 19),
    secondDate: DateTime(2026, 11, 26),
    placeOfSupply: place,
    customerName: 'CA Sachin',
    customerAddress: address,
    customerGstin: gst ? '29ABCDE1234F1Z5' : '',
    customerPhone: '9845333655',
    items: items,
    total: roundToRupee(exact),
    paid: paid,
    terms:
        '1. Goods once sold will not be taken back.\n'
        '2. Subject to local jurisdiction.',
    gstDocument: gst,
  );
}

int _pages(Uint8List pdf) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length;

Future<Uint8List> _render(
  String name,
  PdfDocumentData data,
  Map<String, String> profile,
) async {
  final bytes = await buildDocumentPdf(data, profile);
  if (Platform.environment['SIMPLEK_PDF_QA'] == '1') {
    await Directory('tmp/pdfs-new').create(recursive: true);
    await File('tmp/pdfs-new/$name.pdf').writeAsBytes(bytes);
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round off rounds to the nearest rupee, 50 paise up', () {
    expect(roundToRupee(106.05), 106);
    expect(roundOffFor(106.05), -0.05);
    expect(roundToRupee(2799.99), 2800);
    expect(roundOffFor(2799.99), 0.01);
    expect(roundToRupee(100.5), 101);
    expect(roundToRupee(100.49), 100);
    expect(roundOffFor(250), 0);
  });

  test('amounts use Indian digit grouping', () {
    expect(indianNumber(10600.21), '10,600.21');
    expect(indianNumber(333333.33), '3,33,333.33');
    expect(indianNumber(12345678), '1,23,45,678.00');
    expect(indianNumber(999), '999.00');
    expect(rupees(-0.4), '− ₹0.40');
  });

  test('1: GST business, intra-state, one item fits on one page', () async {
    final pdf = await _render(
      '1-gst-intra',
      _invoice([_item('Rejwin, 1000 ml', 1, 2666.66, 5)]),
      _gstProfile,
    );
    expect(_pages(pdf), 1);
  });

  test('2: inter-state with mixed GST rates', () async {
    final pdf = await _render(
      '2-gst-inter-mixed',
      _invoice([
        _item('Herbal oil, 200 ml', 2, 450, 5),
        _item('Consultation', 1, 1500, 18, hsn: '998311'),
        _item('Soap bar', 6, 60, 5),
      ], place: 'Kerala'),
      _gstProfile,
    );
    expect(_pages(pdf), 1);
  });

  test('3: 30 items span pages without throwing', () async {
    final items = [
      for (var i = 1; i <= 30; i++) _item('Catering item number $i', 3, 250, 5),
    ];
    final pdf = await _render('3-thirty-items', _invoice(items), _gstProfile);
    expect(_pages(pdf), greaterThan(1));
  });

  test('4: business not registered under GST', () async {
    final pdf = await _render(
      '4-not-registered',
      _invoice([
        PdfLineItem(
          description: 'Catering, 15 members',
          quantity: 15,
          unit: 'NOS',
          rate: 250,
          taxable: 3750,
        ),
      ], gst: false),
      _plainProfile,
    );
    expect(_pages(pdf), 1);
  });

  test('5: no logo, no UPI and no bank details', () async {
    final pdf = await _render(
      '5-no-logo-upi-bank',
      _invoice([_item('Rejwin, 1000 ml', 1, 3333.33, 5)]),
      {
        'name': 'Bare Business',
        'businessState': 'Karnataka',
        'gstin': '29AAAAA0000A1Z5',
      },
    );
    expect(_pages(pdf), 1);
  });

  test('6: partly paid invoice', () async {
    final pdf = await _render(
      '6-part-paid',
      _invoice([_item('Rejwin, 1000 ml', 3, 3333.33, 5)], paid: 5000),
      _gstProfile,
    );
    expect(_pages(pdf), 1);
  });

  test('7: long address and long item names wrap', () async {
    final pdf = await _render(
      '7-long-text',
      _invoice(
        [
          _item(
            'Premium cold-pressed Ayurvedic herbal hair oil with bhringraj, '
            'amla, brahmi and coconut base, family pack of 1000 ml',
            2,
            1250,
            12,
          ),
        ],
        address:
            '# 1-10-154, Hotel Nrupatunga, near Dr B R Ambedkar Circle, '
            'Station Road, Raichur 584101, Raichur District, Karnataka, India',
      ),
      _gstProfile,
    );
    expect(_pages(pdf), 1);
  });

  test('8: quotation', () async {
    final pdf = await _render(
      '8-quotation',
      _invoice([
        _item('Rejwin, 1000 ml', 4, 3333.33, 5),
      ], kind: PdfDocumentKind.quotation),
      _gstProfile,
    );
    expect(_pages(pdf), 1);
  });

  test('9: round off both ways', () async {
    await _render(
      '9a-round-down',
      _invoice([_item('Item', 1, 101, 5)]),
      _gstProfile,
    );
    await _render(
      '9b-round-up',
      _invoice([_item('Item', 1, 2666.66, 5)]),
      _gstProfile,
    );
  });
}
