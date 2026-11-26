import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

Widget overview() => ModernOverview(
  sales: '₹27,550.00',
  outstanding: '₹19,800.00',
  invoiceCount: '5',
  customerCount: '12',
  loading: false,
  error: null,
  recent: const [
    {
      'number': 'INV/2026-27/0017',
      'customer': 'Sample Catering Co.',
      'amount': '₹2,441.25',
      'status': 'unpaid',
      'date': '16 Sep 2026',
    },
  ],
  onNewInvoice: () {},
  onNewQuotation: () {},
  onCustomer: () {},
  onProduct: () {},
  onInvoices: () {},
  onRefresh: () async {},
);

void main() {
  setUpAll(() async {
    if (Platform.environment['SIMPLEK_UI_QA'] == '1') {
      // Local visual QA uses real glyphs rather than Flutter's Ahem test font.
      for (final font in {
        'Roboto': 'C:/Windows/Fonts/segoeui.ttf',
        'MaterialIcons':
            'C:/Users/HP/development/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      }.entries) {
        final loader = FontLoader(font.key);
        loader.addFont(
          Future.value(
            ByteData.sublistView(await File(font.value).readAsBytes()),
          ),
        );
        await loader.load();
      }
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesignSettings.modern.value = true;
  });
  tearDown(() {
    DesignSettings.modern.value = true;
    DesignSettings.destination.value = 0;
  });

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0]) {
      testWidgets('overview ${brightness.name} at $width', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: simplekTheme(brightness),
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('Simplek'),
                  actions: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.search),
                    ),
                  ],
                ),
                body: overview(),
                bottomNavigationBar: NavigationBar(
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: 'Invoices',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.people_outline),
                      label: 'Customers',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      label: 'Products',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: 'More',
                    ),
                  ],
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Simplek'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (Platform.environment['SIMPLEK_UI_QA'] == '1' && width == 390) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('tmp/ui').create(recursive: true);
            await File(
              'tmp/ui/modern-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }

  testWidgets('theme switch changes the app theme in one tap and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'business_invoice_terms': 'Keep my terms',
    });
    await tester.pumpWidget(
      MyApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: BusinessSettings.themeMode,
              builder: (context, mode, _) => ThemeModeToggle(
                mode: mode,
                onChanged: BusinessSettings.setThemeMode,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(BusinessSettings.themeMode.value, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.text('Dark'))).brightness,
      Brightness.dark,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('business_invoice_terms'), 'Keep my terms');
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(BusinessSettings.themeMode.value, ThemeMode.light);
    await BusinessSettings.setThemeMode(ThemeMode.system);
  });

  testWidgets('save and share actions fit at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: simplekTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1000),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: DocumentShareBar(
              onWhatsApp: () {},
              onEmail: () {},
              onShare: () {},
            ),
            bottomNavigationBar: DocumentSaveBar(
              saving: false,
              onClose: () {},
              onNext: () => saves++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Save & Next'));
    expect(saves, 1);
    final whatsapp = tester.widget<Text>(find.text('WhatsApp'));
    expect(whatsapp.maxLines, 1);
    expect(whatsapp.softWrap, false);
  });

  testWidgets('state picker filters and selects full names', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: simplekTheme(Brightness.light),
        home: Scaffold(
          body: SearchableStateField(onChanged: (value) => selected = value),
        ),
      ),
    );
    await tester.tap(find.text('Select state'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Telan');
    await tester.pumpAndSettle();
    expect(find.text('Dadra and Nagar Haveli and Daman and Diu'), findsNothing);
    await tester.tap(find.text('Telangana'));
    await tester.pumpAndSettle();
    expect(selected, 'Telangana');
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsible terms preserve edits', (tester) async {
    final controller = TextEditingController(text: 'Original terms');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EditableTerms(controller: controller)),
      ),
    );
    await tester.tap(find.text('Terms and conditions'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Custom agreement');
    await tester.tap(find.text('Terms and conditions'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Custom agreement');
  });
}
