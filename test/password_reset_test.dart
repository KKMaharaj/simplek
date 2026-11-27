// Change request 19 Nov 2026, change 2: "Forgot password?" with a code sent
// by email. Sending and checking the code need the live server, so those are
// a hand test (CHANGE-STATUS.md); this covers the rules, the messages and the
// screens that work without it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Widget _app(Widget home) =>
    MaterialApp(theme: simplekTheme(Brightness.light), home: home);

void main() {
  test('a code is 6 to 10 digits; pasted spaces and dashes are dropped', () {
    expect(cleanResetCode(' 123 456 '), '123456');
    expect(cleanResetCode('1234-5678'), '12345678');
    expect(validResetCode('123456'), isTrue);
    expect(validResetCode('12345678'), isTrue);
    expect(validResetCode('12345'), isFalse);
    expect(validResetCode('12345678901'), isFalse);
    expect(validResetCode('12a456'), isFalse);
  });

  test('password rules: 8 characters with a letter and a number', () {
    expect(passwordRuleError('short1'), kPasswordRules);
    expect(passwordRuleError('longenough'), kPasswordRules);
    expect(passwordRuleError('12345678'), kPasswordRules);
    expect(passwordRuleError('longenough1'), isNull);
  });

  group('messages never show the raw error', () {
    const expired = AuthException(
      'Token has expired or is invalid',
      statusCode: '403',
      code: 'otp_expired',
    );
    const tooMany = AuthException(
      'For security purposes, you can only request this after 42 seconds.',
      statusCode: '429',
      code: 'over_email_send_rate_limit',
    );
    final offline = AuthRetryableFetchException(message: 'Failed host lookup');

    test('a wrong or expired code', () {
      final message = resetCodeError(expired);
      expect(message, contains('wrong or has expired'));
      expect(message, contains('Resend code'));
      expect(message, isNot(contains('Token')));
    });

    test('too many emails or tries', () {
      expect(resetSendError(tooMany), 'Please wait a minute and try again.');
      expect(resetCodeError(tooMany), 'Please wait a minute and try again.');
    });

    test('no internet', () {
      expect(resetSendError(offline), startsWith('No internet connection'));
      expect(resetCodeError(offline), startsWith('No internet connection'));
      expect(newPasswordError(offline), startsWith('No internet connection'));
    });

    test('anything else', () {
      expect(
        resetSendError(Exception('boom')),
        "We couldn't send the email right now. Please try again later, or "
        'contact support.',
      );
      expect(
        newPasswordError(
          const AuthException(
            'New password should be different from the old password.',
            statusCode: '422',
            code: 'same_password',
          ),
        ),
        'Choose a password different from your old one.',
      );
      expect(
        newPasswordError(Exception('boom')),
        "We couldn't save the password. Please try again.",
      );
    });
  });

  testWidgets('screen A: the email is filled in and checked', (tester) async {
    await tester.pumpWidget(
      _app(const ResetPasswordPage(initialEmail: ' asha@example.in ')),
    );
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('asha@example.in'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('"Forgot password?" opens screen A with the typed email', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(Scaffold(body: ForgotPasswordLink(email: () => 'ravi@example.in'))),
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('ravi@example.in'), findsOneWidget);
  });

  testWidgets('screen C after a reset: rules shown, eye button, Log out', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ForcedPasswordPage(
          reason: NewPasswordReason.recovery,
          onDone: () async {},
        ),
      ),
    );
    expect(find.text('Set a new password'), findsOneWidget);
    expect(find.textContaining('Your old password will stop'), findsOneWidget);
    expect(find.text(kPasswordRules), findsOneWidget);
    expect(find.byTooltip('Show password'), findsNWidgets(2));
    expect(find.text('Save and continue'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('Settings → Change password has a back button, no Log out', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ForcedPasswordPage(
          reason: NewPasswordReason.change,
          onDone: () async {},
        ),
      ),
    );
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('Save password'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
  });

  test('the login screen, lock screen and Settings link to it', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('ForgotPasswordLink(email: () => _emailController'));
    expect(main, contains('onForgotPassword:'));
    expect(main, contains("title: 'Change password'"));
    expect(main, contains('AuthChangeEvent.passwordRecovery'));
    final lock = File('lib/app_lock.dart').readAsStringSync();
    expect(lock, contains("Text('Forgot password?')"));
  });
}
