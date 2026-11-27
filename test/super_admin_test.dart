// Change request 26 Nov 2026, super admin panel: what every user sees (plan,
// limit notice, paused account, forced password change, notice banner).
// The admin functions and their access rules are tested on the database in
// supabase/tests/20261127_super_admin_regressions.sql.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

Widget _app(Widget child) => MaterialApp(
  theme: simplekTheme(Brightness.light),
  home: Scaffold(body: child),
);

Map<String, dynamic> _plan(
  int used, {
  int? allowed = 250,
  String period = 'lifetime',
}) => {
  'plan_code': 'free',
  'plan_name': 'Free',
  'used': used,
  'allowed': allowed,
  'limit_period': period,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    MyPlan.current.value = null;
    AccountStatus.current.value = AccountStatus.unknown;
  });

  group('plan usage', () {
    test('words and the 80% notice', () {
      expect(MyPlan.usageText(_plan(212)), '212 of 250 free invoices used');
      expect(
        MyPlan.usageText(_plan(12, period: 'monthly')),
        '12 of 250 free invoices used this month',
      );
      expect(MyPlan.usageText(_plan(640, allowed: null)), isNull);
      expect(MyPlan.nearLimit(_plan(199)), isFalse);
      expect(MyPlan.nearLimit(_plan(200)), isTrue);
      expect(MyPlan.nearLimit(_plan(240)), isTrue);
      expect(MyPlan.nearLimit(_plan(999, allowed: null)), isFalse);
    });

    testWidgets('Settings: "Your plan: Free · 212 of 250…" with Upgrade', (
      tester,
    ) async {
      MyPlan.current.value = _plan(212);
      await tester.pumpWidget(_app(const PlanCard()));
      expect(
        find.text('Your plan: Free · 212 of 250 free invoices used'),
        findsOneWidget,
      );
      expect(find.text('Upgrade'), findsOneWidget);
    });

    testWidgets('Home shows the notice only from 80%', (tester) async {
      MyPlan.current.value = _plan(100);
      await tester.pumpWidget(_app(const PlanCard(onlyWhenNear: true)));
      expect(find.textContaining('free invoices'), findsNothing);
      MyPlan.current.value = _plan(200);
      await tester.pump();
      expect(
        find.text("You've used 200 of 250 free invoices."),
        findsOneWidget,
      );
    });

    test('the server refusal is recognised', () {
      expect(
        isPlanLimitError(
          "You've used all 250 free invoices. Upgrade to keep creating invoices.",
        ),
        isTrue,
      );
      expect(isPlanLimitError('PLAN_LIMIT'), isTrue);
      expect(isPlanLimitError('Invoice not found'), isFalse);
    });
  });

  group('account status', () {
    test('read from my_account_status', () {
      const status = AccountStatus({
        'suspended': true,
        'must_change_password': true,
        'settings': {
          'notice_banner': {
            'text': 'Maintenance tonight at 11 pm',
            'colour': 'orange',
          },
          'support_contact': {
            'whatsapp': '9876543210',
            'email': 'help@example.com',
          },
        },
      });
      expect(status.suspended, isTrue);
      expect(status.mustChangePassword, isTrue);
      expect(status.banner!['text'], 'Maintenance tonight at 11 pm');
      expect(status.supportContact['whatsapp'], '9876543210');
      expect(AccountStatus.unknown.suspended, isFalse);
      expect(AccountStatus.unknown.banner, isNull);
    });

    testWidgets('the notice banner shows while there is text', (tester) async {
      await tester.pumpWidget(_app(const NoticeBanner()));
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
      AccountStatus.current.value = const AccountStatus({
        'settings': {
          'notice_banner': {'text': 'Maintenance tonight at 11 pm'},
        },
      });
      await tester.pump();
      expect(find.text('Maintenance tonight at 11 pm'), findsOneWidget);
    });

    testWidgets('a paused account sees only the paused screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: simplekTheme(Brightness.light),
          home: const SuspendedPage(),
        ),
      );
      expect(
        find.text('Your account is paused. Contact support.'),
        findsOneWidget,
      );
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('after an admin reset, a new password is required', (
      tester,
    ) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: simplekTheme(Brightness.light),
          home: ForcedPasswordPage(onDone: () async => done = true),
        ),
      );
      expect(find.text('Set a new password'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'short');
      await tester.tap(find.text('Save and continue'));
      // The rules are shown before typing; the error replaces them.
      await tester.pumpAndSettle();
      expect(
        find.text('At least 8 characters, with a letter and a number'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).first, 'longenough1');
      await tester.enterText(find.byType(TextFormField).last, 'different1');
      await tester.tap(find.text('Save and continue'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(done, isFalse);
    });
  });
}
