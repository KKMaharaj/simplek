// CR-25B B1: delete with a GST warning, the edit warning on older invoices,
// and the "old invoices show the new details" note.
// (The server side is tested in supabase/tests/20261127_cr25b_b1_regressions.sql.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/business_access.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

/// Opens [show] from a button and returns what the dialog resolved to.
Future<bool?> _open(
  WidgetTester tester,
  Future<bool> Function(BuildContext) show, {
  String? tap,
}) async {
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: simplekTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  if (tap != null) {
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
  }
  return result;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    BusinessSettings.isGstRegistered.value = false;
    BusinessAccess.viewing.value = null;
  });

  group('delete warning', () {
    testWidgets('GST business sees the GSTR-1 line', (tester) async {
      BusinessSettings.isGstRegistered.value = true;
      await _open(
        tester,
        (context) => confirmDeleteInvoice(context, 'INV/2026-27/24'),
      );
      expect(find.text('Delete invoice INV/2026-27/24?'), findsOneWidget);
      expect(
        find.text('It will be removed from your invoices, totals and reports.'),
        findsOneWidget,
      );
      expect(find.text(gstDeleteWarning), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a business without GST sees no GST line', (tester) async {
      await _open(
        tester,
        (context) => confirmDeleteInvoice(context, 'INV/2026-27/24'),
      );
      expect(find.text('Delete invoice INV/2026-27/24?'), findsOneWidget);
      expect(find.text(gstDeleteWarning), findsNothing);
    });

    testWidgets('Delete confirms, Cancel does not', (tester) async {
      expect(
        await _open(
          tester,
          (context) => confirmDeleteInvoice(context, 'INV/1'),
          tap: 'Delete',
        ),
        isTrue,
      );
      expect(
        await _open(
          tester,
          (context) => confirmDeleteInvoice(context, 'INV/1'),
          tap: 'Cancel',
        ),
        isFalse,
      );
    });

    testWidgets('view-only access cannot delete', (tester) async {
      BusinessAccess.viewing.value = (ownerId: 'owner', name: 'Shared');
      final deleted = await _open(
        tester,
        (context) =>
            deleteInvoiceWithUndo(context, invoiceId: 'x', number: 'INV/1'),
      );
      expect(deleted, isFalse);
      expect(find.text('Delete invoice INV/1?'), findsNothing);
      expect(find.text(BusinessAccess.readOnlyMessage), findsOneWidget);
    });
  });

  group('edit warning', () {
    final today = DateTime(2026, 11, 26, 15);
    Map<String, dynamic> dated(String date) => {
      'invoice_number': 'INV/2026-27/20',
      'invoice_date': date,
    };

    test('only GST businesses, only invoices dated before today', () {
      BusinessSettings.isGstRegistered.value = true;
      expect(editNeedsGstWarning(dated('2026-11-25'), today: today), isTrue);
      expect(editNeedsGstWarning(dated('2026-11-26'), today: today), isFalse);
      expect(editNeedsGstWarning(dated('2026-11-27'), today: today), isFalse);
      BusinessSettings.isGstRegistered.value = false;
      expect(editNeedsGstWarning(dated('2026-11-25'), today: today), isFalse);
    });

    testWidgets('asks once with "Edit anyway"', (tester) async {
      BusinessSettings.isGstRegistered.value = true;
      final result = await _open(
        tester,
        (context) =>
            confirmEditInvoice(context, dated('2026-11-01'), today: today),
        tap: 'Edit anyway',
      );
      expect(result, isTrue);
    });

    testWidgets('no dialog for today\'s invoice', (tester) async {
      BusinessSettings.isGstRegistered.value = true;
      final result = await _open(
        tester,
        (context) =>
            confirmEditInvoice(context, dated('2026-11-26'), today: today),
      );
      expect(result, isTrue);
      expect(find.text(gstEditWarning), findsNothing);
    });
  });

  group('old invoices note', () {
    const before = {
      'name': 'Malnad Kitchen',
      'gstin': '29AAGCB7383J1Z4',
      'upiId': 'malnad@upi',
      'ownerName': 'Akshay',
      'phone': '9036426630',
    };

    test('name, address, GSTIN, bank and UPI changes need the note', () {
      for (final key in ['name', 'gstin', 'upiId', 'bankAccount', 'pincode']) {
        expect(
          profileChangeShowsOnOldInvoices(before, {...before, key: 'changed'}),
          isTrue,
          reason: key,
        );
      }
    });

    test('other changes, and a first save, do not', () {
      expect(
        profileChangeShowsOnOldInvoices(before, {
          ...before,
          'ownerName': 'Someone else',
          'phone': '9999999999',
        }),
        isFalse,
      );
      expect(profileChangeShowsOnOldInvoices(before, before), isFalse);
      expect(profileChangeShowsOnOldInvoices({}, before), isFalse);
    });

    test('a product\'s HSN/SAC or GST rate', () {
      const product = {'hsn_sac_code': '0902', 'gst_rate': 5, 'name': 'Tea'};
      expect(
        productChangeShowsOnOldInvoices(product, {
          ...product,
          'gst_rate': 5.0,
          'name': 'Green tea',
        }),
        isFalse,
      );
      expect(
        productChangeShowsOnOldInvoices(product, {...product, 'gst_rate': 12}),
        isTrue,
      );
      expect(
        productChangeShowsOnOldInvoices(product, {
          ...product,
          'hsn_sac_code': '2101',
        }),
        isTrue,
      );
      expect(productChangeShowsOnOldInvoices(null, product), isFalse);
    });

    test('the GST version adds the GST returns clause', () {
      expect(
        oldInvoicesNote(gst: false),
        'Old invoices will also show the new details when you open or share '
        'them again.',
      );
      expect(
        oldInvoicesNote(gst: true),
        endsWith("which may not match GST returns you've already filed."),
      );
    });
  });
}
