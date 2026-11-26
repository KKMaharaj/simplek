part of 'main.dart';

// Change request 26 Nov 2026: the super admin panel (web only), opened at
// https://simplek.pages.dev/app/#/admin. Everything here is checked again on
// the server: every admin_* function calls require_super_admin(), which
// needs a listed user with the two-step login (aal2). Hiding this page is not
// the protection; the server is.

/// True when the web app was opened at `#/admin` (read once at start-up,
/// before Flutter's own navigation rewrites the address).
bool _openedAtAdmin = false;

void _readAdminAddress() {
  if (!kIsWeb) return;
  final fragment = Uri.base.fragment;
  _openedAtAdmin = fragment == '/admin' || fragment.startsWith('/admin/');
}

Future<dynamic> _adminRpc(String name, [Map<String, dynamic>? params]) =>
    Supabase.instance.client.rpc(name, params: params);

/// Shares (phone) or downloads (web) a file the admin exported.
Future<void> _shareAdminFile(
  List<int> bytes,
  String filename,
  String mimeType,
) async {
  final file = kIsWeb
      ? XFile.fromData(
          Uint8List.fromList(bytes),
          name: filename,
          mimeType: mimeType,
        )
      : XFile(await writeTempFile(filename, bytes), mimeType: mimeType);
  await SharePlus.instance.share(ShareParams(files: [file]));
}

/// Exports [rows] as Excel or CSV with [columns] (key, header), logged.
Future<void> _exportAdminList(
  BuildContext context, {
  required String name,
  required String format,
  required List<Map<String, dynamic>> rows,
  required List<(String, String)> columns,
}) async {
  String cell(Object? value) => value == null
      ? ''
      : value is Map || value is List
      ? jsonEncode(value)
      : '$value';
  final stamp = DatePeriod.dbDate(DateTime.now());
  if (format == 'csv') {
    String quote(String text) => '"${text.replaceAll('"', '""')}"';
    final lines = [
      columns.map((c) => quote(c.$2)).join(','),
      for (final row in rows)
        columns.map((c) => quote(cell(row[c.$1]))).join(','),
    ];
    await _shareAdminFile(
      utf8.encode('﻿${lines.join('\r\n')}'),
      'simplek_admin_${name}_$stamp.csv',
      'text/csv',
    );
  } else {
    final workbook = xlsx.Excel.createExcel();
    final sheet = workbook[name];
    sheet.appendRow([for (final c in columns) xlsx.TextCellValue(c.$2)]);
    for (final row in rows) {
      sheet.appendRow([
        for (final c in columns)
          row[c.$1] is num
              ? xlsx.DoubleCellValue((row[c.$1] as num).toDouble())
              : xlsx.TextCellValue(cell(row[c.$1])),
      ]);
    }
    if (workbook.sheets.containsKey('Sheet1')) workbook.delete('Sheet1');
    await _shareAdminFile(
      workbook.encode() ?? const [],
      'simplek_admin_${name}_$stamp.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }
  try {
    // S7: exports of business lists are logged.
    await _adminRpc('admin_log_event', {
      'p_action': 'list_export',
      'p_business': null,
      'p_details': {'list': name, 'format': format, 'rows': rows.length},
    });
  } catch (_) {}
}

/// "Page not found", the same for anyone who isn't a super admin.
class _NotFoundPage extends StatelessWidget {
  const _NotFoundPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                _openedAtAdmin = false;
                UrlState.replace({'tab': 'home'});
                invoiceChanges.value++;
                (context.findAncestorStateOfType<_AuthGateState>())?._refresh();
              },
              child: const Text('Go to Simplek'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The admin area's door: page not found for others; the two-step login
/// set-up or check for super admins; then the panel.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key, required this.onExit});
  final VoidCallback onExit;

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  bool _loading = true;
  bool _member = false;
  bool _verified = false;
  String? _factorId;
  AuthMFAEnrollResponse? _enrolment;
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final auth = Supabase.instance.client.auth;
    try {
      final member = await _adminRpc('is_super_admin_member') == true;
      if (!member) {
        setState(() {
          _member = false;
          _loading = false;
        });
        return;
      }
      final level = auth.mfa.getAuthenticatorAssuranceLevel();
      final factors = await auth.mfa.listFactors();
      final verified = factors.totp
          .where((f) => f.status == FactorStatus.verified)
          .toList();
      setState(() {
        _member = true;
        _verified = level.currentLevel == AuthenticatorAssuranceLevels.aal2;
        _factorId = verified.isEmpty ? null : verified.first.id;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = _connectionMessage(error, fallback: 'Unable to check.');
        _loading = false;
      });
    }
  }

  Future<void> _enrol() async {
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      // An earlier, unfinished set-up is removed first.
      final factors = await auth.mfa.listFactors();
      for (final factor in factors.totp) {
        if (factor.status != FactorStatus.verified) {
          await auth.mfa.unenroll(factor.id);
        }
      }
      final enrolment = await auth.mfa.enroll(
        issuer: 'Simplek',
        friendlyName: 'Simplek admin ${DateTime.now().millisecondsSinceEpoch}',
      );
      setState(() {
        _enrolment = enrolment;
        _factorId = enrolment.id;
      });
    } catch (error) {
      setState(() => _error = _connectionMessage(error, fallback: '$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final factorId = _factorId;
    if (factorId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.mfa.challengeAndVerify(
        factorId: factorId,
        code: _code.text.trim(),
      );
      await Supabase.instance.client.auth.refreshSession();
      setState(() {
        _verified = true;
        _enrolment = null;
      });
    } catch (error) {
      setState(
        () => _error =
            'That code did not work. Check the time on your phone '
            'and try the newest code.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_member) return const _NotFoundPage();
    if (_verified) return AdminShell(onExit: widget.onExit);
    final theme = Theme.of(context);
    final enrolment = _enrolment;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SectionCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _AdminBadge(),
                  const SizedBox(height: 12),
                  Text('Two-step login', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  if (_factorId == null && enrolment == null) ...[
                    const Text(
                      'The admin area needs a code from an authenticator app '
                      '(Google Authenticator, Microsoft Authenticator, Authy) '
                      'every time you open it. Set it up once.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _enrol,
                      child: const Text('Set up two-step login'),
                    ),
                  ] else ...[
                    if (enrolment?.totp != null) ...[
                      const Text(
                        'Scan this with your authenticator app, or type the key.',
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(
                            data: enrolment!.totp!.uri,
                            size: 180,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        'Key: ${enrolment.totp!.secret}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ] else
                      const Text(
                        'Enter the 6-digit code from your authenticator app.',
                      ),
                    const SizedBox(height: 8),
                    LabeledField(
                      label: 'Code',
                      child: TextField(
                        controller: _code,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofocus: true,
                        onSubmitted: (_) => _verify(),
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      child: Text(_busy ? 'Checking…' : 'Continue'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onExit,
                    child: const Text('Back to Simplek'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: SimplekColors.orange,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text('ADMIN', style: inter(11, FontWeight.w800, SimplekColors.navy)),
  );
}

enum _AdminPage {
  dashboard('Dashboard', Icons.bar_chart_outlined),
  businesses('Businesses', Icons.storefront_outlined),
  users('Users', Icons.people_alt_outlined),
  plans('Plans', Icons.sell_outlined),
  integrations('Integrations', Icons.settings_outlined),
  audit('Audit log', Icons.receipt_long_outlined),
  settings('Platform settings', Icons.lock_outline);

  const _AdminPage(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The admin frame: a white sidebar, the ADMIN badge, and the page.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.onExit});
  final VoidCallback onExit;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  _AdminPage _page = _AdminPage.dashboard;
  bool _razorpayTest = false;

  @override
  void initState() {
    super.initState();
    _adminRpc('admin_integrations').then((value) {
      final mode = (value as Map?)?['razorpay']?['config']?['mode'];
      if (mounted) {
        setState(() => _razorpayTest = mode != 'live' && mode != null);
      }
    }, onError: (_) {});
  }

  void _openBusiness(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminBusinessPage(businessId: id, onExit: widget.onExit),
    ),
  );

  Widget _body() => switch (_page) {
    _AdminPage.dashboard => AdminDashboardPage(onOpenBusiness: _openBusiness),
    _AdminPage.businesses => AdminBusinessesPage(onOpenBusiness: _openBusiness),
    _AdminPage.users => const AdminUsersPage(),
    _AdminPage.plans => const AdminPlansPage(),
    _AdminPage.integrations => AdminIntegrationsPage(
      onModeChanged: (test) => setState(() => _razorpayTest = test),
    ),
    _AdminPage.audit => const AdminAuditPage(),
    _AdminPage.settings => const AdminSettingsPage(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final email = _signedInEmail();
    final menu = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Row(
            children: [
              Text('Simplek', style: fraunces(24, theme.colorScheme.onSurface)),
              const SizedBox(width: 8),
              const _AdminBadge(),
            ],
          ),
        ),
        for (final page in _AdminPage.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Pressable(
              onTap: () {
                setState(() => _page = page);
                if (!wide) Navigator.of(context).maybePop();
              },
              semanticLabel: page.label,
              borderRadius: BorderRadius.circular(12),
              color: page == _page
                  ? SimplekColors.orangeTint
                  : Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Icon(page.icon, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      page.label,
                      style: inter(
                        15,
                        page == _page ? FontWeight.w700 : FontWeight.w500,
                        theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SectionCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Signed in as', style: theme.textTheme.bodySmall),
                Text(email, style: theme.textTheme.titleSmall),
                Text('Two-step login on', style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: widget.onExit,
                  child: const Text('Back to Simplek'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_razorpayTest)
          Container(
            color: SimplekColors.orangeTint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Razorpay is in Test mode',
              style: inter(13, FontWeight.w600, SimplekColors.orangeText),
            ),
          ),
        Expanded(
          child: KeyedSubtree(key: ValueKey(_page), child: _body()),
        ),
      ],
    );
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 250,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    right: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: menu,
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(_page.label),
            const SizedBox(width: 8),
            const _AdminBadge(),
          ],
        ),
      ),
      drawer: Drawer(child: SafeArea(child: menu)),
      body: content,
    );
  }
}

/// The page title row of an admin page.
class _AdminHeader extends StatelessWidget {
  const _AdminHeader(this.title, {this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Super admin', style: Theme.of(context).textTheme.bodySmall),
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ),
  );
}

/// "212 / 250" with a bar: sky, orange from 80%, red when over.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.used, required this.allowed});
  final int used;
  final int? allowed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limit = allowed;
    final share = limit == null || limit == 0
        ? 0.0
        : (used / limit).clamp(0.0, 1.0);
    final colour = limit == null
        ? SimplekColors.sky
        : used >= limit
        ? theme.colorScheme.error
        : share >= 0.8
        ? SimplekColors.orange
        : SimplekColors.sky;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          limit == null ? '$used · no limit' : '$used / $limit',
          style: inter(
            14,
            FontWeight.w700,
            limit != null && share >= 0.8
                ? colour
                : theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: limit == null ? 0 : share,
            minHeight: 6,
            color: colour,
            backgroundColor: SimplekColors.skyTint,
          ),
        ),
      ],
    );
  }
}

String _adminStatusWord(String? status, bool quiet) => switch (status) {
  'suspended' => 'Suspended',
  'deletion_pending' => 'Deletion pending',
  _ => quiet ? 'Gone quiet' : 'Active',
};

/// Twelve bars, one per month.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.title, required this.months});
  final String title;
  final List<Map<String, dynamic>> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = [for (final m in months) (m['count'] as num?)?.toInt() ?? 0];
    final highest = counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, m) in months.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Tooltip(
                            message: '${counts[i]}',
                            child: Container(
                              height: highest == 0
                                  ? 3
                                  : (80 * counts[i] / highest).clamp(3, 80),
                              decoration: BoxDecoration(
                                color: i == months.length - 1
                                    ? SimplekColors.orange
                                    : SimplekColors.sky,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              names[(int.tryParse(
                                        '${m['month']}'.split('-').last,
                                      ) ??
                                      1) -
                                  1],
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- S1 Dashboard -------------------------------------------------------

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, required this.onOpenBusiness});
  final ValueChanged<String> onOpenBusiness;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  String _period = '30 days';
  DateTimeRange? _custom;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTimeRange get _range {
    final today = DateUtils.dateOnly(DateTime.now());
    return switch (_period) {
      'Today' => DateTimeRange(start: today, end: today),
      '7 days' => DateTimeRange(
        start: today.subtract(const Duration(days: 6)),
        end: today,
      ),
      'This month' => DateTimeRange(
        start: DateTime(today.year, today.month),
        end: today,
      ),
      'Custom' => _custom ?? DateTimeRange(start: today, end: today),
      _ => DateTimeRange(
        start: today.subtract(const Duration(days: 29)),
        end: today,
      ),
    };
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _adminRpc('admin_dashboard', {
        'p_from': DatePeriod.dbDate(_range.start),
        'p_to': DatePeriod.dbDate(_range.end),
      });
      if (mounted) {
        setState(() => _data = Map<String, dynamic>.from(data as Map));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _connectionMessage(error, fallback: '$error'));
      }
    }
  }

  Future<void> _choose(String period) async {
    if (period == 'Custom') {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2026),
        lastDate: now,
        initialDateRange: _custom,
      );
      if (range == null) return;
      _custom = range;
    }
    setState(() => _period = period);
    await _load();
  }

  List<Map<String, dynamic>> _list(String key) => [
    for (final row in (_data?[key] as List?) ?? const [])
      Map<String, dynamic>.from(row as Map),
  ];

  Widget _businessList(
    String title,
    List<Map<String, dynamic>> rows,
    String empty,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        if (rows.isEmpty)
          SectionCard(child: Text(empty))
        else
          RowGroup(
            children: [
              for (final row in rows)
                ListRowTile(
                  leading: InitialTile(row['business_name']?.toString() ?? ''),
                  title: row['business_name']?.toString() ?? '',
                  subtitle:
                      '${row['email'] ?? ''} · last invoice '
                      '${screenDate(parseStoredDate(row['last_invoice']))}',
                  trailingTop: _UsageBar(
                    used: (row['used'] as num?)?.toInt() ?? 0,
                    allowed: (row['allowed'] as num?)?.toInt(),
                  ),
                  onTap: () => widget.onOpenBusiness('${row['user_id']}'),
                ),
            ],
          ),
        const SizedBox(height: 18),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    int count(String key) => (data?[key] as num?)?.toInt() ?? 0;
    final enrolled = count('enrolled');
    final active = count('active');
    final byPlan = _list('by_plan');
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _AdminHeader(
          'Dashboard',
          actions: [
            for (final period in const [
              'Today',
              '7 days',
              '30 days',
              'This month',
              'Custom',
            ])
              ChoiceChip(
                label: Text(period),
                selected: period == _period,
                onSelected: (_) => _choose(period),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _error != null
              ? _loadError(_error!, _load)
              : data == null
              ? const SkeletonRows(count: 4)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final tiles = [
                          StatTile(
                            label: 'Businesses enrolled',
                            value:
                                '$enrolled (+${count('enrolled_in_period')})',
                            filled: true,
                          ),
                          StatTile(
                            label: 'Active (invoice in period)',
                            value: enrolled == 0
                                ? '$active'
                                : '$active · ${(active * 100 / enrolled).round()}%',
                            tone: TileTone.sky,
                          ),
                          StatTile(
                            label: 'Invoices this period',
                            value: '${count('invoices')}',
                          ),
                          StatTile(
                            label: 'Near · over the limit',
                            value:
                                '${count('near_limit')} · ${count('over_limit')}',
                            tone: TileTone.orange,
                          ),
                          StatTile(
                            label: 'New sign-ups',
                            value: '${count('signups')}',
                          ),
                          StatTile(
                            label: 'Plans',
                            value: byPlan.isEmpty
                                ? '-'
                                : byPlan
                                      .map((p) => '${p['plan']} ${p['count']}')
                                      .join(' · '),
                          ),
                          StatTile(
                            label: 'Monthly revenue',
                            value: rupees(count('mrr')),
                          ),
                        ];
                        final columns = constraints.maxWidth >= 1000
                            ? 4
                            : constraints.maxWidth >= 600
                            ? 2
                            : 1;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final tile in tiles)
                              SizedBox(
                                width:
                                    (constraints.maxWidth -
                                        12 * (columns - 1)) /
                                    columns,
                                child: tile,
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _MonthBars(
                      title: 'Sign-ups per month',
                      months: _list('signups_by_month'),
                    ),
                    const SizedBox(height: 12),
                    _MonthBars(
                      title: 'Invoices per month',
                      months: _list('invoices_by_month'),
                    ),
                    const SizedBox(height: 18),
                    _businessList(
                      'Recently active',
                      _list('recently_active'),
                      'No invoices yet.',
                    ),
                    _businessList(
                      'Gone quiet (no invoice in 30+ days)',
                      _list('gone_quiet'),
                      'Nobody has gone quiet.',
                    ),
                    _businessList(
                      'Needs attention (over the limit)',
                      _list('needs_attention'),
                      'Nothing needs attention.',
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// --- S2 Businesses --------------------------------------------------------

class AdminBusinessesPage extends StatefulWidget {
  const AdminBusinessesPage({super.key, required this.onOpenBusiness});
  final ValueChanged<String> onOpenBusiness;

  @override
  State<AdminBusinessesPage> createState() => _AdminBusinessesPageState();
}

class _AdminBusinessesPageState extends State<AdminBusinessesPage> {
  late final PagedRows _rows = PagedRows(_fetch);
  final _search = TextEditingController();
  Timer? _timer;
  String? _plan;
  String? _status;
  String? _gst;
  bool _quiet = false;
  bool _nearLimit = false;
  DateTimeRange? _joined;
  String _sort = 'last_invoice';
  List<Map<String, dynamic>> _plans = const [];

  static const _columns = [
    ('business_name', 'Business'),
    ('owner_name', 'Owner'),
    ('email', 'Login email'),
    ('mobile', 'Mobile'),
    ('gst_registered', 'GST registered'),
    ('gstin', 'GSTIN'),
    ('city', 'City'),
    ('state', 'State'),
    ('plan_name', 'Plan'),
    ('used', 'Invoices used'),
    ('allowed', 'Limit'),
    ('last_invoice', 'Last invoice'),
    ('last_login', 'Last login'),
    ('joined', 'Joined'),
    ('status', 'Status'),
  ];

  @override
  void initState() {
    super.initState();
    _rows.addListener(() {
      if (mounted) setState(() {});
    });
    _rows.restart();
    _adminRpc('admin_plans').then((value) {
      if (mounted) {
        setState(
          () => _plans = [
            for (final p in value as List) Map<String, dynamic>.from(p as Map),
          ],
        );
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rows.dispose();
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> _params(int offset, int limit) => {
    'p_search': _search.text.trim(),
    'p_plan': _plan,
    'p_status': _status,
    'p_gst': _gst,
    'p_quiet': _quiet,
    'p_near_limit': _nearLimit,
    'p_joined_from': _joined == null ? null : DatePeriod.dbDate(_joined!.start),
    'p_joined_to': _joined == null ? null : DatePeriod.dbDate(_joined!.end),
    'p_sort': _sort,
    'p_offset': offset,
    'p_limit': limit,
  };

  Future<PageResult> _fetch(int from, int to) async {
    final result = Map<String, dynamic>.from(
      await _adminRpc('admin_businesses', _params(from, to - from + 1)) as Map,
    );
    return PageResult([
      for (final r in result['rows'] as List)
        Map<String, dynamic>.from(r as Map),
    ], (result['total'] as num).toInt());
  }

  void _changed(VoidCallback change) {
    setState(change);
    _rows.restart();
  }

  Future<void> _export(String format) async {
    final result = Map<String, dynamic>.from(
      await _adminRpc('admin_businesses', _params(0, 5000)) as Map,
    );
    if (!mounted) return;
    await _exportAdminList(
      context,
      name: 'businesses',
      format: format,
      rows: [
        for (final r in result['rows'] as List)
          Map<String, dynamic>.from(r as Map),
      ],
      columns: _columns,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(String label, bool on, VoidCallback onTap) => FilterChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => onTap(),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _AdminHeader(
          'Businesses',
          actions: [
            OutlinedButton.icon(
              onPressed: () => _export('xlsx'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Excel'),
            ),
            OutlinedButton.icon(
              onPressed: () => _export('csv'),
              icon: const Icon(Icons.download_outlined),
              label: const Text('CSV'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ListSearch(
                controller: _search,
                hint: 'Search name, email, mobile, GSTIN, city',
                onChanged: (_) {
                  _timer?.cancel();
                  _timer = Timer(
                    const Duration(milliseconds: 350),
                    _rows.restart,
                  );
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  chip(
                    'All plans',
                    _plan == null,
                    () => _changed(() => _plan = null),
                  ),
                  for (final p in _plans)
                    chip(
                      '${p['name']}',
                      _plan == p['code'],
                      () => _changed(() => _plan = '${p['code']}'),
                    ),
                  chip(
                    'No invoice 30+ days',
                    _quiet,
                    () => _changed(() => _quiet = !_quiet),
                  ),
                  chip(
                    'Near or over the limit',
                    _nearLimit,
                    () => _changed(() => _nearLimit = !_nearLimit),
                  ),
                  for (final (value, label) in const [
                    ('active', 'Active'),
                    ('suspended', 'Suspended'),
                    ('deletion_pending', 'Deletion pending'),
                  ])
                    chip(
                      label,
                      _status == value,
                      () => _changed(
                        () => _status = _status == value ? null : value,
                      ),
                    ),
                  chip(
                    'GST',
                    _gst == 'yes',
                    () => _changed(() => _gst = _gst == 'yes' ? null : 'yes'),
                  ),
                  chip(
                    'No GST',
                    _gst == 'no',
                    () => _changed(() => _gst = _gst == 'no' ? null : 'no'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _joined == null
                          ? 'Joined between…'
                          : 'Joined ${screenDate(_joined!.start)} – ${screenDate(_joined!.end)}',
                    ),
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2026),
                        lastDate: DateTime.now(),
                        initialDateRange: _joined,
                      );
                      _changed(() => _joined = range);
                    },
                  ),
                  _SortButton(
                    options: const [
                      ('last_invoice', 'Last invoice'),
                      ('name', 'Name A–Z'),
                      ('joined', 'Newest'),
                      ('used', 'Most invoices used'),
                      ('last_login', 'Last login'),
                    ],
                    selected: _sort,
                    onSelected: (value) => _changed(() => _sort = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_rows.error != null && _rows.rows.isEmpty)
                _loadError(
                  _connectionMessage(_rows.error!, fallback: '${_rows.error}'),
                  _rows.refresh,
                )
              else if (_rows.loading && _rows.rows.isEmpty)
                const SkeletonRows()
              else if (_rows.rows.isEmpty)
                const EmptyState(
                  icon: Icons.search_off,
                  message: 'No businesses match.',
                )
              else ...[
                RowGroup(
                  children: [
                    for (final row in _rows.rows)
                      ListRowTile(
                        leading: InitialTile(
                          row['business_name']?.toString() ?? '',
                        ),
                        title: '${row['business_name']} · ${row['owner_name']}',
                        subtitle: [
                          row['email'] ?? '',
                          row['mobile'] ?? '',
                          '${row['plan_name']}',
                          'last invoice ${screenDate(parseStoredDate(row['last_invoice']))}',
                          'last login ${screenDate(parseStoredDate(row['last_login']))}',
                        ].where((p) => '$p'.isNotEmpty).join(' · '),
                        trailingTop: SizedBox(
                          width: 120,
                          child: _UsageBar(
                            used: (row['used'] as num?)?.toInt() ?? 0,
                            allowed: (row['allowed'] as num?)?.toInt(),
                          ),
                        ),
                        trailingBottom: StatusChip(
                          _adminStatusWord(
                            row['status']?.toString(),
                            row['quiet'] == true,
                          ),
                        ),
                        onTap: () => widget.onOpenBusiness('${row['user_id']}'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                PagerBar(
                  rows: _rows,
                  onPage: _rows.goTo,
                  onSize: _rows.setSize,
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SimplekColors.skyTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SimplekColors.skyLine),
                ),
                child: Text(
                  'Passwords are never shown, not even to admins. Open a business, '
                  'then Reset password, to give it a temporary password; they set '
                  'a new one at their next login. Every admin action is recorded '
                  'in the Audit log.',
                  style: inter(13.5, FontWeight.w500, SimplekColors.skyText),
                ),
              ),
              if (theme.brightness == Brightness.dark) const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The profile map the PDFs use, from a business_profiles row (no images).
Map<String, String> _profileFromRow(Map<String, dynamic> row) => {
  'ownerName': row['owner_name']?.toString() ?? '',
  'name': row['business_name']?.toString() ?? '',
  'address': row['address']?.toString() ?? '',
  'gstin': row['gstin']?.toString() ?? '',
  'phone': row['phone']?.toString() ?? '',
  'email': row['email']?.toString() ?? '',
  'bankName': row['bank_name']?.toString() ?? '',
  'bankBranch': row['bank_branch']?.toString() ?? '',
  'bankAccount': row['bank_account']?.toString() ?? '',
  'ifsc': row['ifsc']?.toString() ?? '',
  'upiId': row['upi_id']?.toString() ?? '',
  'pan': row['pan']?.toString() ?? '',
  'businessState': row['business_state']?.toString() ?? '',
  'invoicePrefix': row['invoice_prefix']?.toString() ?? 'INV',
  'quotationPrefix': row['quotation_prefix']?.toString() ?? 'QTN',
};

class AdminBusinessPage extends StatefulWidget {
  const AdminBusinessPage({
    super.key,
    required this.businessId,
    required this.onExit,
  });
  final String businessId;
  final VoidCallback onExit;

  @override
  State<AdminBusinessPage> createState() => _AdminBusinessPageState();
}

class _AdminBusinessPageState extends State<AdminBusinessPage> {
  Map<String, dynamic>? _data;
  String? _error;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _adminRpc('admin_business', {
        'p_business': widget.businessId,
      });
      if (mounted) {
        setState(() => _data = Map<String, dynamic>.from(data as Map));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _connectionMessage(error, fallback: '$error'));
      }
    }
  }

  Future<String?> _ask(String title, String label, {String? body}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (body != null) ...[Text(body), const SizedBox(height: 10)],
            LabeledField(
              label: label,
              child: TextField(
                controller: controller,
                maxLines: 3,
                minLines: 1,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialog, controller.text.trim());
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_connectionMessage(error, fallback: '$error'))),
      );
    }
  }

  Future<void> _resetPassword() async {
    final email = _data?['account']?['email'] ?? '';
    final go = await showInvoiceWarning(
      context,
      title: 'Reset the password of $email?',
      body:
          'A temporary password is set and shown to you once. Pass it on by '
          'phone or WhatsApp; they must set a new one at their next login.',
      confirmLabel: 'Reset password',
    );
    if (!go || !mounted) return;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'admin-reset-password',
        body: {'user_id': widget.businessId},
      );
      final password = (response.data as Map?)?['temporary_password']
          ?.toString();
      if (password == null) throw StateError('No password returned');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('Temporary password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('For $email. It is shown only now.'),
              const SizedBox(height: 12),
              SelectableText(
                password,
                style: inter(22, FontWeight.w700, SimplekColors.navy),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: password)),
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to reset the password: $error')),
      );
    }
  }

  Future<void> _changePlan() async {
    final plans = [
      for (final p in await _adminRpc('admin_plans') as List)
        Map<String, dynamic>.from(p as Map),
    ].where((p) => p['active'] == true).toList();
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePlanDialog(
        businessId: widget.businessId,
        plans: plans,
        current: '${_data?['plan']?['plan_code'] ?? 'free'}',
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _supportView() async {
    final name = '${_data?['row']?['business_name'] ?? 'Business'}';
    try {
      await BusinessAccess.view(widget.businessId, name: name, support: true);
      await BusinessSettings.syncFromCloud(clearIfMissing: true);
      invoiceChanges.value++;
      if (!mounted) return;
      DesignSettings.destination.value = 0;
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onExit();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_connectionMessage(error, fallback: '$error'))),
      );
    }
  }

  Future<void> _download() async {
    setState(() => _progress = 'Getting the data…');
    try {
      final data = Map<String, dynamic>.from(
        await _adminRpc('admin_export_business', {
              'p_business': widget.businessId,
            })
            as Map,
      );
      await DataExport.run(
        data: data,
        profile: _profileFromRow(
          Map<String, dynamic>.from((data['business_profile'] as Map?) ?? {}),
        ),
        fileLabel: 'business-${widget.businessId.substring(0, 8)}',
        onProgress: (text) {
          if (mounted) setState(() => _progress = text);
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_connectionMessage(error, fallback: '$error'))),
      );
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    if (data == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Business'),
          actions: const [_AdminBadge(), SizedBox(width: 16)],
        ),
        body: _error != null
            ? _loadError(_error!, _load)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final row = Map<String, dynamic>.from(data['row'] as Map);
    final profile = Map<String, dynamic>.from((data['profile'] as Map?) ?? {});
    final account = Map<String, dynamic>.from((data['account'] as Map?) ?? {});
    final totals = Map<String, dynamic>.from((data['totals'] as Map?) ?? {});
    final plan = Map<String, dynamic>.from((data['plan'] as Map?) ?? {});
    final suspended = data['suspended'] == true;
    final email = '${account['email'] ?? ''}';
    final mobile = '${row['mobile'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    Widget line(String label, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: SelectableText('${value ?? '-'}')),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${row['business_name']}'),
        actions: const [_AdminBadge(), SizedBox(width: 16)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _resetPassword,
                icon: const Icon(Icons.password),
                label: const Text('Reset password'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final reason = await _ask(
                    suspended
                        ? 'Reactivate this business?'
                        : 'Suspend this business?',
                    'Reason',
                    body: suspended
                        ? null
                        : 'They can log in only to a screen saying "Your account is '
                              'paused. Contact support." Their data is untouched.',
                  );
                  if (reason == null) return;
                  await _run(
                    () => _adminRpc('admin_set_suspended', {
                      'p_business': widget.businessId,
                      'p_suspended': !suspended,
                      'p_reason': reason,
                    }),
                    suspended ? 'Reactivated' : 'Suspended',
                  );
                },
                icon: Icon(suspended ? Icons.play_arrow : Icons.pause),
                label: Text(suspended ? 'Reactivate' : 'Suspend'),
              ),
              OutlinedButton.icon(
                onPressed: _supportView,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Support view (read-only)'),
              ),
              OutlinedButton.icon(
                onPressed: _progress == null ? _download : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(_progress ?? 'Download business data'),
              ),
              OutlinedButton.icon(
                onPressed: data['deletion_due'] != null
                    ? null
                    : () async {
                        final go = await showInvoiceWarning(
                          context,
                          title: 'Start deleting this account?',
                          body:
                              'In 30 days the account and all its data are deleted. '
                              'Logging in during that time cancels it.',
                          confirmLabel: 'Start deletion',
                          destructive: true,
                        );
                        if (!go) return;
                        await _run(
                          () => _adminRpc('admin_start_deletion', {
                            'p_business': widget.businessId,
                          }),
                          'Deletion scheduled',
                        );
                      },
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  data['deletion_due'] == null
                      ? 'Start account deletion'
                      : 'Deletion on ${screenDate(parseStoredDate(data['deletion_due']))}',
                ),
              ),
              if (mobile.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:$mobile')),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call'),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://wa.me/${mobile.length == 10 ? '91$mobile' : mobile}',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
              ],
              if (email.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('mailto:$email')),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('Email'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('Summary'),
          SectionCard(
            child: Column(
              children: [
                line('Business', profile['business_name']),
                line('Owner', profile['owner_name']),
                line('Login email', email),
                line('Mobile', row['mobile']),
                line(
                  'GSTIN',
                  (profile['gstin'] ?? '').toString().isEmpty
                      ? 'Not registered'
                      : profile['gstin'],
                ),
                line('Address', profile['address']),
                line(
                  'Contact',
                  [
                    profile['phone'],
                    profile['email'],
                  ].where((v) => '${v ?? ''}'.isNotEmpty).join(' · '),
                ),
                line('Joined', screenDate(parseStoredDate(account['joined']))),
                line(
                  'Last login',
                  screenDate(parseStoredDate(account['last_login'])),
                ),
                line(
                  'Email confirmed',
                  account['email_confirmed'] == true ? 'Yes' : 'No',
                ),
                line(
                  'Last invoice',
                  screenDate(parseStoredDate(row['last_invoice'])),
                ),
                line(
                  'Totals',
                  '${totals['invoices']} invoices (${totals['deleted_invoices']} deleted) · '
                      '${totals['customers']} customers · ${totals['items']} items',
                ),
                line(
                  'Status',
                  _adminStatusWord(
                    row['status']?.toString(),
                    row['quiet'] == true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _MonthBars(
            title: 'Invoices per month',
            months: [
              for (final m in (data['usage_by_month'] as List?) ?? const [])
                Map<String, dynamic>.from(m as Map),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('People'),
          RowGroup(
            children: [
              ListRowTile(
                leading: InitialTile(email),
                title: email,
                subtitle: 'Owner',
              ),
              for (final person in (data['people'] as List?) ?? const [])
                ListRowTile(
                  leading: InitialTile('${person['email']}'),
                  title: '${person['email']}',
                  subtitle:
                      'Accountant · since ${screenDate(parseStoredDate(person['given']))}',
                ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('Plan'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${plan['plan_name']}', style: theme.textTheme.titleLarge),
                Text(
                  'From ${screenDate(parseStoredDate(plan['starts_on']))}'
                  '${plan['ends_on'] == null ? '' : ' to ${screenDate(parseStoredDate(plan['ends_on']))}'}'
                  '${(plan['extra_invoices'] as num? ?? 0) > 0 ? ' · ${plan['extra_invoices']} extra invoices' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                _UsageBar(
                  used: (plan['used'] as num?)?.toInt() ?? 0,
                  allowed: (plan['allowed'] as num?)?.toInt(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _changePlan,
                    child: const Text('Change plan'),
                  ),
                ),
                const SizedBox(height: 8),
                for (final h in (data['plan_history'] as List?) ?? const [])
                  Text(
                    '${screenDate(parseStoredDate(h['changed_at']))}: ${h['plan']} from '
                    '${screenDate(parseStoredDate(h['starts_on']))}'
                    '${h['ends_on'] == null ? '' : ' to ${screenDate(parseStoredDate(h['ends_on']))}'}'
                    '${(h['extra_invoices'] as num? ?? 0) > 0 ? ', +${h['extra_invoices']} invoices' : ''}'
                    ' · ${h['reason']}${h['changed_by'] == null ? '' : ' (${h['changed_by']})'}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionLabel('Admin notes'),
          RowGroup(
            children: [
              ListRowTile(
                leading: const IconTile(Icons.note_add_outlined, size: 40),
                title: 'Add a note',
                showChevron: true,
                onTap: () async {
                  final note = await _ask('Add a private note', 'Note');
                  if (note == null) return;
                  await _run(
                    () => _adminRpc('admin_add_note', {
                      'p_business': widget.businessId,
                      'p_note': note,
                    }),
                    'Note added',
                  );
                },
              ),
              for (final note in (data['notes'] as List?) ?? const [])
                ListRowTile(
                  leading: const IconTile(
                    Icons.sticky_note_2_outlined,
                    tone: TileTone.sky,
                    size: 40,
                  ),
                  title: '${note['note']}',
                  subtitle:
                      '${screenDate(parseStoredDate(note['created_at']))} · ${note['by'] ?? ''}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangePlanDialog extends StatefulWidget {
  const _ChangePlanDialog({
    required this.businessId,
    required this.plans,
    required this.current,
  });
  final String businessId;
  final List<Map<String, dynamic>> plans;
  final String current;

  @override
  State<_ChangePlanDialog> createState() => _ChangePlanDialogState();
}

class _ChangePlanDialogState extends State<_ChangePlanDialog> {
  late String _plan = widget.current;
  DateTime _start = DateUtils.dateOnly(DateTime.now());
  DateTime? _end;
  final _extra = TextEditingController(text: '0');
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _extra.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Give a reason.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _adminRpc('admin_change_plan', {
        'p_business': widget.businessId,
        'p_plan_code': _plan,
        'p_starts_on': DatePeriod.dbDate(_start),
        'p_ends_on': _end == null ? null : DatePeriod.dbDate(_end!),
        'p_extra': int.tryParse(_extra.text.trim()) ?? 0,
        'p_reason': _reason.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = _connectionMessage(error, fallback: '$error');
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change plan'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Plan',
              child: DropdownButtonFormField<String>(
                initialValue: widget.plans.any((p) => p['code'] == _plan)
                    ? _plan
                    : null,
                items: [
                  for (final p in widget.plans)
                    DropdownMenuItem(
                      value: '${p['code']}',
                      child: Text('${p['name']}'),
                    ),
                ],
                onChanged: (value) => setState(() => _plan = value ?? _plan),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final day = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2026),
                        lastDate: DateTime(2100),
                        initialDate: _start,
                      );
                      if (day != null) setState(() => _start = day);
                    },
                    child: Text('Starts ${screenDate(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final day = await showDatePicker(
                        context: context,
                        firstDate: _start,
                        lastDate: DateTime(2100),
                        initialDate: _end ?? _start,
                      );
                      setState(() => _end = day);
                    },
                    child: Text(
                      _end == null ? 'No end date' : 'Ends ${screenDate(_end)}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LabeledField(
              label: 'Extra free invoices',
              optional: true,
              child: TextField(
                controller: _extra,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(height: 10),
            LabeledField(
              label: 'Reason',
              required: true,
              child: TextField(controller: _reason),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}

// --- S3 Users ---------------------------------------------------------------

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  late final PagedRows _rows = PagedRows(_fetch);
  final _search = TextEditingController();
  Timer? _timer;
  String? _role;

  static const _columns = [
    ('email', 'Login email'),
    ('name', 'Name'),
    ('mobile', 'Mobile'),
    ('role', 'Role'),
    ('owns', 'Owner of'),
    ('accountant_for', 'Accountant for'),
    ('joined', 'Joined'),
    ('email_confirmed', 'Email confirmed'),
    ('last_login', 'Last login'),
    ('two_step', 'Two-step login'),
    ('status', 'Status'),
  ];

  @override
  void initState() {
    super.initState();
    _rows.addListener(() {
      if (mounted) setState(() {});
    });
    _rows.restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rows.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _query(int offset, int limit) async =>
      Map<String, dynamic>.from(
        await _adminRpc('admin_users', {
              'p_search': _search.text.trim(),
              'p_role': _role,
              'p_offset': offset,
              'p_limit': limit,
            })
            as Map,
      );

  Future<PageResult> _fetch(int from, int to) async {
    final result = await _query(from, to - from + 1);
    return PageResult([
      for (final r in result['rows'] as List)
        Map<String, dynamic>.from(r as Map),
    ], (result['total'] as num).toInt());
  }

  Future<void> _export(String format) async {
    final result = await _query(0, 5000);
    if (!mounted) return;
    await _exportAdminList(
      context,
      name: 'users',
      format: format,
      rows: [
        for (final r in result['rows'] as List)
          Map<String, dynamic>.from(r as Map),
      ],
      columns: _columns,
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      _AdminHeader(
        'Users',
        actions: [
          OutlinedButton(
            onPressed: () => _export('xlsx'),
            child: const Text('Excel'),
          ),
          OutlinedButton(
            onPressed: () => _export('csv'),
            child: const Text('CSV'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ListSearch(
              controller: _search,
              hint: 'Search email, name, mobile, business',
              onChanged: (_) {
                _timer?.cancel();
                _timer = Timer(
                  const Duration(milliseconds: 350),
                  _rows.restart,
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in const [
                  (null, 'Everyone'),
                  ('owner', 'Owners'),
                  ('accountant', 'Accountants'),
                  ('none', 'No business yet'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _role == value,
                    onSelected: (_) {
                      setState(() => _role = value);
                      _rows.restart();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_rows.error != null && _rows.rows.isEmpty)
              _loadError(
                _connectionMessage(_rows.error!, fallback: '${_rows.error}'),
                _rows.refresh,
              )
            else if (_rows.loading && _rows.rows.isEmpty)
              const SkeletonRows()
            else if (_rows.rows.isEmpty)
              const EmptyState(
                icon: Icons.search_off,
                message: 'No logins match.',
              )
            else ...[
              RowGroup(
                children: [
                  for (final row in _rows.rows)
                    ListRowTile(
                      leading: InitialTile('${row['email']}'),
                      title:
                          '${row['email']}${row['super_admin'] == true ? ' · super admin' : ''}',
                      subtitle: [
                        row['name'],
                        row['mobile'],
                        row['role'] == 'owner'
                            ? 'Owner of ${row['owns']}'
                            : row['role'] == 'accountant'
                            ? 'Accountant for ${row['accountant_for']}'
                            : 'No business yet',
                        'joined ${screenDate(parseStoredDate(row['joined']))}',
                        'email ${row['email_confirmed'] == true ? 'confirmed' : 'not confirmed'}',
                        'last login ${screenDate(parseStoredDate(row['last_login']))}',
                        'two-step ${row['two_step'] == true ? 'on' : 'off'}',
                      ].where((p) => '${p ?? ''}'.isNotEmpty).join(' · '),
                      trailingTop: StatusChip(
                        row['status'] == 'suspended' ? 'Suspended' : 'Active',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              PagerBar(rows: _rows, onPage: _rows.goTo, onSize: _rows.setSize),
            ],
          ],
        ),
      ),
    ],
  );
}

// --- S4 Plans -------------------------------------------------------------

class AdminPlansPage extends StatefulWidget {
  const AdminPlansPage({super.key});

  @override
  State<AdminPlansPage> createState() => _AdminPlansPageState();
}

class _AdminPlansPageState extends State<AdminPlansPage> {
  List<Map<String, dynamic>>? _plans;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await _adminRpc('admin_plans') as List;
      if (mounted) {
        setState(
          () => _plans = [
            for (final p in plans) Map<String, dynamic>.from(p as Map),
          ],
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _connectionMessage(error, fallback: '$error'));
      }
    }
  }

  Future<void> _edit(Map<String, dynamic>? plan) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanDialog(plan: plan),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _AdminHeader(
          'Plans',
          actions: [
            FilledButton(
              onPressed: () => _edit(null),
              child: const Text('New plan'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _error != null
              ? _loadError(_error!, _load)
              : plans == null
              ? const SkeletonRows()
              : RowGroup(
                  children: [
                    for (final plan in plans)
                      ListRowTile(
                        leading: IconTile(
                          Icons.sell_outlined,
                          tone: plan['active'] == true
                              ? TileTone.orange
                              : TileTone.navy,
                          size: 40,
                        ),
                        title:
                            '${plan['name']}${plan['active'] == true ? '' : ' (inactive)'}',
                        subtitle: [
                          '${rupees(plan['price_monthly'] as num? ?? 0)} a month',
                          '${rupees(plan['price_yearly'] as num? ?? 0)} a year',
                          plan['invoice_limit'] == null ||
                                  plan['limit_period'] == 'none'
                              ? 'no invoice limit'
                              : '${plan['invoice_limit']} invoices ${plan['limit_period'] == 'monthly' ? 'a month' : 'in total'}',
                          plan['visible'] == true
                              ? 'shown to new sign-ups'
                              : 'hidden',
                          '${plan['businesses']} businesses',
                        ].join(' · '),
                        showChevron: true,
                        onTap: () => _edit(plan),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({this.plan});
  final Map<String, dynamic>? plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final _code = TextEditingController(
    text: '${widget.plan?['code'] ?? ''}',
  );
  late final _name = TextEditingController(
    text: '${widget.plan?['name'] ?? ''}',
  );
  late final _monthly = TextEditingController(
    text: '${widget.plan?['price_monthly'] ?? 0}',
  );
  late final _yearly = TextEditingController(
    text: '${widget.plan?['price_yearly'] ?? 0}',
  );
  late final _limit = TextEditingController(
    text: '${widget.plan?['invoice_limit'] ?? ''}',
  );
  late String _period = '${widget.plan?['limit_period'] ?? 'none'}';
  late bool _visible = widget.plan?['visible'] != false;
  late bool _active = widget.plan?['active'] != false;
  late final Map<String, dynamic> _features = Map<String, dynamic>.from(
    (widget.plan?['features'] as Map?) ??
        {'accountant_access': true, 'tally_export': true},
  );
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _name, _monthly, _yearly, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'Give the plan a code and a name.');
      return;
    }
    try {
      await _adminRpc('admin_save_plan', {
        'p_plan': {
          'code': _code.text.trim().toLowerCase(),
          'name': _name.text.trim(),
          'price_monthly': Paise.parse(_monthly.text).inRupees,
          'price_yearly': Paise.parse(_yearly.text).inRupees,
          'invoice_limit': _period == 'none' ? '' : _limit.text.trim(),
          'limit_period': _period,
          'features': _features,
          'visible': _visible,
          'active': _active,
        },
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      setState(() => _error = _connectionMessage(error, fallback: '$error'));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.plan == null ? 'New plan' : 'Edit ${widget.plan!['name']}',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Code',
              child: TextField(controller: _code, enabled: widget.plan == null),
            ),
            const SizedBox(height: 8),
            LabeledField(
              label: 'Name',
              child: TextField(controller: _name),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Monthly price (₹)',
                    child: TextField(
                      controller: _monthly,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LabeledField(
                    label: 'Yearly price (₹)',
                    child: TextField(
                      controller: _yearly,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LabeledField(
              label: 'Invoice limit',
              child: DropdownButtonFormField<String>(
                initialValue: _period,
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No limit')),
                  DropdownMenuItem(
                    value: 'lifetime',
                    child: Text('In total (lifetime)'),
                  ),
                  DropdownMenuItem(value: 'monthly', child: Text('Each month')),
                ],
                onChanged: (value) => setState(() => _period = value ?? 'none'),
              ),
            ),
            if (_period != 'none') ...[
              const SizedBox(height: 8),
              LabeledField(
                label: 'Invoices',
                child: TextField(
                  controller: _limit,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
            SwitchListTile(
              title: const Text('Accountant access'),
              value: _features['accountant_access'] == true,
              onChanged: (v) =>
                  setState(() => _features['accountant_access'] = v),
            ),
            SwitchListTile(
              title: const Text('Tally export'),
              value: _features['tally_export'] == true,
              onChanged: (v) => setState(() => _features['tally_export'] = v),
            ),
            SwitchListTile(
              title: const Text('Shown to new sign-ups'),
              value: _visible,
              onChanged: (v) => setState(() => _visible = v),
            ),
            SwitchListTile(
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

// --- S5 Integrations ------------------------------------------------------

class AdminIntegrationsPage extends StatefulWidget {
  const AdminIntegrationsPage({super.key, required this.onModeChanged});
  final ValueChanged<bool> onModeChanged;

  @override
  State<AdminIntegrationsPage> createState() => _AdminIntegrationsPageState();
}

class _AdminIntegrationsPageState extends State<AdminIntegrationsPage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _adminRpc('admin_integrations');
      if (mounted) {
        setState(() => _data = Map<String, dynamic>.from(data as Map));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _connectionMessage(error, fallback: '$error'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _AdminHeader('Integrations'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _error != null
              ? _loadError(_error!, _load)
              : data == null
              ? const SkeletonRows()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "These are Simplek's own accounts, not each business's. "
                      'Secrets are stored encrypted on the server and never sent '
                      'to the browser. Nothing is sent yet except the test buttons.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _IntegrationCard(
                      kind: 'email',
                      data: data['email'] as Map?,
                      onSaved: _load,
                    ),
                    const SizedBox(height: 16),
                    _IntegrationCard(
                      kind: 'whatsapp',
                      data: data['whatsapp'] as Map?,
                      onSaved: _load,
                    ),
                    const SizedBox(height: 16),
                    _IntegrationCard(
                      kind: 'razorpay',
                      data: data['razorpay'] as Map?,
                      onSaved: () async {
                        await _load();
                        final mode = _data?['razorpay']?['config']?['mode'];
                        widget.onModeChanged(mode != null && mode != 'live');
                      },
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// One integration's form: plain fields, secret fields shown masked with
/// Replace, Save, and its test button.
class _IntegrationCard extends StatefulWidget {
  const _IntegrationCard({
    required this.kind,
    required this.data,
    required this.onSaved,
  });
  final String kind;
  final Map? data;
  final Future<void> Function() onSaved;

  @override
  State<_IntegrationCard> createState() => _IntegrationCardState();
}

class _IntegrationCardState extends State<_IntegrationCard> {
  static const _url = 'https://vvzaoxhygzhentywnlwr.supabase.co/functions/v1';

  /// (key, label, kind: text | secret | choice:a,b | readonly:value)
  List<(String, String, String)> get _fields => switch (widget.kind) {
    'email' => [
      ('provider', 'Provider', 'choice:smtp,gmail,workspace,brevo,ses,zoho'),
      ('host', 'Host', 'text'),
      ('port', 'Port', 'text'),
      ('security', 'Security', 'choice:ssl,starttls'),
      ('username', 'Username', 'text'),
      ('password', 'Password or API key', 'secret'),
      ('from_name', 'From name', 'text'),
      ('from_address', 'From address', 'text'),
      ('reply_to', 'Reply-To', 'text'),
    ],
    'whatsapp' => [
      ('provider', 'Provider', 'choice:meta,gupshup,interakt,aisensy,wati'),
      ('business_number', 'WhatsApp Business number', 'text'),
      ('phone_number_id', 'Phone number ID', 'text'),
      ('business_account_id', 'WhatsApp Business Account ID', 'text'),
      ('access_token', 'Access token', 'secret'),
      ('verify_token', 'Webhook verify token', 'text'),
      ('webhook_url', 'Webhook URL', 'readonly:$_url/whatsapp-webhook'),
    ],
    _ => [
      ('mode', 'Mode', 'choice:test,live'),
      ('test_key_id', 'Key ID (test)', 'text'),
      ('live_key_id', 'Key ID (live)', 'text'),
      ('key_secret', 'Key secret', 'secret'),
      ('webhook_secret', 'Webhook secret', 'secret'),
      ('webhook_url', 'Webhook URL', 'readonly:$_url/razorpay-webhook'),
    ],
  };

  late final Map<String, dynamic> _config = Map<String, dynamic>.from(
    (widget.data?['config'] as Map?) ?? const {},
  );
  Map get _masked => (widget.data?['secrets'] as Map?) ?? const {};
  final _controllers = <String, TextEditingController>{};
  final _replacing = <String>{};
  late List<Map<String, dynamic>> _templates = [
    for (final t in (_config['templates'] as List?) ?? const [])
      Map<String, dynamic>.from(t as Map),
  ];
  final _testTo = TextEditingController();
  String? _result;
  bool _busy = false;

  TextEditingController _controller(String key) => _controllers.putIfAbsent(
    key,
    () => TextEditingController(text: '${_config[key] ?? ''}'),
  );

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _testTo.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
    'email' => 'Email',
    'whatsapp' => 'WhatsApp',
    _ => 'Razorpay',
  };

  Future<void> _save() async {
    final config = <String, dynamic>{};
    final secrets = <String, dynamic>{};
    for (final (key, _, type) in _fields) {
      if (type == 'secret') {
        final text = _controller(key).text.trim();
        if (_replacing.contains(key) && text.isNotEmpty) secrets[key] = text;
      } else if (type.startsWith('choice:')) {
        config[key] = _config[key] ?? type.substring(7).split(',').first;
      } else if (!type.startsWith('readonly:')) {
        config[key] = _controller(key).text.trim();
      }
    }
    if (widget.kind == 'whatsapp') config['templates'] = _templates;
    if (widget.kind == 'razorpay' &&
        config['mode'] == 'live' &&
        (widget.data?['config'] as Map?)?['mode'] != 'live') {
      final go = await showInvoiceWarning(
        context,
        title: 'Switch Razorpay to Live?',
        body: 'Live mode uses real money. Make sure the live keys are right.',
        confirmLabel: 'Switch to Live',
        destructive: true,
      );
      if (!go) return;
    }
    setState(() => _busy = true);
    try {
      await _adminRpc('admin_save_integration', {
        'p_kind': widget.kind,
        'p_config': config,
        'p_secrets': secrets,
      });
      _replacing.clear();
      for (final key in secrets.keys) {
        _controller(key).clear();
      }
      await widget.onSaved();
      if (mounted) setState(() => _result = 'Saved.');
    } catch (error) {
      if (mounted) {
        setState(() => _result = _connectionMessage(error, fallback: '$error'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'admin-integration-test',
        body: {'kind': widget.kind, 'to': _testTo.text.trim()},
      );
      final body = Map<String, dynamic>.from((response.data as Map?) ?? {});
      setState(
        () => _result =
            '${body['ok'] == true ? '✓ ' : '✗ '}${body['message'] ?? body['error'] ?? ''}',
      );
    } catch (error) {
      setState(() => _result = '✗ $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 10),
          for (final (key, label, type) in _fields) ...[
            if (type.startsWith('choice:'))
              LabeledField(
                label: label,
                child: DropdownButtonFormField<String>(
                  initialValue:
                      _config[key]?.toString() ??
                      type.substring(7).split(',').first,
                  items: [
                    for (final option in type.substring(7).split(','))
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (value) => setState(() => _config[key] = value),
                ),
              )
            else if (type.startsWith('readonly:'))
              LabeledField(
                label: '$label (copy into the provider)',
                child: SelectableText(type.substring(9)),
              )
            else if (type == 'secret')
              LabeledField(
                label: label,
                child: _replacing.contains(key) || _masked[key] == null
                    ? TextField(
                        controller: _controller(key)
                          ..text = _replacing.contains(key)
                              ? _controller(key).text
                              : '',
                        obscureText: true,
                        onChanged: (_) => _replacing.add(key),
                      )
                    : Row(
                        children: [
                          Expanded(child: Text('${_masked[key]}')),
                          TextButton(
                            onPressed: () =>
                                setState(() => _replacing.add(key)),
                            child: const Text('Replace'),
                          ),
                        ],
                      ),
              )
            else
              LabeledField(
                label: label,
                child: TextField(controller: _controller(key)),
              ),
            const SizedBox(height: 8),
          ],
          if (widget.kind == 'email')
            Text(
              'Gmail: personal Gmail needs 2-Step Verification and an App Password, '
              'and has a low daily sending limit; Google Workspace or Brevo suit volume '
              'better. Use port 465 (SSL): the server cannot use port 587. Supabase '
              "login emails (sign-up link) are set separately in the Supabase dashboard: "
              'Authentication → Emails → SMTP Settings; point both at the same account.',
              style: theme.textTheme.bodySmall,
            ),
          if (widget.kind == 'whatsapp') ...[
            const SectionLabel('Templates'),
            for (final (i, t) in _templates.indexed)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${t['name']} · ${t['language']} · ${t['category']} · ${t['status']}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => setState(
                      () => _templates = [..._templates]..removeAt(i),
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            TextButton.icon(
              onPressed: () async {
                final name = TextEditingController();
                final language = TextEditingController(text: 'en');
                var category = 'Utility';
                var status = 'Pending';
                final added = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => StatefulBuilder(
                    builder: (dialog, set) => AlertDialog(
                      title: const Text('Add template'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LabeledField(
                            label: 'Name',
                            child: TextField(controller: name),
                          ),
                          LabeledField(
                            label: 'Language',
                            child: TextField(controller: language),
                          ),
                          LabeledField(
                            label: 'Category',
                            child: DropdownButtonFormField<String>(
                              initialValue: category,
                              items: const [
                                DropdownMenuItem(
                                  value: 'Authentication',
                                  child: Text('Authentication'),
                                ),
                                DropdownMenuItem(
                                  value: 'Utility',
                                  child: Text('Utility'),
                                ),
                                DropdownMenuItem(
                                  value: 'Marketing',
                                  child: Text('Marketing'),
                                ),
                              ],
                              onChanged: (v) =>
                                  set(() => category = v ?? category),
                            ),
                          ),
                          LabeledField(
                            label: 'Approval status',
                            child: DropdownButtonFormField<String>(
                              initialValue: status,
                              items: const [
                                DropdownMenuItem(
                                  value: 'Pending',
                                  child: Text('Pending'),
                                ),
                                DropdownMenuItem(
                                  value: 'Approved',
                                  child: Text('Approved'),
                                ),
                                DropdownMenuItem(
                                  value: 'Rejected',
                                  child: Text('Rejected'),
                                ),
                              ],
                              onChanged: (v) => set(() => status = v ?? status),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                );
                if (added == true && name.text.trim().isNotEmpty) {
                  setState(
                    () => _templates = [
                      ..._templates,
                      {
                        'name': name.text.trim(),
                        'language': language.text.trim(),
                        'category': category,
                        'status': status,
                      },
                    ],
                  );
                }
                name.dispose();
                language.dispose();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add template'),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
              if (widget.kind != 'razorpay')
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _testTo,
                    decoration: InputDecoration(
                      hintText: widget.kind == 'email'
                          ? 'Send a test to (email)'
                          : 'Send a test to (number)',
                    ),
                  ),
                ),
              OutlinedButton(
                onPressed: _busy ? null : _test,
                child: Text(switch (widget.kind) {
                  'email' => 'Send test email',
                  'whatsapp' => 'Send test message',
                  _ => 'Test connection',
                }),
              ),
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            SelectableText(_result!),
          ],
        ],
      ),
    );
  }
}

// --- S6 Audit log and platform settings ------------------------------------

class AdminAuditPage extends StatefulWidget {
  const AdminAuditPage({super.key});

  @override
  State<AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends State<AdminAuditPage> {
  late final PagedRows _rows = PagedRows(_fetch);
  final _search = TextEditingController();
  Timer? _timer;
  String? _action;
  DateTimeRange? _dates;

  static const _actions = [
    'edit',
    'delete',
    'restore',
    'plan_change',
    'password_reset',
    'suspend',
    'reactivate',
    'setting_change',
    'integration_change',
    'support_view',
    'note_added',
    'deletion_started',
    'data_export',
    'list_export',
    'plan_saved',
    'access_given',
    'access_removed',
  ];

  @override
  void initState() {
    super.initState();
    _rows.addListener(() {
      if (mounted) setState(() {});
    });
    _rows.restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rows.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _query(int offset, int limit) async =>
      Map<String, dynamic>.from(
        await _adminRpc('admin_audit_log', {
              'p_search': _search.text.trim(),
              'p_action': _action,
              'p_business': null,
              'p_from': _dates == null
                  ? null
                  : DatePeriod.dbDate(_dates!.start),
              'p_to': _dates == null ? null : DatePeriod.dbDate(_dates!.end),
              'p_offset': offset,
              'p_limit': limit,
            })
            as Map,
      );

  Future<PageResult> _fetch(int from, int to) async {
    final result = await _query(from, to - from + 1);
    return PageResult([
      for (final r in result['rows'] as List)
        Map<String, dynamic>.from(r as Map),
    ], (result['total'] as num).toInt());
  }

  Future<void> _export(String format) async {
    final result = await _query(0, 5000);
    if (!mounted) return;
    await _exportAdminList(
      context,
      name: 'audit_log',
      format: format,
      rows: [
        for (final r in result['rows'] as List)
          Map<String, dynamic>.from(r as Map),
      ],
      columns: const [
        ('created_at', 'When'),
        ('actor', 'Who'),
        ('action', 'Action'),
        ('business', 'Business'),
        ('entity', 'What'),
        ('old_values', 'Old values'),
        ('new_values', 'New values'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      _AdminHeader(
        'Audit log',
        actions: [
          OutlinedButton(
            onPressed: () => _export('xlsx'),
            child: const Text('Excel'),
          ),
          OutlinedButton(
            onPressed: () => _export('csv'),
            child: const Text('CSV'),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Read-only: entries can never be changed or deleted.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _ListSearch(
              controller: _search,
              hint: 'Search who, business, values',
              onChanged: (_) {
                _timer?.cancel();
                _timer = Timer(
                  const Duration(milliseconds: 350),
                  _rows.restart,
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<String?>(
                  value: _action,
                  hint: const Text('All actions'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All actions'),
                    ),
                    for (final a in _actions)
                      DropdownMenuItem(
                        value: a,
                        child: Text(a.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _action = value);
                    _rows.restart();
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    _dates == null
                        ? 'All dates'
                        : '${screenDate(_dates!.start)} – ${screenDate(_dates!.end)}',
                  ),
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2026),
                      lastDate: DateTime.now(),
                      initialDateRange: _dates,
                    );
                    setState(() => _dates = range);
                    _rows.restart();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_rows.error != null && _rows.rows.isEmpty)
              _loadError(
                _connectionMessage(_rows.error!, fallback: '${_rows.error}'),
                _rows.refresh,
              )
            else if (_rows.loading && _rows.rows.isEmpty)
              const SkeletonRows()
            else if (_rows.rows.isEmpty)
              const EmptyState(
                icon: Icons.search_off,
                message: 'Nothing logged yet.',
              )
            else ...[
              RowGroup(
                children: [
                  for (final row in _rows.rows)
                    ListRowTile(
                      leading: const IconTile(
                        Icons.history,
                        tone: TileTone.navy,
                        size: 40,
                      ),
                      title:
                          '${'${row['action']}'.replaceAll('_', ' ')} · ${row['business'] ?? row['entity'] ?? ''}',
                      subtitle:
                          '${screenDate(parseStoredDate(row['created_at']))} '
                          '${'${row['created_at']}'.length > 16 ? '${row['created_at']}'.substring(11, 16) : ''} UTC · '
                          '${row['actor'] ?? 'system'}'
                          '${row['new_values'] == null ? '' : ' · ${jsonEncode(row['new_values'])}'}',
                    ),
                ],
              ),
              const SizedBox(height: 10),
              PagerBar(rows: _rows, onPage: _rows.goTo, onSize: _rows.setSize),
            ],
          ],
        ),
      ),
    ],
  );
}

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  Map<String, dynamic>? _settings;
  String? _error;
  final _bannerText = TextEditingController();
  String _bannerColour = 'sky';
  DateTime? _bannerStart;
  DateTime? _bannerEnd;
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bannerText.dispose();
    _whatsapp.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = Map<String, dynamic>.from(
        await _adminRpc('admin_settings') as Map,
      );
      final banner = Map<String, dynamic>.from(
        (settings['notice_banner'] as Map?) ?? {},
      );
      final contact = Map<String, dynamic>.from(
        (settings['support_contact'] as Map?) ?? {},
      );
      setState(() {
        _settings = settings;
        _bannerText.text = '${banner['text'] ?? ''}';
        _bannerColour = '${banner['colour'] ?? 'sky'}';
        _bannerStart = DateTime.tryParse('${banner['starts_at']}')?.toLocal();
        _bannerEnd = DateTime.tryParse('${banner['ends_at']}')?.toLocal();
        _whatsapp.text = '${contact['whatsapp'] ?? ''}';
        _email.text = '${contact['email'] ?? ''}';
      });
    } catch (error) {
      setState(() => _error = _connectionMessage(error, fallback: '$error'));
    }
  }

  Future<void> _save(String key, Object value) async {
    try {
      await _adminRpc('admin_save_setting', {'p_key': key, 'p_value': value});
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_connectionMessage(error, fallback: '$error'))),
      );
    }
  }

  Future<DateTime?> _pickTime(DateTime? current) async {
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(2026),
      lastDate: DateTime(2100),
      initialDate: current ?? DateTime.now(),
    );
    if (day == null || !mounted) return current;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    return DateTime(
      day.year,
      day.month,
      day.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    String when(DateTime? t) => t == null
        ? 'none'
        : '${screenDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const _AdminHeader('Platform settings'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _error != null
              ? _loadError(_error!, _load)
              : settings == null
              ? const SkeletonRows()
              : FormWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionCard(
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Enforce plan limits'),
                              subtitle: const Text(
                                'Off: usage is counted and shown, nobody is blocked. '
                                'On: a business at its limit cannot create new invoices.',
                              ),
                              value: settings['enforce_plan_limits'] == true,
                              onChanged: (value) async {
                                if (value) {
                                  final go = await showInvoiceWarning(
                                    context,
                                    title: 'Turn on plan limits?',
                                    body:
                                        'Businesses at their limit will be stopped from '
                                        'creating new invoices straight away.',
                                    confirmLabel: 'Turn on',
                                  );
                                  if (!go) return;
                                }
                                await _save('enforce_plan_limits', value);
                              },
                            ),
                            SwitchListTile(
                              title: const Text('New sign-ups open'),
                              value: settings['signups_open'] != false,
                              onChanged: (value) =>
                                  _save('signups_open', value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SectionLabel('Notice banner for all users'),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LabeledField(
                              label: 'Text',
                              optional: true,
                              child: TextField(
                                controller: _bannerText,
                                decoration: const InputDecoration(
                                  hintText: 'Maintenance tonight at 11 pm',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final colour in const [
                                  'sky',
                                  'orange',
                                  'navy',
                                ])
                                  ChoiceChip(
                                    label: Text(colour),
                                    selected: _bannerColour == colour,
                                    onSelected: (_) =>
                                        setState(() => _bannerColour = colour),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () async {
                                    final t = await _pickTime(_bannerStart);
                                    setState(() => _bannerStart = t);
                                  },
                                  child: Text('Starts: ${when(_bannerStart)}'),
                                ),
                                OutlinedButton(
                                  onPressed: () async {
                                    final t = await _pickTime(_bannerEnd);
                                    setState(() => _bannerEnd = t);
                                  },
                                  child: Text('Ends: ${when(_bannerEnd)}'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton(
                                onPressed: () => _save('notice_banner', {
                                  'text': _bannerText.text.trim(),
                                  'colour': _bannerColour,
                                  'starts_at': _bannerStart
                                      ?.toUtc()
                                      .toIso8601String(),
                                  'ends_at': _bannerEnd
                                      ?.toUtc()
                                      .toIso8601String(),
                                }),
                                child: const Text('Save banner'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SectionLabel('Support contact'),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Used by the Upgrade and the "account paused" screens.',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            LabeledField(
                              label: 'WhatsApp number',
                              child: TextField(controller: _whatsapp),
                            ),
                            const SizedBox(height: 8),
                            LabeledField(
                              label: 'Email',
                              child: TextField(controller: _email),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton(
                                onPressed: () => _save('support_contact', {
                                  'whatsapp': _whatsapp.text.trim(),
                                  'email': _email.text.trim(),
                                }),
                                child: const Text('Save contact'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

// --- What every user sees: the account status, plans and the banner ------

/// The account status from my_account_status, read at each login.
class AccountStatus {
  const AccountStatus(this.values);
  static const unknown = AccountStatus({});
  final Map<String, dynamic> values;

  bool get suspended => values['suspended'] == true;
  bool get mustChangePassword => values['must_change_password'] == true;
  Map<String, dynamic> get _settings =>
      Map<String, dynamic>.from((values['settings'] as Map?) ?? const {});
  Map<String, dynamic>? get banner => _settings['notice_banner'] == null
      ? null
      : Map<String, dynamic>.from(_settings['notice_banner'] as Map);
  Map<String, dynamic> get supportContact => Map<String, dynamic>.from(
    (_settings['support_contact'] as Map?) ?? const {},
  );

  static final current = ValueNotifier(unknown);

  static Future<AccountStatus> load() async {
    try {
      final value = await Supabase.instance.client.rpc('my_account_status');
      final status = AccountStatus(
        Map<String, dynamic>.from((value as Map?) ?? const {}),
      );
      current.value = status;
      return status;
    } catch (_) {
      return unknown;
    }
  }
}

/// Opens WhatsApp or email to the support contact (Upgrade, paused).
Future<void> contactSupport(String message) async {
  final contact = AccountStatus.current.value.supportContact;
  final whatsapp = '${contact['whatsapp'] ?? ''}'.replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  final email = '${contact['email'] ?? ''}'.trim();
  final uri = whatsapp.isNotEmpty
      ? Uri.parse(
          'https://wa.me/${whatsapp.length == 10 ? '91$whatsapp' : whatsapp}'
          '?text=${Uri.encodeComponent(message)}',
        )
      : email.isNotEmpty
      ? Uri.parse(
          'mailto:$email?subject=${Uri.encodeComponent('Simplek')}&body=${Uri.encodeComponent(message)}',
        )
      : PrivacyInfo.page('');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// "Your account is paused. Contact support."
class SuspendedPage extends StatelessWidget {
  const SuspendedPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SectionCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconTile(Icons.pause_circle_outline, size: 52),
                const SizedBox(height: 12),
                Text(
                  'Your account is paused. Contact support.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your data is safe and unchanged.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      contactSupport('Hello, my Simplek account is paused.'),
                  child: const Text('Contact support'),
                ),
                TextButton(
                  onPressed: () =>
                      signOutEverywhereOnThisDevice(context, confirm: false),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// "Set a new password", forced after an admin reset (S3).
class ForcedPasswordPage extends StatefulWidget {
  const ForcedPasswordPage({super.key, required this.onDone});
  final Future<void> Function() onDone;

  @override
  State<ForcedPasswordPage> createState() => _ForcedPasswordPageState();
}

class _ForcedPasswordPageState extends State<ForcedPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: _password.text,
          data: {'must_change_password': false, 'password_set': true},
        ),
      );
      await widget.onDone();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is AuthException ? error.message : '$error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: SectionCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set a new password',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You logged in with a temporary password. Choose your own '
                    'to carry on.',
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'New password',
                    child: TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      validator: (value) {
                        final text = value ?? '';
                        if (text.length < 8 ||
                            !RegExp(r'[A-Za-z]').hasMatch(text) ||
                            !RegExp(r'\d').hasMatch(text)) {
                          return 'At least 8 characters, with a letter and a number';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  LabeledField(
                    label: 'Confirm password',
                    child: TextFormField(
                      controller: _confirm,
                      obscureText: true,
                      validator: (value) => value == _password.text
                          ? null
                          : 'Passwords do not match',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save and continue'),
                  ),
                  TextButton(
                    onPressed: () =>
                        signOutEverywhereOnThisDevice(context, confirm: false),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The admin's notice banner above the app, while it is due.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AccountStatus.current,
    builder: (context, status, _) {
      final banner = status.banner;
      final text = '${banner?['text'] ?? ''}'.trim();
      if (text.isEmpty) return const SizedBox.shrink();
      final colour = '${banner?['colour']}';
      final background = switch (colour) {
        'orange' => SimplekColors.orangeTint,
        'navy' => SimplekColors.navy,
        _ => SimplekColors.skyTint,
      };
      final foreground = switch (colour) {
        'orange' => SimplekColors.orangeText,
        'navy' => Colors.white,
        _ => SimplekColors.skyText,
      };
      return Material(
        color: background,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.campaign_outlined, color: foreground, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: inter(14, FontWeight.w600, foreground),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The signed-in owner's plan and usage (my_plan).
abstract final class MyPlan {
  static final current = ValueNotifier<Map<String, dynamic>?>(null);

  static Future<void> load() async {
    try {
      final value = await Supabase.instance.client.rpc('my_plan');
      current.value = value == null
          ? null
          : Map<String, dynamic>.from(value as Map);
    } catch (_) {
      // Shown next time.
    }
  }

  /// "212 of 250 invoices used", or null without a limit.
  static String? usageText(Map<String, dynamic>? plan) {
    final allowed = (plan?['allowed'] as num?)?.toInt();
    if (plan == null || allowed == null) return null;
    final period = plan['limit_period'] == 'monthly' ? ' this month' : '';
    return '${plan['used']} of $allowed ${plan['plan_code'] == 'free' ? 'free ' : ''}invoices used$period';
  }

  /// 0.8 and 0.95 of the limit and above get a notice (S4).
  static bool nearLimit(Map<String, dynamic>? plan) {
    final allowed = (plan?['allowed'] as num?)?.toInt();
    if (plan == null || allowed == null || allowed == 0) return false;
    return ((plan['used'] as num?)?.toInt() ?? 0) >= (allowed * 0.8).ceil();
  }
}

/// "Your plan: Free · 212 of 250 invoices used" with Upgrade (Settings, Home).
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, this.onlyWhenNear = false});

  /// On Home: shown only from 80% of the limit.
  final bool onlyWhenNear;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: MyPlan.current,
    builder: (context, plan, _) {
      if (plan == null || BusinessAccess.readOnly) {
        return const SizedBox.shrink();
      }
      if (onlyWhenNear && !MyPlan.nearLimit(plan)) {
        return const SizedBox.shrink();
      }
      final usage = MyPlan.usageText(plan);
      final near = MyPlan.nearLimit(plan);
      final theme = Theme.of(context);
      return Padding(
        padding: onlyWhenNear
            ? const EdgeInsets.fromLTRB(16, 8, 16, 0)
            : EdgeInsets.zero,
        child: SectionCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconTile(
                near
                    ? Icons.warning_amber_rounded
                    : Icons.workspace_premium_outlined,
                tone: near ? TileTone.orange : TileTone.sky,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  onlyWhenNear && usage != null
                      ? "You've used ${usage.replaceFirst(' used', '')}."
                      : 'Your plan: ${plan['plan_name']}${usage == null ? '' : ' · $usage'}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (usage != null)
                TextButton(
                  onPressed: () => contactSupport(
                    'Hello, I would like to upgrade my Simplek plan. ($usage)',
                  ),
                  child: const Text('Upgrade'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// "You've used all 250 free invoices…" with Upgrade / Contact us.
Future<void> showPlanLimitDialog(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Invoice limit reached'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialog);
              contactSupport('Hello, I would like to upgrade my Simplek plan.');
            },
            child: const Text('Upgrade / Contact us'),
          ),
        ],
      ),
    );

/// True for the server's plan-limit refusal.
bool isPlanLimitError(Object error) =>
    '$error'.contains("You've used all") || '$error'.contains('PLAN_LIMIT');
