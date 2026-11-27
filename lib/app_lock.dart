import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fingerprint / face unlock for a device that is already signed in.
///
/// The password is still what signs an account in. Once signed in, the session
/// stays on the device and this lock guards it, so opening the app needs only
/// a fingerprint or face.
///
/// Rules (CR 26 Nov, login fixes L1):
/// * a login (password or email link) never asks for the fingerprint;
/// * it is asked when the app opens with a saved login, or comes back after
///   more than 45 seconds in the background;
/// * the choice is stored per account, so another account signing in on the
///   same phone doesn't inherit it.
abstract final class AppLock {
  static String _enabledKey(String user) => 'app_lock_enabled_$user';
  static String _offeredKey(String user) => 'app_lock_offer_shown_$user';

  static final enabled = ValueNotifier(false);
  static final _auth = LocalAuthentication();
  static String? _user;

  /// Set by a login that just happened, so the user is not asked twice in a
  /// row. Read and reset once, when the lock gate opens.
  static bool _unlockedThisSession = false;

  /// Reads the choice of [user] (null when signed out: off).
  static Future<void> load([String? user]) async {
    _user = user;
    if (user == null) {
      enabled.value = false;
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    enabled.value = preferences.getBool(_enabledKey(user)) ?? false;
  }

  /// True when this device has a fingerprint or face enrolled.
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Turning the lock on requires proving the fingerprint or face works.
  static Future<bool> setEnabled(bool value) async {
    if (value && !await authenticate('Confirm to turn on quick unlock')) {
      return false;
    }
    final user = _user;
    if (user != null) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_enabledKey(user), value);
    }
    enabled.value = value;
    return true;
  }

  /// Call when a login has just succeeded (password or email link).
  static void markSignedInWithPassword() => _unlockedThisSession = true;

  /// For tests: whether the next lock gate will skip the lock.
  @visibleForTesting
  static bool get justSignedIn => _unlockedThisSession;

  static Future<bool> _shouldOffer() async {
    final user = _user;
    if (user == null || enabled.value || !await isAvailable()) return false;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_offeredKey(user)) ?? false) return false;
    await preferences.setBool(_offeredKey(user), true);
    return true;
  }
}

/// Shows [child] only after the device owner has unlocked the app.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    required this.onUsePassword,
    this.onForgotPassword,
  });

  final Widget child;

  /// Called when the user prefers to sign in again with their password.
  final Future<void> Function() onUsePassword;

  /// "Forgot password?" under it (CR 19 Nov, change 2): logs out and opens
  /// the reset page.
  final Future<void> Function()? onForgotPassword;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const _relockAfter = Duration(seconds: 45);

  bool _locked = false;
  bool _prompting = false;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Decide first, then reset: a login that just happened skips the lock.
    _locked = AppLock.enabled.value && !AppLock._unlockedThisSession;
    AppLock._unlockedThisSession = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_locked) {
        _unlock();
      } else {
        _offer();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _hiddenAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final hiddenAt = _hiddenAt;
      _hiddenAt = null;
      if (AppLock.enabled.value &&
          !_locked &&
          !_prompting &&
          hiddenAt != null &&
          DateTime.now().difference(hiddenAt) > _relockAfter) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final ok = await AppLock.authenticate('Unlock Simplek');
    _prompting = false;
    _hiddenAt = null;
    if (ok && mounted) setState(() => _locked = false);
  }

  Future<void> _offer() async {
    if (!await AppLock._shouldOffer() || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.fingerprint, size: 44),
        title: const Text('Unlock faster next time?'),
        content: const Text(
          'Open Simplek with your fingerprint or face instead of typing your '
          'password. You can change this in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (accepted == true) await AppLock.setEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/simplek-app-icon-hd.png',
                  width: 84,
                ),
                const SizedBox(height: 24),
                Text('Simplek is locked', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Use your fingerprint or face to continue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: widget.onUsePassword,
                  child: const Text('Log in with password instead'),
                ),
                if (widget.onForgotPassword != null)
                  TextButton(
                    onPressed: widget.onForgotPassword,
                    child: const Text('Forgot password?'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings row for the lock. Hidden where the device has no biometrics.
class AppLockSetting extends StatefulWidget {
  const AppLockSetting({super.key});

  @override
  State<AppLockSetting> createState() => _AppLockSettingState();
}

class _AppLockSettingState extends State<AppLockSetting> {
  late final Future<bool> _available = AppLock.isAvailable();

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _available,
    builder: (context, snapshot) {
      if (snapshot.data != true) return const SizedBox.shrink();
      return ValueListenableBuilder<bool>(
        valueListenable: AppLock.enabled,
        builder: (context, enabled, _) => Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Fingerprint or face unlock'),
            subtitle: const Text('Ask for it whenever Simplek is opened.'),
            value: enabled,
            onChanged: (value) async {
              final changed = await AppLock.setEnabled(value);
              if (!changed && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not confirm your fingerprint or face.',
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    },
  );
}
