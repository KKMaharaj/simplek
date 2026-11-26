part of 'main.dart';

// CR-25B B4: privacy under the DPDP Act 2023 and Rules 2025. The consent at
// sign-up, the one-time "updated Privacy Notice" screen, Settings → "Your
// data and privacy" (download, correct, delete, nominee, concerns), the
// grievance contact and the web storage notice. The notice and terms are
// website pages (website/privacy.html, website/terms.html).

abstract final class PrivacyInfo {
  /// Changes when the notice or terms change; everyone accepts it once.
  static const noticeVersion = '2026-11-27';
  static const noticeLabel = 'Version 1.0, 27 November 2026';

  // Replace before launch (NOTES.md): the owner's grievance contact.
  static const grievanceName = '[Grievance contact, to be added]';
  static const grievanceEmail = '[Grievance email, to be added]';

  /// The website page, `privacy` or `terms`.
  static Uri page(String name) => kIsWeb
      ? Uri.base.resolve('/$name')
      : Uri.parse('https://simplek.pages.dev/$name');
}

Future<void> openPrivacyPage(String name) =>
    launchUrl(PrivacyInfo.page(name), mode: LaunchMode.externalApplication);

/// "Privacy Notice · Terms of Service".
class PrivacyLinks extends StatelessWidget {
  const PrivacyLinks({super.key, this.center = false});
  final bool center;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: center ? WrapAlignment.center : WrapAlignment.start,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        onPressed: () => openPrivacyPage('privacy'),
        child: const Text('Privacy Notice'),
      ),
      Text('·', style: Theme.of(context).textTheme.bodySmall),
      TextButton(
        onPressed: () => openPrivacyPage('terms'),
        child: const Text('Terms of Service'),
      ),
    ],
  );
}

/// The unticked "I am 18 or older and I agree…" box. Sign-up can't continue
/// until it is ticked.
class ConsentField extends FormField<bool> {
  ConsentField({super.key, ValueChanged<bool>? onChanged})
    : super(
        initialValue: false,
        validator: (value) =>
            value == true ? null : 'Tick the box to create your account',
        builder: (state) {
          final context = state.context;
          final theme = Theme.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                checked: state.value == true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    state.didChange(!(state.value ?? false));
                    onChanged?.call(state.value ?? false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: state.value ?? false,
                          onChanged: (value) {
                            state.didChange(value ?? false);
                            onChanged?.call(value ?? false);
                          },
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I am 18 or older and I agree to the Privacy '
                              'Notice and Terms',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 40),
                child: PrivacyLinks(),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 2),
                  child: Text(
                    state.errorText!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          );
        },
      );
}

/// Recording consents and the account-deletion grace period on the server.
abstract final class PrivacyRecords {
  /// True between asking to delete the account and signing out, so the
  /// sign-out's own events don't cancel the request.
  static bool deleting = false;

  static String get source {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'other',
    };
  }

  static String get device => 'Simplek $appVersion ($appBuild) $source';

  /// The metadata saved with a new sign-up's account: proof of the tick.
  static Map<String, String> signupConsent(DateTime ticked) => {
    'privacy_consent_version': PrivacyInfo.noticeVersion,
    'privacy_consent_at': ticked.toUtc().toIso8601String(),
  };

  static Future<void> record({DateTime? at}) => Supabase.instance.client.rpc(
    'record_consent',
    params: {
      'p_version': PrivacyInfo.noticeVersion,
      'p_source': source,
      'p_device': device,
      'p_consented_at': at?.toUtc().toIso8601String(),
    },
  );

  /// After a login: stores the consent ticked at sign-up, and returns true
  /// when the user still has to accept the current notice. Offline or on an
  /// error it returns false and asks again next time.
  static Future<bool> needsAcceptance() async {
    final client = Supabase.instance.client;
    try {
      final needed =
          await client.rpc(
                'consent_needed',
                params: {'p_version': PrivacyInfo.noticeVersion},
              )
              as bool;
      if (!needed) return false;
      final meta = client.auth.currentUser?.userMetadata ?? const {};
      if (meta['privacy_consent_version'] == PrivacyInfo.noticeVersion) {
        await record(at: DateTime.tryParse('${meta['privacy_consent_at']}'));
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A login within the 30 days cancels a deletion. Returns the day it was
  /// due when one was cancelled.
  static Future<DateTime?> cancelPendingDeletion() async {
    if (deleting) return null;
    try {
      final due = await Supabase.instance.client.rpc('cancel_account_deletion');
      return due == null ? null : DateTime.tryParse('$due')?.toLocal();
    } catch (_) {
      return null;
    }
  }
}

/// Shown once to a signed-in user who hasn't accepted this notice version.
class PrivacyUpdatePage extends StatefulWidget {
  const PrivacyUpdatePage({super.key, required this.onAccepted});
  final VoidCallback onAccepted;

  @override
  State<PrivacyUpdatePage> createState() => _PrivacyUpdatePageState();
}

class _PrivacyUpdatePageState extends State<PrivacyUpdatePage> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  Future<void> _accept() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await PrivacyRecords.record();
      widget.onAccepted();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _connectionMessage(error, fallback: 'Unable to save. Try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: FormWidth(
              child: Form(
                key: _formKey,
                child: SectionCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IconTile(Icons.privacy_tip_outlined, size: 48),
                      const SizedBox(height: 14),
                      Text(
                        "We've updated our Privacy Notice",
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'It explains what personal data Simplek keeps, why, '
                        'who receives it and how you can download, correct '
                        'or delete it. Please read it and the Terms of '
                        'Service, then accept to carry on.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        PrivacyInfo.noticeLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      ConsentField(),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saving ? null : _accept,
                        child: Text(
                          _saving ? 'Saving…' : 'Accept and continue',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => signOutEverywhereOnThisDevice(
                            context,
                            confirm: false,
                          ),
                          child: const Text('Log out'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The web app's small first-visit note: only essential storage is used.
abstract final class WebStorageNotice {
  static const _key = 'web_storage_notice_seen';

  static Future<void> showIfNeeded(BuildContext context) async {
    if (!kIsWeb) return;
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_key) ?? false) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.cookie_outlined),
        content: const Text(
          'Simplek keeps only what it needs to work in this browser, such as '
          'your login. No advertising or tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => openPrivacyPage('privacy'),
            child: const Text('Privacy Notice'),
          ),
          TextButton(
            onPressed: () async {
              messenger.hideCurrentMaterialBanner();
              await preferences.setBool(_key, true);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Settings → Your data and privacy.
class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  Map<String, dynamic>? _nominee;
  List<Map<String, dynamic>> _requests = const [];
  DateTime? _lastDownload;
  String? _progress;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final last = await DataExport.lastDownload();
    try {
      final results = await Future.wait<Object?>([
        client.from('privacy_nominees').select().maybeSingle(),
        client
            .from('privacy_requests')
            .select()
            .order('created_at', ascending: false)
            .limit(20),
      ]);
      if (!mounted) return;
      setState(() {
        _nominee = results[0] == null
            ? null
            : Map<String, dynamic>.from(results[0] as Map);
        _requests = List<Map<String, dynamic>>.from(results[1] as List);
        _lastDownload = last;
      });
    } catch (_) {
      if (mounted) setState(() => _lastDownload = last);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    if (_progress != null) return;
    setState(() => _progress = 'Getting your data…');
    try {
      await DataExport.run(
        onProgress: (text) {
          if (mounted) setState(() => _progress = text);
        },
      );
      final last = await DataExport.lastDownload();
      if (!mounted) return;
      setState(() => _lastDownload = last);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your data is ready. The download link works for 24 hours.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : _connectionMessage(
                    error,
                    fallback: 'Unable to prepare your data. Try again.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _editNominee() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _NomineeDialog(nominee: _nominee),
    );
    if (saved == true) await _load();
  }

  Future<void> _raiseConcern() async {
    final due = await showDialog<DateTime>(
      context: context,
      builder: (_) => const _ConcernDialog(),
    );
    if (due == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent. We will reply by ${screenDate(due)}.')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _lastDownload;
    return Scaffold(
      appBar: _simplekAppBar(context, 'Your data and privacy'),
      body: FormWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Your rights under the Digital Personal Data Protection Act, '
              '2023. Your customers\' details belong to your business; '
              'Simplek keeps them only for you.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const SectionLabel('Your data'),
            RowGroup(
              children: [
                ListRowTile(
                  leading: const IconTile(Icons.download_outlined, size: 40),
                  title: 'Download my data',
                  subtitle:
                      _progress ??
                      (last == null
                          ? 'Excel, JSON and every invoice as a PDF, in a ZIP'
                          : 'Last downloaded on this device ${screenDate(last)}'),
                  showChevron: _progress == null,
                  trailing: _progress == null
                      ? null
                      : const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                  onTap: _progress == null ? _download : null,
                ),
                ListRowTile(
                  leading: const IconTile(
                    Icons.edit_outlined,
                    tone: TileTone.sky,
                    size: 40,
                  ),
                  title: 'Correct my data',
                  subtitle: 'Change your name, business and bank details',
                  showChevron: true,
                  onTap: () => _openPage(context, const BusinessSettingsPage()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Someone to act for you'),
            RowGroup(
              children: [
                ListRowTile(
                  leading: const IconTile(
                    Icons.person_add_alt_outlined,
                    tone: TileTone.sky,
                    size: 40,
                  ),
                  title: 'Nominate a person',
                  subtitle: _nominee == null
                      ? (_loading
                            ? 'Loading…'
                            : 'Someone who can use these rights if you die or cannot act')
                      : '${_nominee!['name']} (${_nominee!['relation']}) · ${_nominee!['contact']}',
                  showChevron: true,
                  onTap: _editNominee,
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Questions and concerns'),
            RowGroup(
              children: [
                ListRowTile(
                  leading: const IconTile(
                    Icons.support_agent_outlined,
                    tone: TileTone.sky,
                    size: 40,
                  ),
                  title: 'Raise a concern',
                  subtitle: 'We reply within 30 days',
                  showChevron: true,
                  onTap: _raiseConcern,
                ),
                for (final request in _requests)
                  ListRowTile(
                    leading: IconTile(
                      request['status'] == 'answered' ||
                              request['status'] == 'closed'
                          ? Icons.mark_email_read_outlined
                          : Icons.schedule,
                      size: 40,
                    ),
                    title: '${request['message']}',
                    subtitle:
                        'Sent ${screenDate(parseStoredDate(request['created_at']))} · '
                        'reply by ${screenDate(parseStoredDate(request['due_at']))}'
                        '${request['answer'] == null ? '' : '\n${request['answer']}'}',
                    trailingTop: StatusChip(
                      (request['status']?.toString() ?? 'open').replaceAll(
                        '_',
                        ' ',
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grievance contact', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text(PrivacyInfo.grievanceName),
                  const SelectableText(PrivacyInfo.grievanceEmail),
                  const SizedBox(height: 6),
                  Text(
                    'If our answer doesn\'t settle it, you can complain to the '
                    'Data Protection Board of India.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SectionLabel('Delete my account'),
            RowGroup(
              children: [
                ListRowTile(
                  leading: const IconTile(
                    Icons.delete_outline,
                    tone: TileTone.orange,
                    size: 40,
                  ),
                  title: 'Delete my account',
                  subtitle:
                      'Also withdraws your consent. 30 days to change your mind',
                  showChevron: true,
                  onTap: BusinessAccess.readOnly
                      ? null
                      : () => _openPage(
                          context,
                          DeleteAccountPage(onDownload: _download),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const PrivacyLinks(),
            Text(PrivacyInfo.noticeLabel, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _NomineeDialog extends StatefulWidget {
  const _NomineeDialog({this.nominee});
  final Map<String, dynamic>? nominee;

  @override
  State<_NomineeDialog> createState() => _NomineeDialogState();
}

class _NomineeDialogState extends State<_NomineeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.nominee?['name']?.toString() ?? '',
  );
  late final _relation = TextEditingController(
    text: widget.nominee?['relation']?.toString() ?? '',
  );
  late final _contact = TextEditingController(
    text: widget.nominee?['contact']?.toString() ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _relation.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_connectionMessage(error, fallback: 'Unable to save.')),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await _run(
      () => Supabase.instance.client.from('privacy_nominees').upsert({
        'user_id': user.id,
        'name': _name.text.trim(),
        'relation': _relation.text.trim(),
        'contact': _contact.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? value, String what) =>
        (value ?? '').trim().isEmpty ? 'Enter the $what' : null;
    return AlertDialog(
      title: const Text('Nominate a person'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This person can use your privacy rights for you if you die '
                  'or cannot act yourself.',
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Name',
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) => required(value, 'name'),
                  ),
                ),
                const SizedBox(height: 10),
                LabeledField(
                  label: 'Relation',
                  child: TextFormField(
                    controller: _relation,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(hintText: 'e.g. Sister'),
                    validator: (value) => required(value, 'relation'),
                  ),
                ),
                const SizedBox(height: 10),
                LabeledField(
                  label: 'Email or mobile',
                  child: TextFormField(
                    controller: _contact,
                    validator: (value) => (value ?? '').trim().length < 3
                        ? 'Enter an email or mobile number'
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.nominee != null)
          TextButton(
            onPressed: _saving
                ? null
                : () => _run(
                    () => Supabase.instance.client
                        .from('privacy_nominees')
                        .delete()
                        .eq(
                          'user_id',
                          Supabase.instance.client.auth.currentUser!.id,
                        ),
                  ),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ConcernDialog extends StatefulWidget {
  const _ConcernDialog();

  @override
  State<_ConcernDialog> createState() => _ConcernDialogState();
}

class _ConcernDialogState extends State<_ConcernDialog> {
  static const _kinds = [
    ('concern', 'A concern about my data'),
    ('access', 'What data you keep about me'),
    ('correction', 'Correcting my data'),
    ('deletion', 'Deleting my data'),
    ('other', 'Something else'),
  ];
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  String _kind = 'concern';
  bool _saving = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final row = await Supabase.instance.client
          .from('privacy_requests')
          .insert({'kind': _kind, 'message': _message.text.trim()})
          .select('due_at')
          .single();
      if (mounted) {
        Navigator.of(context).pop(parseStoredDate(row['due_at']));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_connectionMessage(error, fallback: 'Unable to send.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Raise a concern'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'About',
                child: DropdownButtonFormField<String>(
                  initialValue: _kind,
                  items: [
                    for (final (value, label) in _kinds)
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (value) => setState(() => _kind = value!),
                ),
              ),
              const SizedBox(height: 10),
              LabeledField(
                label: 'Your message',
                child: TextFormField(
                  controller: _message,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Write what you would like us to know or do'
                      : null,
                ),
              ),
              Text(
                'Our grievance contact replies within 30 days. You can see '
                'the status here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _send,
        child: const Text('Send'),
      ),
    ],
  );
}

/// Delete my account: a warning to download first, the business name typed
/// to confirm, then 30 days' grace.
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key, this.onDownload});
  final Future<void> Function()? onDownload;

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _confirm = TextEditingController();
  bool _deleting = false;

  /// What must be typed: the business name, or the login email.
  String get _expected {
    final name = BusinessSettings.profile.value['name']?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return Supabase.instance.client.auth.currentUser?.email ?? '';
  }

  bool get _matches =>
      _expected.isNotEmpty &&
      _confirm.text.trim().toLowerCase() == _expected.toLowerCase();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_matches || _deleting) return;
    setState(() => _deleting = true);
    PrivacyRecords.deleting = true;
    try {
      final due = await Supabase.instance.client.rpc(
        'request_account_deletion',
        params: {'p_business_name': _confirm.text.trim()},
      );
      final day = DateTime.tryParse('$due')?.toLocal() ?? DateTime.now();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('Your account will be deleted'),
          content: Text(
            'On ${screenDate(day)} your account and all its data will be '
            'deleted. If you change your mind, just log in before then and '
            'the deletion is cancelled.\n\nYou will now be logged out on all '
            'your devices.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      await signOutEverywhereOnThisDevice(
        context,
        confirm: false,
        scope: SignOutScope.global,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _connectionMessage(error, fallback: 'Unable to delete. Try again.'),
          ),
        ),
      );
    } finally {
      PrivacyRecords.deleting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final usesEmail =
        (BusinessSettings.profile.value['name']?.trim() ?? '').isEmpty;
    return Scaffold(
      appBar: _simplekAppBar(context, 'Delete my account'),
      body: FormWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark
                    ? SimplekColors.orange.withValues(alpha: 0.16)
                    : SimplekColors.orangeTint,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: SimplekColors.orange.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: dark
                            ? SimplekColors.orange
                            : SimplekColors.orangeText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Download your data first',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'GST law requires businesses to keep their invoices for '
                    'several years. Once your account is deleted, Simplek '
                    'cannot bring them back.',
                  ),
                  if (widget.onDownload != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: widget.onDownload,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download my data'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Deleting your account also withdraws your consent to the '
              'Privacy Notice. Nothing is deleted for 30 days: log in during '
              'that time and the deletion is cancelled. On day 31 all your '
              'personal data, your business profile, customers, items, '
              'invoices, quotations and payments are deleted. Security logs '
              'are kept for one year, and encrypted backups for up to 12 '
              'months, then erased.',
            ),
            const SizedBox(height: 16),
            LabeledField(
              label: usesEmail
                  ? 'Type your email to confirm: $_expected'
                  : 'Type your business name to confirm: $_expected',
              child: TextField(
                controller: _confirm,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: _expected),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: _matches && !_deleting ? _delete : null,
              child: Text(_deleting ? 'Deleting…' : 'Delete my account'),
            ),
            if (!_matches)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  usesEmail
                      ? 'The button works once the email matches.'
                      : 'The button works once the business name matches.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Download my data": the server sends everything the account holds as
/// JSON (export_my_data); the app adds Excel and every invoice as a PDF,
/// zips it, stores it in the private data-exports folder and opens a link
/// that works for 24 hours. The PDFs are made with the same code as the
/// app's own invoices, so they look exactly the same.
abstract final class DataExport {
  static String _lastKey(String user) => 'last_data_download_$user';

  /// When "Download my data" (or "Download my backup") last ran here.
  static Future<DateTime?> lastDownload() async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    if (user == null) return null;
    final preferences = await SharedPreferences.getInstance();
    return DateTime.tryParse(preferences.getString(_lastKey(user)) ?? '');
  }

  static Future<void> run({required ValueChanged<String> onProgress}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Log in again to download your data.');
    if (BusinessAccess.readOnly) {
      throw StateError(
        'Switch back to your own business to download your data.',
      );
    }
    final data = Map<String, dynamic>.from(
      await client.rpc('export_my_data') as Map,
    );
    List<Map<String, dynamic>> rows(String key) => [
      for (final row in (data[key] as List?) ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];

    final archive = Archive();
    void add(String name, List<int> bytes) =>
        archive.addFile(ArchiveFile(name, bytes.length, bytes));

    add(
      'simplek-data.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    );

    onProgress('Making the Excel file…');
    final workbook = xlsx.Excel.createExcel();
    void sheet(String name, List<Map<String, dynamic>> list) {
      final page = workbook[name];
      final columns = <String>{for (final row in list) ...row.keys}.toList();
      page.appendRow([for (final c in columns) xlsx.TextCellValue(c)]);
      for (final row in list) {
        page.appendRow([
          for (final c in columns)
            row[c] is num
                ? xlsx.DoubleCellValue((row[c] as num).toDouble())
                : xlsx.TextCellValue(
                    row[c] == null
                        ? ''
                        : row[c] is Map || row[c] is List
                        ? jsonEncode(row[c])
                        : '${row[c]}',
                  ),
        ]);
      }
    }

    final profile = data['business_profile'] is Map
        ? Map<String, dynamic>.from(data['business_profile'] as Map)
        : <String, dynamic>{};
    sheet('Business profile', [
      for (final entry in profile.entries)
        {'field': entry.key, 'value': entry.value},
    ]);
    final invoices = rows('invoices');
    final items = rows('invoice_items');
    final customers = rows('customers');
    sheet('Customers', customers);
    sheet('Items', rows('products'));
    sheet('Invoices', invoices);
    sheet('Invoice lines', items);
    sheet('Payments', rows('payments'));
    sheet('Quotations', rows('quotations'));
    sheet('Quotation lines', rows('quotation_items'));
    if (workbook.sheets.containsKey('Sheet1')) workbook.delete('Sheet1');
    add('simplek-data.xlsx', workbook.encode() ?? const []);

    // Every invoice as a PDF, as the app draws it.
    final linesOf = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      linesOf.putIfAbsent('${item['invoice_id']}', () => []).add(item);
    }
    final contactOf = {
      for (final customer in customers)
        '${customer['name']}'.trim().toLowerCase(): customer,
    };
    for (final (index, invoice) in invoices.indexed) {
      onProgress('Making invoice PDFs: ${index + 1} of ${invoices.length}');
      final contact =
          contactOf['${invoice['customer_name']}'.trim().toLowerCase()] ??
          const {};
      final gst =
          BusinessSettings.isGstRegistered.value ||
          (invoice['tax_type']?.toString() ?? 'none') != 'none' ||
          Paise.parse(invoice['tax_amount']) > Paise.zero;
      final bytes = await buildDocumentPdf(
        PdfDocumentData(
          kind: PdfDocumentKind.invoice,
          number: invoice['invoice_number']?.toString() ?? 'Invoice',
          date: parseStoredDate(invoice['invoice_date']) ?? DateTime.now(),
          secondDate: parseStoredDate(invoice['due_date']),
          placeOfSupply: invoice['place_of_supply']?.toString() ?? '',
          customerName: invoice['customer_name']?.toString() ?? '',
          customerAddress: contact['address']?.toString() ?? '',
          customerGstin: gst ? invoice['customer_gstin']?.toString() ?? '' : '',
          customerPhone: contact['phone']?.toString() ?? '',
          items: [
            for (final line in linesOf['${invoice['id']}'] ?? const [])
              PdfLineItem(
                description: line['item_name']?.toString() ?? '',
                hsn: line['hsn_sac_code']?.toString() ?? '',
                quantity: (line['quantity'] as num?)?.toDouble() ?? 0,
                unit: line['uqc_code']?.toString() ?? '',
                rate: Paise.parse(line['unit_price']).inRupees,
                gstRate: (line['gst_rate'] as num?)?.toDouble() ?? 0,
                taxable: Paise.parse(line['taxable_amount']).inRupees,
                tax: Paise.parse(line['tax_amount']).inRupees,
              ),
          ],
          total: Paise.parse(invoice['total_amount']).inRupees,
          paid: Paise.parse(invoice['paid_amount']).inRupees,
          terms: invoice['terms']?.toString() ?? '',
          description: invoice['description']?.toString() ?? '',
          gstDocument: gst,
        ),
        BusinessSettings.profile.value,
      );
      final number = '${invoice['invoice_number'] ?? 'invoice'}'.replaceAll(
        RegExp(r'[^A-Za-z0-9-]+'),
        '_',
      );
      final folder = invoice['deleted_at'] == null
          ? 'invoices'
          : 'invoices/deleted';
      add('$folder/${index + 1}_$number.pdf', bytes);
    }

    onProgress('Packing and uploading…');
    final zip = ZipEncoder().encode(archive);
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final path =
        '${user.id}/simplek-data-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.zip';
    await client.storage
        .from('data-exports')
        .uploadBinary(
          path,
          Uint8List.fromList(zip),
          fileOptions: const FileOptions(
            contentType: 'application/zip',
            upsert: true,
          ),
        );
    final link = await client.storage
        .from('data-exports')
        .createSignedUrl(path, 24 * 60 * 60);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastKey(user.id), now.toIso8601String());
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }
}

/// CR-25B B5 part 2, on More → Sync and backup: the user's own copy of
/// everything (the same ZIP as "Download my data"), and when this device
/// last made one. Restoring from it is not part of the app; disaster
/// recovery uses the nightly server backup.
class _BackupDownloadCard extends StatefulWidget {
  const _BackupDownloadCard();

  @override
  State<_BackupDownloadCard> createState() => _BackupDownloadCardState();
}

class _BackupDownloadCardState extends State<_BackupDownloadCard> {
  DateTime? _last;
  String? _progress;

  @override
  void initState() {
    super.initState();
    DataExport.lastDownload().then((last) {
      if (mounted) setState(() => _last = last);
    });
  }

  Future<void> _download() async {
    setState(() => _progress = 'Getting your data…');
    try {
      await DataExport.run(
        onProgress: (text) {
          if (mounted) setState(() => _progress = text);
        },
      );
      final last = await DataExport.lastDownload();
      if (mounted) setState(() => _last = last);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : _connectionMessage(
                    error,
                    fallback: 'Unable to prepare your backup. Try again.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Download my backup', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A ZIP of your customers, items, invoices, quotations, payments '
            'and business profile (Excel and JSON), with every invoice as a '
            'PDF. Keep it somewhere safe.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            _progress ??
                (last == null
                    ? 'Not downloaded on this device yet.'
                    : 'Last downloaded on this device on ${screenDate(last)}.'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _progress == null ? _download : null,
            icon: _progress == null
                ? const Icon(Icons.download_outlined)
                : const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
            label: const Text('Download my backup'),
          ),
        ],
      ),
    );
  }
}
