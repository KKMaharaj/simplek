import 'dart:io';

// Tests for the 25 Nov 2026 change request (docs/CHANGE_REQUEST_2026-11-25.md).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/document_pdf.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';
import 'package:simplek/money.dart';

TextEditingValue _type(List<TextInputFormatter> formatters, String text) {
  var value = TextEditingValue.empty;
  for (final formatter in formatters) {
    value = formatter.formatEditUpdate(
      TextEditingValue.empty,
      value.text.isEmpty ? TextEditingValue(text: text) : value,
    );
  }
  return value;
}

/// True once tool/import_lgd.dart has filled the district lists.
final _districtsImported = File(
  'assets/data/states_districts.json',
).readAsStringSync().contains(RegExp(r'"districts": \[\s*\{'));

/// A GSTIN with a correct check digit for the given first 14 characters.
String _gstin(String first14) => first14 + gstinCheckCharacter(first14);

/// A field label (FieldLabel), whatever its * or "(optional)".
Finder _label(String text) => find.byWidgetPredicate(
  (widget) => widget is FieldLabel && widget.text == text,
);

Widget _app(Widget child) => MaterialApp(
  theme: simplekTheme(Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('change 2: code fields in capitals', () {
    test('PAN is upper case, letters and digits only, 10 characters', () {
      expect(
        _type(upperCaseCodeFormatters(10), 'abcde1234f').text,
        'ABCDE1234F',
      );
      expect(
        _type(upperCaseCodeFormatters(10), 'abcde1234fgh').text,
        'ABCDE1234F',
      );
      expect(
        _type(upperCaseCodeFormatters(10), 'ab cd-e1234f').text,
        'ABCDE1234F',
      );
    });

    test('IFSC stops at 11 and GSTIN at 15 characters', () {
      expect(
        _type(upperCaseCodeFormatters(11), 'hdfc00008391').text,
        'HDFC0000839',
      );
      expect(
        _type(upperCaseCodeFormatters(15), '29abcde1234f1z5xx').text,
        '29ABCDE1234F1Z5',
      );
    });

    testWidgets('typing into a PAN field shows capitals', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          TextField(
            controller: controller,
            inputFormatters: upperCaseCodeFormatters(10),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'abcde1234f!@#');
      expect(controller.text, 'ABCDE1234F');
    });
  });

  group('change 4: GSTIN checksum and state', () {
    test('a GSTIN needs the pattern and its check digit', () {
      final good = _gstin('29ABCDE1234F1Z');
      expect(isValidGstin(good), isTrue);
      expect(gstinError(good), isNull);
      final wrongCheck = good.substring(0, 14) + (good[14] == 'A' ? 'B' : 'A');
      expect(isValidGstin(wrongCheck), isFalse);
      expect(gstinError(wrongCheck), contains('check digit'));
      expect(gstinError('29ABCDE'), 'A GSTIN has 15 characters');
      expect(gstinError(''), isNull);
      expect(gstinError('', required: true), 'Enter the GSTIN');
    });

    test('known real-format GSTINs pass the checksum', () {
      // Published sample GSTINs with valid check digits.
      expect(isValidGstin('27AAPFU0939F1ZV'), isTrue);
      expect(isValidGstin('29AAGCB7383J1Z4'), isTrue);
    });

    test('the first two digits give the state', () {
      expect(stateFromGstin('29ABCDE1234F1Z5')?.name, 'Karnataka');
      expect(stateFromGstin('32ABCDE1234F1Z5')?.name, 'Kerala');
      expect(stateFromGstin('37ABCDE1234F1Z5')?.name, 'Andhra Pradesh');
      expect(stateFromGstin('38ABCDE1234F1Z5')?.name, 'Ladakh');
      expect(
        stateFromGstin('25ABCDE1234F1Z5')?.name,
        'Dadra and Nagar Haveli and Daman and Diu',
      );
      expect(stateFromGstin('99ABCDE1234F1Z5'), isNull);
      expect(stateWithCode('Kerala'), 'Kerala (32)');
    });

    test('CGST/SGST v IGST compares state codes, not typed names', () {
      expect(sameGstState('Karnataka', 'KARNATAKA'), isTrue);
      expect(sameGstState('Jammu And Kashmir', 'Jammu and Kashmir'), isTrue);
      expect(
        sameGstState(
          'The Dadra And Nagar Haveli And Daman And Diu',
          'Dadra and Nagar Haveli and Daman and Diu',
        ),
        isTrue,
      );
      expect(sameGstState('Karnataka', 'Kerala'), isFalse);
    });

    test('the lookup status is shown as given, never assumed Active', () {
      expect(gstinStatusMessage('Cancelled'), 'GSTIN found. Status: Cancelled');
      expect(gstinStatusMessage(null), isNot(contains('Active')));
      expect(gstinStatusMessage(''), contains('did not return a status'));
    });
  });

  group('change 6: place of supply on a new document', () {
    test('customer GSTIN first, then saved state, then business state', () {
      expect(
        placeOfSupplyFor(
          customerGstin: _gstin('32ABCDE1234F1Z'),
          customerState: 'Karnataka',
          businessState: 'Karnataka',
        ),
        'Kerala',
      );
      expect(
        placeOfSupplyFor(
          customerGstin: '',
          customerState: 'Goa',
          businessState: 'Karnataka',
        ),
        'Goa',
      );
      expect(
        placeOfSupplyFor(
          customerGstin: '',
          customerState: '',
          businessState: 'Karnataka',
        ),
        'Karnataka',
      );
    });
  });

  group('change 3: state picker', () {
    testWidgets('empty: the label shows once and never over the hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(SearchableStateField(label: 'Business state', onChanged: (_) {})),
      );
      expect(find.text('Business state'), findsOneWidget);
      expect(find.text('Select state'), findsOneWidget);
      final label = tester.getRect(find.text('Business state'));
      final hint = tester.getRect(find.text('Select state'));
      expect(label.overlaps(hint), isFalse);
      expect(label.bottom, lessThanOrEqualTo(hint.top));
    });

    testWidgets('filled: the state shows inside, the label above', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: simplekTheme(brightness),
            home: Scaffold(
              body: SearchableStateField(
                label: 'Place of supply',
                value: 'Kerala',
                onChanged: (_) {},
              ),
            ),
          ),
        );
        expect(find.text('Select state'), findsNothing);
        final label = tester.getRect(find.text('Place of supply'));
        final value = tester.getRect(find.text('Kerala'));
        expect(label.overlaps(value), isFalse);
      }
    });

    testWidgets('read-only from the GSTIN', (tester) async {
      await tester.pumpWidget(
        _app(
          const SearchableStateField(
            label: 'State',
            value: 'Karnataka',
            readOnly: true,
            helperText: 'From your GSTIN',
          ),
        ),
      );
      await tester.tap(find.text('Karnataka'));
      await tester.pumpAndSettle();
      expect(find.text('Select State / Union Territory'), findsNothing);
      expect(find.text('From your GSTIN'), findsOneWidget);
    });
  });

  group('change 1: Yes / No choice', () {
    testWidgets('nothing chosen at first; continuing shows the error', (
      tester,
    ) async {
      final formKey = GlobalKey<FormState>();
      bool? chosen;
      await tester.pumpWidget(
        _app(
          Form(
            key: formKey,
            child: YesNoFormField(
              yesLabel: 'Yes, registered',
              noLabel: 'No, not registered',
              onChanged: (value) => chosen = value,
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.check), findsNothing);
      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Select Yes or No'), findsOneWidget);
      await tester.tap(find.text('Yes, registered'));
      await tester.pump();
      expect(chosen, isTrue);
      expect(formKey.currentState!.validate(), isTrue);
      await tester.pump();
      expect(find.text('Select Yes or No'), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('the two buttons sit together at 1920 px', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          FormWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Is your business registered under GST?'),
                YesNoFormField(onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      final question = tester.getRect(
        find.text('Is your business registered under GST?'),
      );
      final no = tester.getRect(find.text('No'));
      expect(no.right - question.left, lessThan(640));
      expect(no.top - question.bottom, lessThan(40));
    });
  });

  group('change 6: the business GST rule in the customer form', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => BusinessSettings.isGstRegistered.value = false);

    Future<void> openForm(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: simplekTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const CustomerFormDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('not registered: straight to name, no GST, no state', (
      tester,
    ) async {
      BusinessSettings.isGstRegistered.value = false;
      await openForm(tester);
      expect(_label('Customer name'), findsOneWidget);
      for (final label in [
        'Is the customer registered for GST?',
        'GSTIN',
        'State',
        'Verify',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
        expect(_label(label), findsNothing, reason: label);
      }
      expect(find.textContaining('GST'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('registered: Yes/No with the other fields already shown', (
      tester,
    ) async {
      BusinessSettings.isGstRegistered.value = true;
      await openForm(tester);
      expect(_label('Is the customer registered for GST?'), findsOneWidget);
      expect(_label('Customer name'), findsOneWidget);
      expect(_label('Mobile'), findsOneWidget);
      expect(_label('GSTIN'), findsNothing);
      expect(_label('State'), findsNothing);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(_label('GSTIN'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(_label('State'), findsNothing);
    });

    testWidgets('the dialog scrolls; buttons stay below at 360x640', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      BusinessSettings.isGstRegistered.value = true;
      await openForm(tester);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final save = tester.getRect(find.text('Save customer'));
      expect(save.bottom, lessThanOrEqualTo(640));
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });

  group('change 6: invoice and quotation screens', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      BusinessSettings.profile.value = {'businessState': 'Karnataka'};
    });
    tearDown(() => BusinessSettings.isGstRegistered.value = false);

    for (final quotation in [false, true]) {
      final name = quotation ? 'quotation' : 'invoice';
      testWidgets(
        'not registered: no GST, GSTIN, HSN or place of supply on a new $name',
        (tester) async {
          BusinessSettings.isGstRegistered.value = false;
          await tester.pumpWidget(
            MaterialApp(
              theme: simplekTheme(Brightness.light),
              home: quotation
                  ? const QuotationBuilderPage()
                  : const InvoiceBuilderPage(),
            ),
          );
          await tester.pumpAndSettle();
          for (final label in [
            'Place of supply',
            'Customer GSTIN',
            'GST rate (%)',
            'CGST',
            'SGST',
            'IGST',
            'HSN',
            'TAX INVOICE',
          ]) {
            expect(find.text(label), findsNothing, reason: label);
            expect(_label(label), findsNothing, reason: label);
          }
          await tester.scrollUntilVisible(
            _label('Description'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(_label('Description'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('registered: place of supply on a new $name', (tester) async {
        BusinessSettings.isGstRegistered.value = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: simplekTheme(Brightness.light),
            home: quotation
                ? const QuotationBuilderPage()
                : const InvoiceBuilderPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(_label('Place of supply'), findsOneWidget);
        expect(find.text('Karnataka'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('change 10: compact PDF', () {
    const profile = <String, String>{
      'name': 'Malnad Kitchen',
      'gstin': '29EMLPS9051L1Z1',
      'businessState': 'Karnataka',
      'addressLine1': 'Ratnamma Madhava Rao Road',
      'addressLine2': 'Durgigudi',
      'landmark': 'Opp Sarji Mother and Child Care',
      'city': 'Shivamogga',
      'district': 'Shivamogga',
      'pincode': '577201',
      'email': 'orders@example.com',
      'phone': '9036426630',
      'bankName': 'HDFC Bank',
      'bankBranch': 'Shivamogga',
      'bankAccount': '50200124616049',
      'ifsc': 'HDFC0000839',
      'upiId': '9036426630@ybl',
      'invoiceTheme': 'white-blue',
      'logoPath': 'assets/branding/simplek-app-icon-hd.png',
    };

    PdfDocumentData invoice(int count, {String description = ''}) {
      final items = [
        for (var i = 1; i <= count; i++)
          PdfLineItem(
            description: 'Catering item $i',
            hsn: '996331',
            quantity: 2,
            unit: 'NOS',
            rate: 333.33,
            gstRate: 5,
            taxable: 666.66,
            tax: 33.33,
          ),
      ];
      final exact = items.fold<double>(0, (sum, item) => sum + item.amount);
      return PdfDocumentData(
        kind: PdfDocumentKind.invoice,
        number: 'INV/2026-27/28',
        date: DateTime(2026, 11, 25),
        secondDate: DateTime(2026, 12, 2),
        placeOfSupply: 'Karnataka',
        customerName: 'Ravi Kumar',
        customerAddress: '12 Market Road, Shivamogga, Karnataka 577201',
        customerPhone: '9845333655',
        items: items,
        total: roundToRupee(exact),
        terms:
            '1. Goods once sold will not be taken back.\n'
            '2. Payment within 7 days.\n'
            '3. Interest at 18% after the due date.\n'
            '4. Subject to Shivamogga jurisdiction.',
        description: description,
        gstDocument: true,
      );
    }

    int pages(Uint8List pdf) => RegExp(
      r'/Type\s*/Page[^s]',
    ).allMatches(String.fromCharCodes(pdf)).length;

    final description =
        ('Digital signature, valid 2 years, for Mr. Ravi Kumar. ' * 6)
            .substring(0, 300);

    test(
      '8 items, CGST/SGST, bank + UPI and 300 characters fit one page',
      () async {
        expect(description.length, 300);
        final pdf = await buildDocumentPdf(
          invoice(8, description: description),
          profile,
        );
        if (Platform.environment['SIMPLEK_PDF_QA'] == '1') {
          await Directory('tmp/pdfs-new').create(recursive: true);
          await File('tmp/pdfs-new/cr25-8-items.pdf').writeAsBytes(pdf);
        }
        expect(pages(pdf), 1);
      },
    );

    test('12 items run onto two pages', () async {
      final pdf = await buildDocumentPdf(
        invoice(12, description: description),
        profile,
      );
      expect(pages(pdf), 2);
    });
  });

  group('change 11: address', () {
    test('one comma-separated line, district only when it differs', () {
      expect(
        composeBusinessAddress(
          line1: 'Malnad Kitchen, Ratnamma Madhava Rao Road',
          landmark: 'Opp Sarji Mother and Child Care',
          line2: 'Durgigudi, Tilak Nagara',
          city: 'Shivamogga',
          district: 'Shivamogga',
          state: 'Karnataka',
          pincode: '577201',
        ),
        'Malnad Kitchen, Ratnamma Madhava Rao Road, Durgigudi, Tilak Nagara, '
        'Opp Sarji Mother and Child Care, Shivamogga, Karnataka 577201',
      );
      expect(
        composeBusinessAddress(
          line1: '12 Main Road',
          city: 'Sagar',
          district: 'Shivamogga',
          state: 'Karnataka',
          pincode: '577401',
        ),
        '12 Main Road, Sagar, Shivamogga, Karnataka 577401',
      );
    });

    test('states load from the bundled asset', () async {
      await IndiaDistricts.load(
        () => rootBundle.loadString(IndiaDistricts.assetPath),
      );
      expect(indiaStates, hasLength(36));
      expect(
        indiaStates.where((state) => state.isUnionTerritory),
        hasLength(8),
      );
      expect(IndiaDistricts.isLoaded, isTrue);
    });

    test(
      'districts follow the chosen state',
      () async {
        await IndiaDistricts.load(
          () => rootBundle.loadString(IndiaDistricts.assetPath),
        );
        expect(IndiaDistricts.of('Karnataka'), contains('Shivamogga'));
        expect(IndiaDistricts.of('Kerala'), isNot(contains('Shivamogga')));
        expect(IndiaDistricts.match('Karnataka', 'SHIVAMOGGA'), 'Shivamogga');
      },
      skip: _districtsImported
          ? false
          : 'LGD district list not imported yet (tool/import_lgd.dart)',
    );
  });
}
