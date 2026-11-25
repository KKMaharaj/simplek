part of 'main.dart';

// The item and customer picker (CR-25 change 7, UI-25 "Item and customer
// picker"). It replaces the inline autocomplete dropdown, whose option taps
// could be lost on the web. Full screen on a phone, a dialog on wider
// screens: a search box, an "+ Add '…'" first row, then the saved records.

/// What the picker hands back.
class _PickResult {
  const _PickResult.record(this.record) : freeText = null;
  const _PickResult.freeText(String text) : record = null, freeText = text;

  /// A saved (or just added / restored) record, with its `id`.
  final Map<String, dynamic>? record;

  /// A name typed for this document only, not saved.
  final String? freeText;
}

/// Everything the picker needs to list, add and restore one kind of record.
class _PickerSource {
  const _PickerSource({
    required this.title,
    required this.searchHint,
    required this.noun,
    required this.load,
    required this.titleFor,
    required this.subtitleFor,
    required this.searchTextFor,
    required this.onAdd,
    this.findArchived,
    this.onRestore,
    this.freeTextLabel,
    this.icon = Icons.inventory_2_outlined,
  });

  final String title;
  final String searchHint;

  /// "item" or "customer", used in "+ Add 'x' as a new item".
  final String noun;
  final Future<List<Map<String, dynamic>>> Function() load;
  final String Function(Map<String, dynamic>) titleFor;
  final String Function(Map<String, dynamic>) subtitleFor;
  final String Function(Map<String, dynamic>) searchTextFor;

  /// Opens the add form with the name filled in; returns the saved row, or
  /// null when the user cancels.
  final Future<Map<String, dynamic>?> Function(
    BuildContext context,
    String name,
  )
  onAdd;

  /// An archived record with exactly this name, if any.
  final Future<Map<String, dynamic>?> Function(String name)? findArchived;

  /// Brings an archived record back; returns the saved row.
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> archived)?
  onRestore;

  /// When set, a row "Use '…' on this document only" lets a name be used
  /// without saving it (as before the picker).
  final String Function(String name)? freeTextLabel;
  final IconData icon;
}

Future<_PickResult?> _showRecordPicker(
  BuildContext context,
  _PickerSource source, {
  String initialQuery = '',
}) {
  final page = _RecordPickerPage(source: source, initialQuery: initialQuery);
  if (MediaQuery.sizeOf(context).width < 600) {
    return Navigator.of(context).push<_PickResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => page),
    );
  }
  return showDialog<_PickResult>(
    context: context,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
        ),
        child: page,
      ),
    ),
  );
}

class _RecordPickerPage extends StatefulWidget {
  const _RecordPickerPage({required this.source, this.initialQuery = ''});
  final _PickerSource source;
  final String initialQuery;

  @override
  State<_RecordPickerPage> createState() => _RecordPickerPageState();
}

class _RecordPickerPageState extends State<_RecordPickerPage> {
  late final _search = TextEditingController(text: widget.initialQuery);
  List<Map<String, dynamic>> _records = const [];
  bool _loading = true;
  String? _loadError;
  bool _busy = false;
  Map<String, dynamic>? _archivedMatch;
  Timer? _archivedTimer;

  _PickerSource get _source => widget.source;
  String get _query => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _load();
    _checkArchived();
  }

  @override
  void dispose() {
    _archivedTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final records = await _source.load();
      if (mounted) setState(() => _records = records);
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = _isOfflineError(error)
              ? 'No internet connection. Connect and tap Retry.'
              : 'Could not load the list. Tap Retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasExactMatch {
    final query = _query.toLowerCase();
    return _records.any(
      (record) => _source.titleFor(record).trim().toLowerCase() == query,
    );
  }

  void _checkArchived() {
    _archivedTimer?.cancel();
    final query = _query;
    if (_source.findArchived == null || query.isEmpty) {
      if (_archivedMatch != null) setState(() => _archivedMatch = null);
      return;
    }
    _archivedTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final match = await _source.findArchived!(query);
        if (mounted && _query == query) setState(() => _archivedMatch = match);
      } catch (_) {
        // Offering "Add" is still correct when the check fails.
      }
    });
  }

  Future<void> _run(Future<Map<String, dynamic>?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await action();
      if (!mounted) return;
      if (saved != null) {
        Navigator.of(context).pop(_PickResult.record(saved));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(
            _isOfflineError(error)
                ? 'No internet connection. Nothing was saved.'
                : 'Could not save: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.toLowerCase();
    final visible = query.isEmpty
        ? _records
        : _records
              .where(
                (record) =>
                    _source.searchTextFor(record).toLowerCase().contains(query),
              )
              .toList();
    final showAdd = _query.isNotEmpty && !_hasExactMatch;
    final archived = showAdd ? _archivedMatch : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            _source.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _source.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                            _checkArchived();
                          },
                        ),
                ),
                onChanged: (_) {
                  setState(() {});
                  _checkArchived();
                },
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [
                  if (showAdd && archived != null && _source.onRestore != null)
                    _PickerActionRow(
                      key: const ValueKey('picker-restore'),
                      icon: Icons.unarchive_outlined,
                      label: "Restore '${_source.titleFor(archived)}'",
                      detail:
                          'It was deleted earlier. Restore it and use it here.',
                      onTap: _busy
                          ? null
                          : () => _run(() => _source.onRestore!(archived)),
                    )
                  else if (showAdd)
                    _PickerActionRow(
                      key: const ValueKey('picker-add'),
                      icon: Icons.add,
                      label: "+ Add '$_query' as a new ${_source.noun}",
                      detail: 'Opens the form with the name filled in.',
                      onTap: _busy
                          ? null
                          : () => _run(() => _source.onAdd(context, _query)),
                    ),
                  if (showAdd && _source.freeTextLabel != null)
                    ListTile(
                      key: const ValueKey('picker-free-text'),
                      leading: const Icon(Icons.edit_note_outlined),
                      title: Text(
                        _source.freeTextLabel!(_query),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(_PickResult.freeText(_query)),
                    ),
                  if (showAdd) const SizedBox(height: 8),
                  if (_loading)
                    for (var i = 0; i < 5; i++) const _SkeletonRow()
                  else if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(_loadError!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _records.isEmpty
                            ? 'Nothing saved yet. Type a name above to add your first ${_source.noun}.'
                            : 'No saved ${_source.noun}s match "$_query".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final record in visible)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: SimplekColors.skyTint,
                          foregroundColor: SimplekColors.navy,
                          child: Icon(_source.icon, size: 20),
                        ),
                        title: Text(
                          _source.titleFor(record),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: _source.subtitleFor(record).isEmpty
                            ? null
                            : Text(
                                _source.subtitleFor(record),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_PickResult.record(record)),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerActionRow extends StatelessWidget {
  const _PickerActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: SimplekColors.orangeTint,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SimplekColors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: SimplekColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: SimplekColors.navy,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: SimplekColors.slate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A grey placeholder row while a list loads.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) {
    final shade = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: shade,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: shade, shape: BoxShape.circle),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(160, 12), const SizedBox(height: 8), bar(100, 10)],
            ),
          ),
        ],
      ),
    );
  }
}

/// The field on a document that opens the picker. Once something is chosen
/// it shows a compact card with the name, details and a Change button.
class _PickedRecordField extends StatelessWidget {
  const _PickedRecordField({
    required this.label,
    required this.placeholder,
    required this.title,
    required this.subtitle,
    required this.onPick,
    required this.emptyError,
    this.icon = Icons.inventory_2_outlined,
  });

  final String label;
  final String placeholder;

  /// The chosen name, or '' when nothing is chosen.
  final String title;
  final String subtitle;
  final VoidCallback onPick;
  final String emptyError;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormField<String>(
      key: ValueKey('$label|$title'),
      initialValue: title,
      validator: (value) => (value ?? '').trim().isEmpty ? emptyError : null,
      builder: (field) {
        final empty = title.trim().isEmpty;
        final border = field.hasError
            ? theme.colorScheme.error
            : theme.colorScheme.outlineVariant;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FieldLabel(label, required: true),
            Material(
              color: empty
                  ? theme.inputDecorationTheme.fillColor
                  : (theme.brightness == Brightness.dark
                        ? SimplekColors.navy2
                        : SimplekColors.skyTint),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: empty ? border : SimplekColors.skyLine),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onPick,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          empty ? Icons.search : icon,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: empty
                              ? Text(
                                  placeholder,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                        ),
                        if (!empty)
                          TextButton(
                            onPressed: onPick,
                            child: const Text('Change'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Products: list, add (opens the product form), restore archived.
_PickerSource _productPickerSource() => _PickerSource(
  title: 'Choose a product or service',
  searchHint: 'Search name, type or unit',
  noun: 'item',
  icon: Icons.inventory_2_outlined,
  load: () async => List<Map<String, dynamic>>.from(
    await Supabase.instance.client
        .from('products')
        .select(_productColumns)
        .eq('is_active', true)
        .order('name')
        .limit(1000),
  ),
  titleFor: (row) => row['name']?.toString() ?? 'Unnamed item',
  subtitleFor: _productDetails,
  searchTextFor: (row) =>
      '${row['name'] ?? ''} ${row['product_type'] ?? ''} ${row['uqc_code'] ?? ''} ${row['hsn_sac_code'] ?? ''}',
  onAdd: (context, name) => Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => AddProductPage(initialName: name, returnRecord: true),
    ),
  ),
  findArchived: (name) async {
    final rows = await Supabase.instance.client
        .from('products')
        .select(_productColumns)
        .eq('is_active', false)
        .ilike('name', name.replaceAll('%', r'\%').replaceAll('_', r'\_'))
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  },
  onRestore: (archived) async => Map<String, dynamic>.from(
    await Supabase.instance.client
        .from('products')
        .update({'is_active': true})
        .eq('id', archived['id'])
        .select(_productColumns)
        .single(),
  ),
  freeTextLabel: (name) => "Use '$name' on this document only (not saved)",
);

const _productColumns =
    'id, name, product_type, selling_price, uqc_code, gst_rate, hsn_sac_code';

/// "SAC 998314 · GST 18% · ₹1,500.00" (GST parts only when registered).
String _productDetails(Map<String, dynamic> row) {
  final gst = BusinessSettings.isGstRegistered.value;
  final code = row['hsn_sac_code']?.toString() ?? '';
  final type = row['product_type']?.toString() == 'service' ? 'SAC' : 'HSN';
  final rate = row['gst_rate'];
  final price = row['selling_price'];
  return [
    if (gst && code.isNotEmpty) '$type $code',
    if (gst && rate != null) 'GST ${percent(num.tryParse('$rate') ?? 0)}',
    if (price != null) rupees(num.tryParse('$price') ?? 0),
  ].join(' · ');
}

/// Customers: list, add (opens the customer form), restore archived.
_PickerSource _customerPickerSource() => _PickerSource(
  title: 'Choose a customer',
  searchHint: BusinessSettings.isGstRegistered.value
      ? 'Search name, mobile or GSTIN'
      : 'Search name or mobile',
  noun: 'customer',
  icon: Icons.person_outline,
  load: () async => List<Map<String, dynamic>>.from(
    await Supabase.instance.client
        .from('customers')
        .select(_customerColumns)
        .eq('is_active', true)
        .order('name')
        .limit(1000),
  ),
  titleFor: (row) => row['name']?.toString() ?? 'Unnamed customer',
  subtitleFor: _customerDetails,
  searchTextFor: (row) =>
      '${row['name'] ?? ''} ${row['phone'] ?? ''} ${row['email'] ?? ''} ${BusinessSettings.isGstRegistered.value ? row['gstin'] ?? '' : ''}',
  onAdd: (context, name) => _showCustomerForm(context, initialName: name),
  findArchived: (name) async {
    final rows = await Supabase.instance.client
        .from('customers')
        .select(_customerColumns)
        .eq('is_active', false)
        .ilike('name', name.replaceAll('%', r'\%').replaceAll('_', r'\_'))
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  },
  onRestore: (archived) async => Map<String, dynamic>.from(
    await Supabase.instance.client
        .from('customers')
        .update({'is_active': true})
        .eq('id', archived['id'])
        .select(_customerColumns)
        .single(),
  ),
  freeTextLabel: (name) => "Use '$name' without saving a customer",
);

const _customerColumns = 'id, name, phone, email, gstin, state, address';

String _customerDetails(Map<String, dynamic> row) => [
  row['phone']?.toString() ?? '',
  if (BusinessSettings.isGstRegistered.value) row['gstin']?.toString() ?? '',
].where((part) => part.trim().isNotEmpty).join(' · ');

/// Place of supply for a new document (CR-25 change 6, 2a): the state from
/// the customer's GSTIN, else the customer's saved state, else the business
/// state.
String placeOfSupplyFor({
  required String customerGstin,
  required String customerState,
  required String businessState,
}) {
  final fromGstin = _gstinState(customerGstin.trim().toUpperCase());
  if (fromGstin != null) return fromGstin;
  final saved = stateNamed(customerState)?.name;
  if (saved != null) return saved;
  return stateNamed(businessState)?.name ?? businessState.trim();
}

/// The optional short description on invoices and quotations (CR-25
/// change 9): up to 300 characters with a counter, growing to 3 lines.
class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => LabeledField(
    label: 'Description',
    optional: true,
    child: TextFormField(
      controller: controller,
      minLines: 1,
      maxLines: 3,
      maxLength: 300,
      style: const TextStyle(fontSize: 16),
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText:
            'Optional, e.g. Digital signature, valid 2 years, for Mr. Ravi Kumar',
      ),
    ),
  );
}
