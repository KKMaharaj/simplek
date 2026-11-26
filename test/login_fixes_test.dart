// Change request 26 Nov 2026: login, sign-up, log-out and fingerprint fixes
// (docs/CHANGE_REQUEST_2026-11-26_LOGIN_FIXES.md).
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/app_lock.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Widget _gate({Future<void> Function()? onUsePassword}) => MaterialApp(
  theme: simplekTheme(Brightness.light),
  home: AppLockGate(
    onUsePassword: onUsePassword ?? () async {},
    child: const Scaffold(body: Text('Home')),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('L1 fingerprint', () {
    testWidgets('lock on + password login: no lock screen', (tester) async {
      SharedPreferences.setMockInitialValues({'app_lock_enabled_u1': true});
      await AppLock.load('u1');
      expect(AppLock.enabled.value, isTrue);
      AppLock.markSignedInWithPassword();
      await tester.pumpWidget(_gate());
      await tester.pump();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Simplek is locked'), findsNothing);
      expect(AppLock.justSignedIn, isFalse, reason: 'used once');
    });

    testWidgets('lock on + app restarted with a saved login: lock screen', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'app_lock_enabled_u1': true});
      await AppLock.load('u1');
      await tester.pumpWidget(_gate());
      await tester.pump();
      expect(find.text('Simplek is locked'), findsOneWidget);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('"Log in with password instead", then login: no loop', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'app_lock_enabled_u1': true});
      await AppLock.load('u1');
      var usedPassword = false;
      await tester.pumpWidget(
        _gate(onUsePassword: () async => usedPassword = true),
      );
      await tester.pump();
      await tester.tap(find.text('Log in with password instead'));
      expect(usedPassword, isTrue);
      // The user logs in again: a new gate opens unlocked.
      AppLock.markSignedInWithPassword();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_gate());
      await tester.pump();
      expect(find.text('Home'), findsOneWidget);
    });

    test('quick unlock is per account, not per phone', () async {
      SharedPreferences.setMockInitialValues({'app_lock_enabled_u1': true});
      await AppLock.load('u1');
      expect(AppLock.enabled.value, isTrue);
      await AppLock.load('u2');
      expect(AppLock.enabled.value, isFalse);
      await AppLock.load(null);
      expect(AppLock.enabled.value, isFalse);
    });
  });

  group('L2 pending sign-up', () {
    final now = DateTime.utc(2026, 11, 27, 12);
    Map<String, String> pending({
      String email = 'new@example.com',
      Duration age = const Duration(minutes: 5),
    }) => {
      'name': 'Asha',
      'businessName': 'Asha Traders',
      'mobile': '9876543210',
      'email': email,
      'savedAt': now.subtract(age).toIso8601String(),
    };
    bool applies(
      Map<String, String> value, {
      String email = 'new@example.com',
      bool passwordSet = false,
      bool passwordLogin = false,
    }) => pendingSignupApplies(
      pending: value,
      signedInEmail: email,
      passwordSet: passwordSet,
      passwordLogin: passwordLogin,
      now: now,
    );

    test('used for the same email, recent, no password, email link', () {
      expect(applies(pending()), isTrue);
      expect(applies(pending(), email: 'NEW@example.com '), isTrue);
    });

    test('ignored for another email, an old one, or a password login', () {
      expect(applies(pending(), email: 'other@example.com'), isFalse);
      expect(applies(pending(age: const Duration(hours: 25))), isFalse);
      expect(applies(pending(), passwordSet: true), isFalse);
      expect(applies(pending(), passwordLogin: true), isFalse);
      expect(applies(pending()..remove('email')), isFalse);
      expect(applies({...pending(), 'savedAt': ''}), isFalse);
    });

    test('saved with the email and time, and cleared', () async {
      await PendingSignup.save(
        name: 'Asha',
        businessName: 'Asha Traders',
        mobile: '9876543210',
        email: ' New@Example.com ',
        savedAt: now,
      );
      final saved = await PendingSignup.load();
      expect(saved!['email'], 'new@example.com');
      expect(saved['savedAt'], now.toIso8601String());
      await PendingSignup.clear();
      expect(await PendingSignup.load(), isNull);
    });
  });

  group('L3 set-up follows the server', () {
    test('an existing account skips password and set-up', () {
      final started = DateTime.utc(2026, 11, 27, 12);
      expect(isExistingAccount(passwordSet: false, hasProfile: false), isFalse);
      expect(isExistingAccount(passwordSet: true, hasProfile: false), isTrue);
      expect(isExistingAccount(passwordSet: false, hasProfile: true), isTrue);
      // Created long before this sign-up: an old account.
      expect(
        isExistingAccount(
          passwordSet: false,
          hasProfile: false,
          accountCreated: DateTime.utc(2026, 10, 1),
          signupStarted: started,
        ),
        isTrue,
      );
      // Created by this sign-up (seconds before it was saved).
      expect(
        isExistingAccount(
          passwordSet: false,
          hasProfile: false,
          accountCreated: started.subtract(const Duration(seconds: 3)),
          signupStarted: started,
        ),
        isFalse,
      );
    });

    test('set-up only for an owner without a profile', () {
      expect(
        needsBusinessSetup(hasProfile: false, sharedBusinesses: 0),
        isTrue,
      );
      expect(
        needsBusinessSetup(hasProfile: true, sharedBusinesses: 0),
        isFalse,
      );
      expect(
        needsBusinessSetup(hasProfile: false, sharedBusinesses: 2),
        isFalse,
        reason: 'an accountant works in shared businesses',
      );
    });

    testWidgets('set-up and the password page always have a way out', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: simplekTheme(Brightness.light),
          home: const BusinessOnboardingPage(
            ownerName: 'Asha',
            businessName: 'Asha Traders',
            mobile: '9876543210',
          ),
        ),
      );
      expect(find.text('Log out'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: simplekTheme(Brightness.light),
          home: const PasswordSetupPage(
            name: 'Asha',
            businessName: 'Asha Traders',
            mobile: '9876543210',
          ),
        ),
      );
      expect(find.text('Cancel and log out'), findsOneWidget);
    });
  });

  group('L4 log-out clears the old account', () {
    test('the next account sees a blank profile', () async {
      SharedPreferences.setMockInitialValues({
        'business_name': 'A Traders',
        'business_owner_name': 'Owner A',
        'business_gst_registered': true,
        'business_invoice_terms': 'Pay in 7 days',
      });
      FlutterSecureStorage.setMockInitialValues({
        'business_gstin': '29AAGCB7383J1Z4',
        'business_bank_account': '123456789',
      });
      await BusinessSettings.load();
      expect(BusinessSettings.profile.value['name'], 'A Traders');
      expect(BusinessSettings.profile.value['gstin'], '29AAGCB7383J1Z4');
      expect(BusinessSettings.isGstRegistered.value, isTrue);

      await BusinessSettings.clearLocal();
      expect(BusinessSettings.profile.value['name'] ?? '', isEmpty);
      expect(BusinessSettings.isGstRegistered.value, isFalse);

      // A fresh start (the next account on this phone) finds nothing.
      await BusinessSettings.load();
      final profile = BusinessSettings.profile.value;
      expect(profile['name'], isEmpty);
      expect(profile['ownerName'], isEmpty);
      expect(profile['gstin'], isEmpty);
      expect(profile['bankAccount'], isEmpty);
      expect(BusinessSettings.isGstRegistered.value, isFalse);
    });

    test('log-out also forgets the pending sign-up', () async {
      await PendingSignup.save(
        name: 'Asha',
        businessName: '',
        mobile: '9876543210',
        email: 'a@example.com',
      );
      await PendingSignup.clear();
      expect(await PendingSignup.load(), isNull);
    });
  });

  group('L5 sign-up email errors in plain words', () {
    test('rate limit and other errors', () {
      expect(
        signupEmailError(
          const AuthException('Email rate limit exceeded', statusCode: '429'),
        ),
        'Too many sign-up emails were sent in the last hour. Please try '
        'again later.',
      );
      expect(
        signupEmailError(const AuthException('Email address not authorized')),
        "We couldn't send the email right now. Please try again later, or "
        'contact support.',
      );
    });
  });
}
