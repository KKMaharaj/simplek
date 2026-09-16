import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:simplek/document_defaults.dart';
import 'package:simplek/payment_pdf.dart';
import 'package:simplek/main.dart';

void main() {
  test('old defaults upgrade while custom terms remain unchanged', () {
    expect(
      DocumentDefaults.resolve(
        DocumentDefaults.legacyInvoice,
        isQuotation: false,
      ),
      DocumentDefaults.invoice,
    );
    expect(
      DocumentDefaults.resolve(
        DocumentDefaults.legacyQuotation,
        isQuotation: true,
      ),
      DocumentDefaults.quotation,
    );
    expect(
      DocumentDefaults.resolve(null, isQuotation: false),
      DocumentDefaults.invoice,
    );
    expect(
      DocumentDefaults.resolve('Custom payment agreement', isQuotation: true),
      'Custom payment agreement',
    );
  });

  testWidgets('theme updates immediately and selection is persisted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MyApp(home: Scaffold(body: Text('Theme test'))),
    );
    await BusinessSettings.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Theme test'))).brightness,
      Brightness.dark,
    );
    expect(
      (await SharedPreferences.getInstance()).getString('app_theme_mode'),
      'dark',
    );
    await BusinessSettings.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Theme test'))).brightness,
      Brightness.light,
    );
    await BusinessSettings.setThemeMode(ThemeMode.system);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });

  testWidgets(
    'GST popup appears over customer dialog and closes after two seconds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Customer form'),
                    content: TextButton(
                      onPressed: () =>
                          showGstinResult(dialogContext, 'GSTIN verified'),
                      child: const Text('Verify'),
                    ),
                  ),
                ),
                child: const Text('Add customer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add customer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('GSTIN verified'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pumpAndSettle();
      expect(find.text('GSTIN verified'), findsNothing);
      expect(find.text('Customer form'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('splash keeps branding but has no loading spinner', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AppLaunchSplash()));
    expect(find.text('Invoicing made easy'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(AppLaunchSplash), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
    'payment section generates with QR, caption and bundled UPI logo',
    (tester) async {
      await tester.runAsync(() async {
        expect(await buildPaymentQr({}), isNull);
        final qr = await buildPaymentQr({
          'upiId': 'example@upi',
          'name': 'Test Business',
        });
        expect(qr, isNotNull);
        final pdf = pw.Document();
        pdf.addPage(
          pw.MultiPage(
            build: (_) => [
              pw.Text('Invoice payment section preview'),
              pw.SizedBox(height: 20),
              pw.Text(DocumentDefaults.invoice),
              pw.SizedBox(height: 20),
              qr!,
              pw.SizedBox(height: 20),
              pw.Text('Quotation terms'),
              pw.Text(DocumentDefaults.quotation),
            ],
          ),
        );
        final bytes = await pdf.save();
        expect(bytes.length, greaterThan(1000));
        // Opt-in local visual QA artifact; regular tests do not write files.
        if (Platform.environment['SIMPLEK_PDF_QA'] == '1') {
          await Directory('tmp/pdfs').create(recursive: true);
          await File('tmp/pdfs/payment-qa.pdf').writeAsBytes(bytes);
        }
      });
    },
  );
}
