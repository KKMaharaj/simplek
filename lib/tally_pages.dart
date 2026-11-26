part of 'main.dart';

// Change request 26 Nov 2026, Tally (T4): Reports → "Export for Tally" and
// "Tally settings". The XML is made on the server by the tally-export edge
// function (the owner's proven kit); these screens show the check summary,
// download the file and edit the names used in Tally. Owners and
// accountants with view access use both (the server checks who may).

/// The standard names, as in supabase/functions/tally-export/tally.ts.
abstract final class TallyNames {
  static const fixed = <String, String>{
    'sales': 'Sales',
    'roundOff': 'Round Off',
    'cash': 'Cash',
    'bank': 'Bank',
    'upi': 'UPI receipts',
    'customersGroup': 'Sundry Debtors',
  };
  static const fixedLabels = <String, String>{
    'sales': 'Sales (no GST)',
    'roundOff': 'Round off',
    'cash': 'Cash',
    'bank': 'Bank',
    'upi': 'UPI receipts',
    'customersGroup': "Customers' group",
  };
  static const rateKeys = [
    'salesLocal',
    'salesInterstate',
    'serviceLocal',
    'serviceInterstate',
    'cgst',
    'sgst',
    'igst',
  ];
  static const rateLabels = <String, String>{
    'salesLocal': 'Sales, within the state',
    'salesInterstate': 'Sales, other states',
    'serviceLocal': 'Service sales, within the state',
    'serviceInterstate': 'Service sales, other states',
    'cgst': 'CGST',
    'sgst': 'SGST',
    'igst': 'IGST',
  };
  static const units = <String, String>{
    'NOS': 'Nos',
    'PCS': 'Pcs',
    'KGS': 'Kgs',
    'GMS': 'Gms',
    'LTR': 'Ltr',
    'MLT': 'Ml',
    'MTR': 'Mtr',
    'CMS': 'Cms',
    'BOX': 'Box',
    'BAG': 'Bag',
    'BTL': 'Btl',
    'DOZ': 'Doz',
    'PAC': 'Pac',
    'SET': 'Set',
    'PRS': 'Prs',
    'ROL': 'Rol',
    'SQF': 'Sqft',
    'SQM': 'Sqm',
    'TON': 'Ton',
    'UNT': 'Unt',
    'OTH': 'Nos',
  };

  /// "18", "2.5": the key the settings use for a rate.
  static String pct(num rate) {
    final fixed = rate.toStringAsFixed(2);
    return fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
  }

  static String rateDefault(num rate, String key) => switch (key) {
    'salesLocal' => 'Sales GST ${pct(rate)}% Local',
    'salesInterstate' => 'Sales GST ${pct(rate)}% Interstate',
    'serviceLocal' => 'Service Sales GST ${pct(rate)}% Local',
    'serviceInterstate' => 'Service Sales GST ${pct(rate)}% Interstate',
    'cgst' => 'Output CGST ${pct(rate / 2)}%',
    'sgst' => 'Output SGST ${pct(rate / 2)}%',
    _ => 'Output IGST ${pct(rate)}%',
  };

  static String unitDefault(String code) => units[code.toUpperCase()] ?? 'Nos';
}

/// "How to import into TallyPrime" (T4.3).
class TallyHelpPanel extends StatelessWidget {
  const TallyHelpPanel({super.key, this.initiallyExpanded = false});
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      'Open TallyPrime and the company these vouchers belong to.',
      'Gateway of Tally → Import → Transactions.',
      'Choose the file you downloaded (Tally_….xml).',
      'Keep "masters included": customers, ledgers, units and stock items '
          'are made if they are missing.',
      'Check the import summary, then Day Book for the vouchers.',
    ];
    return SectionCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        leading: const Icon(Icons.help_outline),
        title: const Text('How to import into TallyPrime'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${i + 1}. ${steps[i]}'),
            ),
          const SizedBox(height: 4),
          Text(
            'The company name in Tally must match "Company name in Tally" in '
            'Tally settings exactly, or Tally refuses the file.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class TallyExportPage extends StatefulWidget {
  const TallyExportPage({super.key, this.period});

  /// The dates Reports was showing; "All dates" starts at This month.
  final DatePeriod? period;

  @override
  State<TallyExportPage> createState() => _TallyExportPageState();
}

class _TallyExportPageState extends State<TallyExportPage> {
  late DatePeriod _period =
      widget.period == null || widget.period!.preset == DatePreset.all
      ? DatePeriod.of(DatePreset.thisMonth)
      : widget.period!;
  bool _sales = true;
  bool _receipts = true;
  bool _loading = false;
  bool _downloading = false;
  String? _error;
  Map<String, dynamic>? _summary;
  bool _showAll = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  List<String> get _kinds => [if (_sales) 'sales', if (_receipts) 'receipts'];

  Future<Map<String, dynamic>> _call({bool download = false}) async {
    final response = await Supabase.instance.client.functions.invoke(
      'tally-export',
      body: {
        'from': _period.fromDb,
        'to': _period.toDb,
        'kinds': _kinds,
        'download': download,
      },
    );
    final data = response.data;
    if (data is! Map || data['xml'] == null) {
      throw StateError(
        data is Map ? '${data['error'] ?? 'No file'}' : 'No file',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  String _message(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        return '${details['error']}';
      }
      return 'Tally export is not available yet (${error.status}).';
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  Future<void> _check() async {
    final request = ++_request;
    if (_kinds.isEmpty) {
      setState(() {
        _summary = null;
        _error = 'Tick Sales or Receipts.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _call();
      if (!mounted || request != _request) return;
      setState(
        () => _summary = Map<String, dynamic>.from(result['summary'] as Map),
      );
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _summary = null;
        _error = _message(error);
      });
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final result = await _call(download: true);
      final filename = '${result['filename'] ?? 'Tally.xml'}';
      final bytes = utf8.encode('${result['xml']}');
      final file = kIsWeb
          ? XFile.fromData(
              Uint8List.fromList(bytes),
              name: filename,
              mimeType: 'application/xml',
            )
          : XFile(
              await writeTempFile(filename, bytes),
              mimeType: 'application/xml',
            );
      await SharePlus.instance.share(
        ShareParams(
          subject: 'Simplek export for Tally',
          text: 'For TallyPrime: ${_period.rangeText}.',
          files: [file],
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$filename is ready. Vouchers marked exported.'),
        ),
      );
      await _check();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _money(dynamic paise) =>
      rupees((paise is num ? paise : num.tryParse('$paise') ?? 0) / 100);

  String _date(dynamic value) =>
      screenDate(DateTime.tryParse('${value ?? ''}')?.toLocal());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _summary;
    final vouchers = summary == null
        ? const <dynamic, dynamic>{}
        : summary['vouchers'] as Map;
    final list = summary == null
        ? const <dynamic>[]
        : (summary['list'] as List? ?? const []);
    final deleted = summary == null
        ? const <dynamic>[]
        : (summary['exportedThenDeleted'] as List? ?? const []);
    final matches = summary?['matchesReports'];
    final total = (vouchers['total'] as num?) ?? 0;

    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: strong
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );

    final shown = _showAll ? list : list.take(20).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export for Tally'),
        actions: [
          IconButton(
            tooltip: 'Tally settings',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TallySettingsPage(),
                ),
              );
              if (mounted) _check();
            },
          ),
        ],
      ),
      body: FormWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'For TallyPrime: Import > Transactions (with masters). Importing '
              'the same vouchers again updates them, without duplicates. '
              'Purchases are entered in Tally directly.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            const SectionLabel('Dates'),
            _PeriodButton(
              period: _period,
              onChanged: (period) {
                setState(
                  () => _period = period.preset == DatePreset.all
                      ? DatePeriod.of(DatePreset.thisYear)
                      : period,
                );
                _check();
              },
            ),
            const SizedBox(height: 16),
            const SectionLabel('What to include'),
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  CheckboxListTile(
                    value: _sales,
                    title: const Text('Sales'),
                    subtitle: const Text('Your invoices, with items and tax'),
                    onChanged: (value) {
                      setState(() => _sales = value ?? false);
                      _check();
                    },
                  ),
                  CheckboxListTile(
                    value: _receipts,
                    title: const Text('Receipts'),
                    subtitle: const Text(
                      'Payments received, one receipt per payment',
                    ),
                    onChanged: (value) {
                      setState(() => _receipts = value ?? false);
                      _check();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Check before downloading'),
            if (_loading)
              const SectionCard(child: SkeletonRows(count: 4))
            else if (_error != null)
              SectionCard(
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            else if (summary != null) ...[
              for (final item in deleted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SectionCard(
                    color: theme.colorScheme.errorContainer,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Invoice ${(item as Map)['number']} was exported '
                            'to Tally on ${_date(item['exportedAt'])} and later '
                            'deleted. Cancel it in Tally too.',
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row('Sales vouchers', '${vouchers['sales'] ?? 0}'),
                    row('Receipt vouchers', '${vouchers['receipts'] ?? 0}'),
                    if (_sales) ...[
                      row(
                        'Quantity sold',
                        plainQuantity(
                          ((summary['quantity'] as Map?)?['sold'] as num?) ?? 0,
                        ),
                      ),
                      const Divider(height: 18),
                      row('Taxable value', _money(summary['taxablePaise'])),
                      row('CGST', _money(summary['cgstPaise'])),
                      row('SGST', _money(summary['sgstPaise'])),
                      row('IGST', _money(summary['igstPaise'])),
                      row(
                        'Sales total',
                        _money(summary['totalPaise']),
                        strong: true,
                      ),
                    ],
                    if (_receipts) ...[
                      const Divider(height: 18),
                      row(
                        'Receipts total',
                        _money(summary['receiptsPaise']),
                        strong: true,
                      ),
                    ],
                    if (matches != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            matches == true
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 20,
                            color: matches == true
                                ? SimplekColors.success
                                : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              matches == true
                                  ? 'Matches Simplek Reports for these dates.'
                                  : 'Does not match Simplek Reports for these '
                                        'dates. Check before importing.',
                              style: TextStyle(
                                color: matches == true
                                    ? null
                                    : theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: total == 0 || _downloading ? null : _download,
                icon: _downloading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_outlined),
                label: Text(
                  total == 0
                      ? 'Nothing to export in these dates'
                      : 'Download for Tally',
                ),
              ),
              const SizedBox(height: 20),
              if (list.isNotEmpty) ...[
                SectionLabel('Vouchers (${list.length})'),
                RowGroup(
                  children: [
                    for (final entry in shown)
                      ListRowTile(
                        leading: IconTile(
                          (entry as Map)['kind'] == 'receipt'
                              ? Icons.payments_outlined
                              : Icons.receipt_long_outlined,
                          size: 40,
                        ),
                        title:
                            '${entry['kind'] == 'receipt' ? 'Receipt' : 'Sales'} '
                            '${entry['number']}',
                        subtitle: [
                          screenDate(DateTime.tryParse('${entry['date']}')),
                          '${entry['party']}',
                          if (entry['exportedAt'] != null)
                            'Already exported on ${_date(entry['exportedAt'])}',
                        ].join(' · '),
                        trailingTop: Text(_money(entry['amountPaise'])),
                      ),
                  ],
                ),
                if (!_showAll && list.length > shown.length)
                  TextButton(
                    onPressed: () => setState(() => _showAll = true),
                    child: Text('Show all ${list.length}'),
                  ),
                const SizedBox(height: 16),
              ],
            ],
            const TallyHelpPanel(),
          ],
        ),
      ),
    );
  }
}

class TallySettingsPage extends StatefulWidget {
  const TallySettingsPage({super.key});

  @override
  State<TallySettingsPage> createState() => _TallySettingsPageState();
}

class _TallySettingsPageState extends State<TallySettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _data = const {};
  List<num> _rates = const [];
  List<String> _units = const [];
  bool _gst = false;
  String _business = '';

  // Field key ("company", "ledgers.cash", "rates.18.cgst", "units.NOS") to
  // its controller, label and standard name.
  final Map<String, TextEditingController> _fields = {};
  final Map<String, String> _labels = {};
  final Map<String, String> _standard = {};
  Map<String, String> _saved = {};
  bool _ledgerLines = false;
  bool _savedLedgerLines = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Supabase.instance.client.rpc('tally_settings_get');
      if (!mounted) return;
      _apply(Map<String, dynamic>.from(data as Map));
      setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Tally settings are not available yet.';
        });
      }
    }
  }

  void _apply(Map<String, dynamic> data) {
    _data = data;
    _gst = data['gst'] == true;
    _business = '${data['business_name'] ?? ''}'.trim();
    _rates =
        ((data['rates'] as List?) ?? const [])
            .map((r) => r is num ? r : num.tryParse('$r') ?? 0)
            .where((r) => r > 0)
            .toList()
          ..sort();
    _units = {
      'NOS',
      ...((data['units'] as List?) ?? const []).map((u) => '$u'.toUpperCase()),
    }.toList()..sort();
    final settings = Map<String, dynamic>.from(
      (data['settings'] as Map?) ?? const {},
    );
    final ledgers = Map<String, dynamic>.from(
      (settings['ledgers'] as Map?) ?? const {},
    );
    final rates = Map<String, dynamic>.from(
      (settings['rates'] as Map?) ?? const {},
    );
    final units = Map<String, dynamic>.from(
      (settings['units'] as Map?) ?? const {},
    );
    String pick(dynamic value, String standard) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? standard : text;
    }

    final values = <String, String>{};
    void field(String key, String label, String standard, dynamic saved) {
      _labels[key] = label;
      _standard[key] = standard;
      values[key] = pick(saved, standard);
    }

    field(
      'company',
      'Company name in Tally',
      _business.isEmpty ? 'Business' : _business,
      settings['company'],
    );
    for (final entry in TallyNames.fixed.entries) {
      if (_gst && entry.key == 'sales') continue;
      field(
        'ledgers.${entry.key}',
        TallyNames.fixedLabels[entry.key]!,
        entry.value,
        ledgers[entry.key],
      );
    }
    if (_gst) {
      for (final rate in _rates) {
        final key = TallyNames.pct(rate);
        final saved = Map<String, dynamic>.from(
          (rates[key] as Map?) ?? const {},
        );
        for (final rateKey in TallyNames.rateKeys) {
          field(
            'rates.$key.$rateKey',
            '${TallyNames.rateLabels[rateKey]} ($key%)',
            TallyNames.rateDefault(rate, rateKey),
            saved[rateKey],
          );
        }
      }
    }
    for (final unit in _units) {
      field(
        'units.$unit',
        'Unit $unit',
        TallyNames.unitDefault(unit),
        units[unit],
      );
    }
    for (final entry in values.entries) {
      (_fields[entry.key] ??= TextEditingController()).text = entry.value;
    }
    _saved = values;
    _ledgerLines = settings['itemsAs'] == 'ledger';
    _savedLedgerLines = _ledgerLines;
  }

  bool get _dirty =>
      _ledgerLines != _savedLedgerLines ||
      _saved.entries.any((e) => _fields[e.key]!.text.trim() != e.value);

  Map<String, dynamic> _settingsFrom(Map<String, String> values, bool lines) {
    final ledgers = <String, String>{};
    final rates = <String, Map<String, String>>{};
    final units = <String, String>{};
    String? company;
    for (final entry in values.entries) {
      // Only names that differ from the standard are stored.
      if (entry.value == _standard[entry.key]) continue;
      final parts = entry.key.split('.');
      switch (parts.first) {
        case 'company':
          company = entry.value;
        case 'ledgers':
          ledgers[parts[1]] = entry.value;
        case 'rates':
          // "rates.2.5.cgst": the rate itself may hold a dot.
          final rate = parts.sublist(1, parts.length - 1).join('.');
          (rates[rate] ??= {})[parts.last] = entry.value;
        case 'units':
          units[parts[1]] = entry.value;
      }
    }
    // Names saved earlier for rates or units not shown now are kept.
    final before = Map<String, dynamic>.from(
      (_data['settings'] as Map?) ?? const {},
    );
    final keptRates = Map<String, dynamic>.from(
      (before['rates'] as Map?) ?? const {},
    )..removeWhere((k, _) => _rates.any((r) => TallyNames.pct(r) == k));
    final keptUnits = Map<String, dynamic>.from(
      (before['units'] as Map?) ?? const {},
    )..removeWhere((k, _) => _units.contains(k));
    return {
      'company': ?company,
      'ledgers': ledgers,
      'rates': {...keptRates, ...rates},
      'units': {...keptUnits, ...units},
      'itemsAs': lines ? 'ledger' : 'stock',
    };
  }

  Future<void> _save({bool reset = false}) async {
    final values = <String, String>{
      for (final entry in _saved.entries)
        entry.key: reset
            ? _standard[entry.key]!
            : _fields[entry.key]!.text.trim().isEmpty
            ? _standard[entry.key]!
            : _fields[entry.key]!.text.trim(),
    };
    final lines = reset ? false : _ledgerLines;
    final changes = [
      for (final entry in values.entries)
        if (entry.value != _saved[entry.key])
          {
            'setting': _labels[entry.key],
            'from': _saved[entry.key],
            'to': entry.value,
          },
      if (lines != _savedLedgerLines)
        {
          'setting': 'Export items as',
          'from': _savedLedgerLines ? 'Ledger lines only' : 'Stock items',
          'to': lines ? 'Ledger lines only' : 'Stock items',
        },
    ];
    if (changes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing to change.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final data = await Supabase.instance.client.rpc(
        'tally_settings_save',
        params: {
          'p_business': null,
          'p_settings': _settingsFrom(values, lines),
          'p_changes': changes,
        },
      );
      if (!mounted) return;
      setState(() => _apply(Map<String, dynamic>.from(data as Map)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reset ? 'Standard names restored.' : 'Saved.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save Tally settings.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buttons() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      FilledButton(
        onPressed: _saving || !_dirty ? null : () => _save(),
        child: const Text('Save changes'),
      ),
      OutlinedButton(
        onPressed: _saving ? null : () => _save(reset: true),
        child: const Text('Reset to standard names'),
      ),
    ],
  );

  Widget _field(String key) {
    final controller = _fields[key]!;
    final standard = _standard[key]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LabeledField(
        label: _labels[key]!,
        child: TextField(
          controller: controller,
          maxLength: 100,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            counterText: '',
            helperText: controller.text.trim() == standard
                ? null
                : 'Standard: $standard',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renames = (_data['renames'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Tally settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : FormWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'The names Simplek uses in the Tally file. Change one only '
                    'if your Tally company already uses a different name for '
                    'it. Every change is logged below.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  _buttons(),
                  const SizedBox(height: 20),
                  const SectionLabel('Company'),
                  _field('company'),
                  const SizedBox(height: 8),
                  const SectionLabel('Ledgers'),
                  for (final key in _saved.keys.where(
                    (k) => k.startsWith('ledgers.'),
                  ))
                    _field(key),
                  if (_gst) ...[
                    const SizedBox(height: 8),
                    for (final rate in _rates) ...[
                      SectionLabel('GST ${TallyNames.pct(rate)}%'),
                      for (final rateKey in TallyNames.rateKeys)
                        _field('rates.${TallyNames.pct(rate)}.$rateKey'),
                    ],
                    if (_rates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'The GST-rate ledgers appear here once you have '
                          'items or invoices with GST.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  const SectionLabel('Units'),
                  for (final unit in _units) _field('units.$unit'),
                  const SizedBox(height: 8),
                  const SectionLabel('Items'),
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      value: _ledgerLines,
                      title: const Text('Ledger lines only'),
                      subtitle: Text(
                        _ledgerLines
                            ? 'Every line goes to the sales ledgers; no stock '
                                  'items are made in Tally.'
                            : 'Standard: goods become stock items in Tally '
                                  '(quantity and rate); services go to the '
                                  'service sales ledgers.',
                      ),
                      onChanged: (value) =>
                          setState(() => _ledgerLines = value),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buttons(),
                  const SizedBox(height: 28),
                  const SectionLabel('Rename log'),
                  if (renames.isEmpty)
                    Text(
                      'No names changed yet.',
                      style: theme.textTheme.bodySmall,
                    )
                  else
                    RowGroup(
                      children: [
                        for (final entry in renames)
                          ListRowTile(
                            leading: const IconTile(
                              Icons.edit_outlined,
                              size: 40,
                            ),
                            title:
                                '${(entry as Map)['setting']}: '
                                '${entry['from']} → ${entry['to']}',
                            subtitle:
                                '${entry['by'] ?? 'Unknown'} · '
                                '${screenDate(DateTime.tryParse('${entry['at']}')?.toLocal())}',
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const TallyHelpPanel(),
                ],
              ),
            ),
    );
  }
}
