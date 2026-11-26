// Renders the screens changed by a change request to PNG files for the
// owner's review (BUILD-STANDARDS 16: screenshots at 1366 and 390 px).
// Skipped unless SIMPLEK_SCREENSHOTS=1:
//   SIMPLEK_SCREENSHOTS=1 flutter test test/screenshots_test.dart
// Writes docs/screenshots/2026-11-25/*.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

final _enabled = Platform.environment['SIMPLEK_SCREENSHOTS'] == '1';
final _out = Platform.environment['SIMPLEK_SCREENSHOT_DIR'] ?? 'docs/screenshots/2026-11-25';
final _boundary = GlobalKey();

Future<void> _loadFonts() async {
  // flutter_tester lives under <sdk>/bin/cache/artifacts/engine/...
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/artifacts/material_fonts').existsSync()) {
    dir = dir.parent;
  }
  final fonts = '${dir.path}/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File('$fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  // The app's own fonts (pubspec fonts are not loaded in tests by default).
  for (final name in ['Inter', 'Fraunces']) {
    final loader = FontLoader(name)
      ..addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$name.ttf').readAsBytesSync()),
        ),
      );
    await loader.load();
  }
  await family('MaterialIcons', ['materialicons-regular.otf']);
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget home, {
  required Size size,
  Future<void> Function(WidgetTester tester)? before,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: simplekTheme(Brightness.light),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (before != null) await before(tester);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget _dialogHost() => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const CustomerFormDialog(),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const phone = Size(390, 1500);
  const desktop = Size(1440, 1500);

  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BusinessSettings.profile.value = {
      'name': 'Malnad Kitchen',
      'businessState': 'Karnataka',
      'address': 'Ratnamma Madhava Rao Road, Durgigudi, Shivamogga',
      'invoicePrefix': 'INV',
      'quotationPrefix': 'QTN',
    };
  });
  tearDown(() => BusinessSettings.isGstRegistered.value = false);

  for (final (label, size) in [('phone', phone), ('web', desktop)]) {
    testWidgets('home ($label)', skip: !_enabled, (tester) async {
      await _shot(
        tester,
        'home-$label',
        Scaffold(
          body: SafeArea(
            child: ModernOverview(
              businessName: 'Malabar Traders',
              sales: '₹27,550.00',
              outstanding: '₹19,800.00',
              invoiceCount: '5',
              customerCount: '12',
              collected: '₹7,750.00',
              unpaidCount: 3,
              partlyPaidCount: 1,
              loading: false,
              error: null,
              recent: const [
                {'id': '1', 'number': 'INV/2026-27/24', 'customer': 'Principal JNNCE', 'amount': '₹10,600.21', 'status': 'sent', 'date': '19 Nov 2026'},
                {'id': '2', 'number': 'INV/2026-27/23', 'customer': 'Kiran N P & Associates', 'amount': '₹3,276.00', 'status': 'paid', 'date': '18 Nov 2026'},
                {'id': '3', 'number': 'INV/2026-27/22', 'customer': 'Pearlite Liners Pvt Ltd', 'amount': '₹2,205.00', 'status': 'partial', 'date': '14 Nov 2026'},
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
            ),
          ),
        ),
        size: Size(size.width, label == 'phone' ? 844 : 960),
      );
    });

    testWidgets('login ($label)', skip: !_enabled, (tester) async {
      await _shot(
        tester,
        'login-$label',
        const LoginPage(),
        size: Size(size.width, label == 'phone' ? 844 : 960),
      );
    });

    testWidgets(
      'onboarding, GST question unanswered ($label)',
      skip: !_enabled,
      (tester) async {
        await _shot(
          tester,
          'onboarding-start-$label',
          const BusinessOnboardingPage(
            ownerName: 'Akshay',
            businessName: 'Malnad Kitchen',
            mobile: '9036426630',
          ),
          size: size,
        );
      },
    );

    testWidgets('onboarding, registered with GSTIN ($label)', skip: !_enabled, (
      tester,
    ) async {
      await _shot(
        tester,
        'onboarding-registered-$label',
        const BusinessOnboardingPage(
          ownerName: 'Akshay',
          businessName: 'Malnad Kitchen',
          mobile: '9036426630',
        ),
        size: Size(size.width, 2200),
        before: (tester) async {
          await tester.tap(find.text('Yes, registered'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextFormField).at(2),
            '29aagcb7383j1z4',
          );
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('onboarding, not registered ($label)', skip: !_enabled, (
      tester,
    ) async {
      await _shot(
        tester,
        'onboarding-not-registered-$label',
        const BusinessOnboardingPage(
          ownerName: 'Akshay',
          businessName: 'Malnad Kitchen',
          mobile: '9036426630',
        ),
        size: Size(size.width, 2000),
        before: (tester) async {
          await tester.tap(find.text('No, not registered'));
          await tester.pumpAndSettle();
        },
      );
    });

    for (final registered in [false, true]) {
      final tag = registered ? 'gst' : 'no-gst';
      testWidgets('new customer, $tag ($label)', skip: !_enabled, (
        tester,
      ) async {
        BusinessSettings.isGstRegistered.value = registered;
        await _shot(
          tester,
          'new-customer-$tag-$label',
          _dialogHost(),
          size: Size(size.width, 900),
          before: (tester) async {
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            if (registered) {
              await tester.tap(find.text('Yes'));
              await tester.pumpAndSettle();
            }
          },
        );
      });

      testWidgets('new invoice, $tag ($label)', skip: !_enabled, (
        tester,
      ) async {
        BusinessSettings.isGstRegistered.value = registered;
        await _shot(
          tester,
          'new-invoice-$tag-$label',
          const InvoiceBuilderPage(),
          size: size,
        );
      });
    }

    testWidgets('settings, old address to complete ($label)', skip: !_enabled, (
      tester,
    ) async {
      BusinessSettings.isGstRegistered.value = true;
      BusinessSettings.profile.value = {
        ...BusinessSettings.profile.value,
        'gstin': '29AAGCB7383J1Z4',
        'pan': 'AAGCB7383J',
      };
      await _shot(
        tester,
        'settings-$label',
        const BusinessSettingsPage(),
        size: Size(size.width, 3000),
      );
    });
  }
}
