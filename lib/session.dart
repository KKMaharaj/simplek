part of 'main.dart';

// Change request 26 Nov 2026, login fixes: one log-out that really logs out
// and forgets the old account (L4), and the rules that decide which set-up
// screen a login sees (L2, L3).

/// How the current session started.
abstract final class SessionOrigin {
  /// True from the moment a password login is tried until the next sign-out
  /// (L2: a pending sign-up is only for a login from the email link).
  static bool passwordLogin = false;
}

/// The last account signed in on this device (L4: a different account
/// signing in first clears the old one's local copy).
abstract final class LastAccount {
  static const _key = 'last_signed_in_user_id';

  /// Remembers [userId]; returns true when another account was here before.
  static Future<bool> switchedTo(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getString(_key);
    await preferences.setString(_key, userId);
    return previous != null && previous != userId;
  }
}

/// Forgets the account's local copy on this device: the business profile
/// and its files, the shared-business view, list and lock choices, the
/// pending sign-up and live updates. Never touches unsynced offline items.
Future<void> clearLocalAccountData() async {
  LiveSync.stop();
  BusinessAccess.viewing.value = null;
  await BusinessSettings.clearLocal();
  await ListPrefs.load(null);
  await AppLock.load(null);
  await PendingSignup.clear();
  DesignSettings.destination.value = 0;
}

/// The one way the app logs out (both Log out buttons, "Log in with password
/// instead", the privacy screens).
///
/// 1. With [confirm], asks first. If items saved offline haven't reached the
///    server, says so; they stay on the device under this account and upload
///    at the next login to it.
/// 2. Signs out; if the network call fails, the session saved on this device
///    is removed anyway, so the user is logged out here either way.
/// 3. Clears this account's local copy ([clearLocalAccountData]).
/// 4. Closes every open screen, leaving the login screen.
///
/// Returns false when the user chose to stay.
Future<bool> signOutEverywhereOnThisDevice(
  BuildContext context, {
  bool confirm = true,
  SignOutScope scope = SignOutScope.local,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var waiting = 0;
  try {
    waiting = (await OfflineStore.pendingCounts()).values.fold(
      0,
      (sum, count) => sum + count,
    );
  } catch (_) {
    // Unknown; the log-out still goes ahead if the user confirms.
  }
  if (confirm || waiting > 0) {
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Log out of Simplek?'),
        content: Text(
          waiting > 0
              ? "$waiting item${waiting == 1 ? '' : 's'} haven't reached the "
                    "server yet. Log out anyway? They'll upload next time you "
                    'log in to this account.'
              : 'You will need your password to log in again.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(waiting > 0 ? 'Log out anyway' : 'Log out'),
          ),
        ],
      ),
    );
    if (go != true) return false;
  }
  try {
    // The session on this device is removed before the server is told, so
    // a network failure here still logs this device out.
    await Supabase.instance.client.auth.signOut(scope: scope);
  } catch (error) {
    debugPrint('Sign-out request failed (logged out on this device): $error');
  }
  SessionOrigin.passwordLogin = false;
  await clearLocalAccountData();
  navigator.popUntil((route) => route.isFirst);
  return true;
}

/// Login fixes L2: a pending sign-up saved on this device is used only when
/// the signed-in email is the one it was saved for, it is less than 24 hours
/// old, the account has no password yet, and the login came from the email
/// link (not a password login).
bool pendingSignupApplies({
  required Map<String, String> pending,
  required String? signedInEmail,
  required bool passwordSet,
  required bool passwordLogin,
  DateTime? now,
}) {
  final email = pending['email']?.trim().toLowerCase() ?? '';
  final saved = DateTime.tryParse(pending['savedAt'] ?? '');
  if (email.isEmpty || saved == null) return false;
  if (email != (signedInEmail ?? '').trim().toLowerCase()) return false;
  if ((now ?? DateTime.now()).difference(saved) > const Duration(hours: 24)) {
    return false;
  }
  return !passwordSet && !passwordLogin;
}

/// Login fixes L3: an account counts as existing (no password or set-up
/// screens) when it already has a password or a business profile, or was
/// created before this sign-up started.
bool isExistingAccount({
  required bool passwordSet,
  required bool hasProfile,
  DateTime? accountCreated,
  DateTime? signupStarted,
}) =>
    passwordSet ||
    hasProfile ||
    (accountCreated != null &&
        signupStarted != null &&
        accountCreated.isBefore(
          signupStarted.subtract(const Duration(minutes: 1)),
        ));

/// Login fixes L3: "Set up your business" for an owner account without a
/// profile; never for an accountant who works in businesses shared with it.
bool needsBusinessSetup({
  required bool hasProfile,
  required int sharedBusinesses,
}) => !hasProfile && sharedBusinesses == 0;

/// The sign-up email error in plain words (L5); the full error goes to the
/// debug log.
String signupEmailError(Object error) {
  debugPrint('Sign-up email failed: $error');
  final text = error is AuthException
      ? '${error.statusCode ?? ''} ${error.message}'.toLowerCase()
      : '$error'.toLowerCase();
  if (text.contains('429') ||
      text.contains('rate limit') ||
      text.contains('too many')) {
    return 'Too many sign-up emails were sent in the last hour. Please try '
        'again later.';
  }
  if (_isOfflineError(error)) {
    return 'No internet connection. Check your connection and try again.';
  }
  return "We couldn't send the email right now. Please try again later, or "
      'contact support.';
}
