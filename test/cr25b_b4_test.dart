// CR-25B B4: privacy (DPDP). The server side is tested in
// supabase/tests/20261127_cr25b_b4_regressions.sql.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: simplekTheme(Brightness.light), home: home);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('consent box', () {
    testWidgets('starts unticked and must be ticked', (tester) async {
      final form = GlobalKey<FormState>();
      bool? ticked;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Form(
              key: form,
              child: ConsentField(onChanged: (value) => ticked = value),
            ),
          ),
        ),
      );
      expect(
        find.text(
          'I am 18 or older and I agree to the Privacy Notice and Terms',
        ),
        findsOneWidget,
      );
      expect(find.text('Privacy Notice'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Tick the box to create your account'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(ticked, isTrue);
      expect(form.currentState!.validate(), isTrue);
    });

    testWidgets('sign-up cannot go on without the tick', (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(const SignupPage()));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Asha Rao');
      await tester.enterText(fields.at(2), '9876543210');
      await tester.enterText(fields.at(3), 'asha@example.com');
      await tester.tap(find.text('Send verification email'));
      await tester.pump();
      expect(find.text('Tick the box to create your account'), findsOneWidget);
    });

    test('the tick is saved with the new account', () {
      final ticked = DateTime.utc(2026, 11, 27, 10, 30);
      expect(PrivacyRecords.signupConsent(ticked), {
        'privacy_consent_version': PrivacyInfo.noticeVersion,
        'privacy_consent_at': '2026-11-27T10:30:00.000Z',
      });
    });
  });

  testWidgets('the updated-notice screen needs the tick too', (tester) async {
    var accepted = false;
    await tester.pumpWidget(
      _app(PrivacyUpdatePage(onAccepted: () => accepted = true)),
    );
    expect(find.text("We've updated our Privacy Notice"), findsOneWidget);
    await tester.tap(find.text('Accept and continue'));
    await tester.pump();
    expect(find.text('Tick the box to create your account'), findsOneWidget);
    expect(accepted, isFalse);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('the login screen links the notice and terms', (tester) async {
    await tester.pumpWidget(_app(const LoginPage()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Privacy Notice'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
  });

  testWidgets('delete my account needs the business name typed', (
    tester,
  ) async {
    BusinessSettings.profile.value = {'name': 'Malnad Kitchen'};
    addTearDown(() => BusinessSettings.profile.value = {});
    await tester.pumpWidget(_app(const DeleteAccountPage()));
    expect(find.text('Download your data first'), findsOneWidget);
    FilledButton button() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete my account'),
    );
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Malnad');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  malnad kitchen ');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  test('the pages open on the website', () {
    expect(
      PrivacyInfo.page('privacy').toString(),
      'https://simplek.pages.dev/privacy',
    );
    expect(
      PrivacyInfo.page('terms').toString(),
      'https://simplek.pages.dev/terms',
    );
  });

  group('website pages', () {
    final privacy = File('website/privacy.html').readAsStringSync();
    final terms = File('website/terms.html').readAsStringSync();

    test('the Privacy Notice says what the change request lists', () {
      for (final phrase in [
        'Who we are',
        'Data Fiduciary',
        'on your behalf',
        'Supabase',
        'Cloudflare',
        'gstinapi.in',
        'Accountants you invite',
        'Mumbai, India',
        '30 days',
        'up to\n        12 months',
        'withdraw your consent',
        'Nominate a person',
        'Data Protection Board of India',
        'Grievance contact',
        'Version 1.0',
        '18 or older',
      ]) {
        expect(privacy, contains(phrase), reason: phrase);
      }
    });

    test('the Terms cover processing on the business\'s behalf', () {
      expect(terms, contains('We process that data only on your behalf'));
      expect(terms, contains('Data Fiduciary'));
      expect(terms, contains('href="privacy"'));
    });

    test('the website footer links both', () {
      for (final page in [
        File('website/index.html').readAsStringSync(),
        privacy,
        terms,
      ]) {
        expect(page, contains('<a href="privacy">Privacy Notice</a>'));
        expect(page, contains('<a href="terms">Terms of Service</a>'));
      }
    });
  });
}
