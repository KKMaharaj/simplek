// UI-25 section 5: no overlapping or overflowing text. Pumps every screen
// that works without a login at phone, tablet and web widths, at text scale
// 1.0 and 1.3, in light and dark, and fails on any RenderFlex overflow or
// other layout error. Lists that need the server (invoices, customers,
// items, reports) are covered by the hand test with real data.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

const _sizes = <Size>[
  Size(320, 640),
  Size(360, 740),
  Size(375, 812),
  Size(390, 844),
  Size(414, 896),
  Size(768, 1024),
  Size(1024, 768),
  Size(1280, 800),
  Size(1366, 768),
  Size(1440, 900),
  Size(1920, 1080),
];

ModernOverview _home() => ModernOverview(
  businessName: 'Valyou Products Private Limited, Shivamogga',
  sales: '₹12,34,56,789.00',
  outstanding: '₹1,23,45,678.90',
  invoiceCount: '1234',
  customerCount: '567',
  collected: '₹98,76,543.21',
  unpaidCount: 321,
  partlyPaidCount: 12,
  loading: false,
  error: null,
  recent: const [
    {
      'id': '1',
      'number': 'INV/2026-27/1024',
      'customer': 'Sri Venkateshwara Engineering and Fabrication Works',
      'amount': '₹12,34,567.89',
      'status': 'partial',
      'date': '19 Nov 2026',
    },
    {
      'id': '2',
      'number': 'INV/2026-27/23',
      'customer': 'Kiran N P & Associates',
      'amount': '₹3,276.00',
      'status': 'paid',
      'date': '18 Nov 2026',
    },
  ],
  onNewInvoice: () {},
  onNewQuotation: () {},
  onCustomer: () {},
  onProduct: () {},
  onPayment: () {},
  onSearch: () {},
  onReports: () {},
  onInvoices: () {},
  onRefresh: () async {},
);

final _screens = <String, Widget Function()>{
  'home': () => Scaffold(body: SafeArea(child: _home())),
  'login': () => const LoginPage(),
  'onboarding': () => const BusinessOnboardingPage(
    ownerName: 'Akshay',
    businessName: 'Malnad Kitchen',
    mobile: '9036426630',
  ),
  'new invoice': () => const InvoiceBuilderPage(),
  'new quotation': () => const QuotationBuilderPage(),
  'settings': () => const BusinessSettingsPage(),
  'customer form': () =>
      const Scaffold(body: CustomerFormDialog(asSheet: true)),
  'privacy update': () => PrivacyUpdatePage(onAccepted: () {}),
  'delete account': () => const DeleteAccountPage(),
  'sign-up': () => const SignupPage(),
  'paused account': () => const SuspendedPage(),
  'new password': () => ForcedPasswordPage(onDone: () async {}),
  'new password after reset': () => ForcedPasswordPage(
    reason: NewPasswordReason.recovery,
    onDone: () async {},
  ),
  'change password': () =>
      ForcedPasswordPage(reason: NewPasswordReason.change, onDone: () async {}),
  'forgot password': () => const ResetPasswordPage(
    initialEmail: 'valyou.products.shivamogga@example.in',
  ),
};

/// The app's real fonts, so text is measured as it is in the app (the
/// default test font draws every letter as a wide square).
Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)
      ..addFont(
        Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
      );
    await loader.load();
  }

  await load('Inter', 'assets/fonts/Inter.ttf');
  await load('Fraunces', 'assets/fonts/Fraunces.ttf');
  // The Material icon font, if this Flutter install has it. The file name's
  // case differs between installs (GitHub's Linux runner is case-sensitive),
  // so match it case-insensitively. Without it the test font draws each icon
  // as a square of the same size, which measures the same.
  final icons = _materialIconFont();
  if (icons != null) await load('MaterialIcons', icons);
}

String? _materialIconFont() {
  // flutter_tester lives under <sdk>/bin/cache/artifacts/engine/...
  var dir = File(Platform.resolvedExecutable).parent;
  while (true) {
    final fonts = Directory('${dir.path}/artifacts/material_fonts');
    if (fonts.existsSync()) {
      for (final file in fonts.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last.toLowerCase();
        if (name == 'materialicons-regular.otf') return file.path;
      }
      return null;
    }
    if (dir.parent.path == dir.path) return null;
    dir = dir.parent;
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BusinessSettings.profile.value = {
      'name': 'Malnad Kitchen',
      'businessState': 'Karnataka',
      'gstin': '29AAGCB7383J1Z4',
      'invoicePrefix': 'INV',
      'quotationPrefix': 'QTN',
    };
  });
  tearDown(() => BusinessSettings.isGstRegistered.value = false);

  for (final gst in [true, false]) {
    for (final entry in _screens.entries) {
      testWidgets(
        '${entry.key} (${gst ? 'GST' : 'no GST'}) fits every size, scale and theme',
        (tester) async {
          BusinessSettings.isGstRegistered.value = gst;
          addTearDown(tester.view.reset);
          final failures = <String>[];
          for (final size in _sizes) {
            for (final scale in [1.0, 1.3]) {
              for (final brightness in Brightness.values) {
                tester.view.physicalSize = size;
                tester.view.devicePixelRatio = 1;
                await tester.pumpWidget(
                  MaterialApp(
                    key: ValueKey('$size$scale$brightness'),
                    theme: simplekTheme(brightness),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: entry.value(),
                  ),
                );
                await tester.pump(const Duration(milliseconds: 50));
                final error = tester.takeException();
                if (error != null) {
                  failures.add(
                    '${size.width.toInt()}x${size.height.toInt()} '
                    '@$scale ${brightness.name}: $error',
                  );
                }
              }
            }
          }
          expect(failures, isEmpty, reason: failures.join('\n'));
        },
      );
    }
  }

  group('labels never share a position with the hint', () {
    Future<void> check(
      WidgetTester tester,
      Widget field,
      String label,
      String? hint,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: simplekTheme(Brightness.light),
          home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: field),
          ),
        ),
      );
      final labels = find.byWidgetPredicate(
        (widget) => widget is FieldLabel && widget.text == label,
      );
      expect(labels, findsOneWidget);
      if (hint != null) {
        final hintRect = tester.getRect(find.text(hint));
        expect(tester.getRect(labels).overlaps(hintRect), isFalse);
      }
    }

    testWidgets('text field, empty and filled', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      Widget field() => LabeledField(
        label: 'PAN',
        child: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. ABCDE1234F'),
        ),
      );
      await check(tester, field(), 'PAN', 'e.g. ABCDE1234F');
      controller.text = 'ABCDE1234F';
      await check(tester, field(), 'PAN', null);
      expect(find.text('ABCDE1234F'), findsOneWidget);
    });

    testWidgets('state and district pickers, empty and filled', (tester) async {
      await check(
        tester,
        SearchableStateField(label: 'State', onChanged: (_) {}),
        'State',
        'Select state',
      );
      await check(
        tester,
        SearchableStateField(
          label: 'State',
          value: 'Kerala',
          onChanged: (_) {},
        ),
        'State',
        null,
      );
      await check(
        tester,
        SearchablePickerField(
          label: 'District',
          options: const ['Shivamogga'],
          hint: 'Select district',
          onChanged: (_) {},
        ),
        'District',
        'Select district',
      );
    });

    testWidgets('Yes / No choice', (tester) async {
      await check(
        tester,
        Column(
          children: [
            const FieldLabel('Is your business registered under GST?'),
            YesNoFormField(onChanged: (_) {}),
          ],
        ),
        'Is your business registered under GST?',
        null,
      );
    });
  });

  test('no floating labels are left in the app', () {
    // UI-25 done checklist: `grep labelText lib/` finds none in screens.
    // (labelTextStyle in the theme is the navigation bar's text style.)
    final hits = <String>[];
    for (final file in [
      'lib/main.dart',
      'lib/modern_ui.dart',
      'lib/business_forms.dart',
      'lib/customer_form.dart',
      'lib/record_picker.dart',
      'lib/document_parts.dart',
      'lib/form_fields.dart',
      'lib/ui_kit.dart',
    ]) {
      final lines = File(file).readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        if (RegExp(r'\blabelText\s*:').hasMatch(line)) {
          hits.add('$file:${index + 1}');
        }
      }
    }
    expect(hits, isEmpty);
  });
}
