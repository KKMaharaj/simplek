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
const _out = 'docs/screenshots/2026-11-25';
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
