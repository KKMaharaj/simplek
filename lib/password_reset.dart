part of 'main.dart';

// Change request 19 Nov 2026, change 2: "Forgot password?" with a code sent
// by email, not a link, so the email can be read on another device. It was
// postponed until Simplek could send its own email; the owner set up email
// sending (SMTP) on 26 Nov 2026.
//
// Screen A (email) and screen B (code) are [ResetPasswordPage]. Screen C,
// "Set a new password", is [ForcedPasswordPage] in its recovery mode, shown
// by AuthGate while [PasswordReset.recovering] is true. A reset link (an old
// email template without the code) lands on the same screen C.

abstract final class PasswordReset {
  /// True after a reset code or link logged the user in, until they save a
  /// new password or log out.
  static final recovering = ValueNotifier(false);

  /// Set by "Forgot password?" on the fingerprint lock screen: after logging
  /// out, the login screen opens the reset page with this email.
  static String? openFor;

  /// The project lets one email go out a minute (Auth → max frequency).
  static const resendAfter = Duration(seconds: 60);

  /// Wrong codes allowed before a new code must be requested (standard §3).
  static const maxTries = 5;
}

/// A reset code as typed or pasted: digits only, spaces and dashes removed.
String cleanResetCode(String text) => text.replaceAll(RegExp(r'\D'), '');

/// Supabase sends 6 to 10 digits, depending on the project's setting.
bool validResetCode(String code) => RegExp(r'^\d{6,10}$').hasMatch(code);

/// The password rules of BUILD-STANDARDS §3, shown before the person types.
const kPasswordRules = 'At least 8 characters, with a letter and a number';

String? passwordRuleError(String? value) {
  final text = value ?? '';
  if (text.length < 8 ||
      !RegExp(r'[A-Za-z]').hasMatch(text) ||
      !RegExp(r'\d').hasMatch(text)) {
    return kPasswordRules;
  }
  return null;
}

String _authErrorText(Object error) => error is AuthException
    ? '${error.statusCode ?? ''} ${error.code ?? ''} ${error.message}'
          .toLowerCase()
    : '$error'.toLowerCase();

bool _isRateLimited(String text) =>
    text.contains('429') ||
    text.contains('rate limit') ||
    text.contains('rate_limit') ||
    text.contains('too many') ||
    text.contains('only request this after');

bool _isOfflineAuthError(Object error) =>
    error is AuthRetryableFetchException || _isOfflineError(error);

/// Sending the code failed: plain words, never the raw error.
String resetSendError(Object error) {
  debugPrint('Password reset email failed: $error');
  if (_isOfflineAuthError(error)) {
    return 'No internet connection. Check Wi-Fi or mobile data and try again.';
  }
  if (_isRateLimited(_authErrorText(error))) {
    return 'Please wait a minute and try again.';
  }
  return "We couldn't send the email right now. Please try again later, or "
      'contact support.';
}

/// Checking the code failed. Supabase answers a wrong code and an expired
/// one the same way, so one message covers both.
String resetCodeError(Object error) {
  debugPrint('Password reset code failed: $error');
  if (_isOfflineAuthError(error)) {
    return 'No internet connection. Check Wi-Fi or mobile data and try again.';
  }
  final text = _authErrorText(error);
  if (_isRateLimited(text)) return 'Please wait a minute and try again.';
  return 'That code is wrong or has expired. Check it, or tap Resend code '
      'for a new one.';
}

/// Saving the new password failed.
String newPasswordError(Object error) {
  debugPrint('Saving a new password failed: $error');
  if (_isOfflineAuthError(error)) {
    return 'No internet connection. Check Wi-Fi or mobile data and try again.';
  }
  final text = _authErrorText(error);
  if (text.contains('same_password') || text.contains('different from')) {
    return 'Choose a password different from your old one.';
  }
  if (text.contains('weak_password') || text.contains('weak password')) {
    return '$kPasswordRules.';
  }
  if (_isRateLimited(text)) return 'Please wait a minute and try again.';
  if (text.contains('session') || text.contains('reauthentication')) {
    return 'Your login has expired. Log out, then use Forgot password? on '
        'the login screen.';
  }
  return "We couldn't save the password. Please try again.";
}

/// "Reset your password" (screen A) and "Enter the code" (screen B).
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, this.initialEmail = ''});
  final String initialEmail;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _emailForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail.trim());
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _tries = 0;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _address => _email.text.trim().toLowerCase();

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = PasswordReset.resendAfter.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _wait--);
      if (_wait <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    if (!_codeSent && !_emailForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _address,
        redirectTo: _authRedirectUrl,
      );
      if (!mounted) return;
      _code.clear();
      setState(() {
        _codeSent = true;
        _tries = 0;
      });
      _startCountdown();
    } catch (error) {
      if (mounted) setState(() => _error = resetSendError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = cleanResetCode(_code.text);
    if (!validResetCode(code)) {
      setState(() => _error = 'Enter the whole code from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Set first: verifyOTP logs in and AuthGate rebuilds straight away.
      PasswordReset.recovering.value = true;
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        email: _address,
        token: code,
      );
      // L1: a login that just happened skips the fingerprint.
      AppLock.markSignedInWithPassword();
      if (!mounted) return;
      // AuthGate now shows "Set a new password".
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      PasswordReset.recovering.value = false;
      if (!mounted) return;
      _tries++;
      setState(
        () => _error = _tries >= PasswordReset.maxTries
            ? 'Too many wrong codes. Tap Resend code for a new one.'
            : resetCodeError(error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    _code.clear();
    setState(() {
      _codeSent = false;
      _error = null;
      _wait = 0;
      _tries = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooManyTries = _tries >= PasswordReset.maxTries;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SectionCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _codeSent ? 'Enter the code' : 'Reset your password',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (!_codeSent) ...[
                    const Text(
                      "Enter your account's email. We'll send you a code to "
                      'set a new password.',
                    ),
                    const SizedBox(height: 14),
                    Form(
                      key: _emailForm,
                      child: AutofillGroup(
                        child: LabeledField(
                          label: 'Email',
                          child: TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            decoration: const InputDecoration(
                              hintText: 'you@business.in',
                            ),
                            validator: _emailValidator,
                            onFieldSubmitted: (_) => _busy ? null : _send(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _send,
                      child: Text(_busy ? 'Sending…' : 'Send code'),
                    ),
                  ] else ...[
                    Text(
                      "If an account exists for $_address, we've sent a code. "
                      'Check your inbox and spam folder.',
                    ),
                    const SizedBox(height: 14),
                    LabeledField(
                      label: 'Code',
                      child: TextField(
                        controller: _code,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          letterSpacing: 6,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Code from the email',
                          hintStyle: TextStyle(
                            fontSize: 16,
                            letterSpacing: 0,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        onSubmitted: (_) =>
                            _busy || tooManyTries ? null : _verify(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy || tooManyTries ? null : _verify,
                      child: Text(_busy ? 'Checking…' : 'Verify code'),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _busy || _wait > 0 ? null : _send,
                          child: Text(
                            _wait > 0
                                ? 'Resend code in $_wait s'
                                : 'Resend code',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _changeEmail,
                          child: const Text('Change email'),
                        ),
                      ],
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Forgot password?" under a password box: opens [ResetPasswordPage] with
/// the email typed so far.
class ForgotPasswordLink extends StatelessWidget {
  const ForgotPasswordLink({super.key, required this.email});
  final String Function() email;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: TextButton(
      onPressed: () =>
          _openPage(context, ResetPasswordPage(initialEmail: email())),
      child: const Text('Forgot password?'),
    ),
  );
}
