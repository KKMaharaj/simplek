part of 'main.dart';

// CR-25B B2: the lists (Invoices, Quotations, Customers, Items and the
// invoices to collect on Record payment) page, search, filter and sort on
// the server. See lib/paging.dart for the page rules.

/// Destination index ↔ the `tab` value in the web address.
const _tabNames = {
  0: 'home',
  1: 'invoices',
  2: 'customers',
  3: 'items',
  4: 'more',
  5: 'quotations',
  6: 'payments',
  7: 'reports',
  8: 'settings',
};

int? _tabIndex(String? name) {
  for (final entry in _tabNames.entries) {
    if (entry.value == name) return entry.key;
  }
  return null;
}

/// Opens the tab named in the web address, then keeps the address's `tab`
/// in step with the tab shown. Call once at start-up.
void _syncTabWithUrl() {
  final start = _tabIndex(UrlState.read()['tab']);
  if (start != null) DesignSettings.destination.value = start;
  DesignSettings.destination.addListener(() {
    // A new tab starts with a clean view: only its name stays.
    UrlState.replace({'tab': _tabNames[DesignSettings.destination.value]!});
  });
}

String _searchTerm(String text) => searchTerm(text);
String _ilikeAny(List<String> columns, String term) => ilikeAny(columns, term);

/// Rows and count of one PostgREST page.
Future<PageResult> _pageOf(
  PostgrestTransformBuilder<PostgrestList> query,
  int from,
  int to,
) async {
  final response = await query.range(from, to).count(CountOption.exact);
  return PageResult(
    List<Map<String, dynamic>>.from(response.data),
    response.count,
  );
}

/// Shared state for a server-side list: the page controller, the delayed
/// search, numbered pages from 600 px or scrolling on below, live refresh,
/// and the web address.
mixin _ServerList<W extends StatefulWidget> on State<W> {
  late final PagedRows rows = PagedRows(
    fetchPage,
    pageSize: ListPrefs.pageSize.value,
  );
  final search = TextEditingController();
  Timer? _searchTimer;
  bool? _numbered;

  /// The `tab` value this list owns in the web address.
  String get urlTab;

  /// The page of rows [from]..[to] for the current search and filters.
  Future<PageResult> fetchPage(int from, int to);

  /// This list's filters and sort for the web address (besides `q` and
  /// `page`). Empty values are left out.
  Map<String, String> get urlFilters => const {};

  /// Reads this list's filters from the web address, before the first load.
  void readUrlFilters(Map<String, String> params) {}

  /// The `page` to open with, when the address belongs to this list.
  int _startPage = 1;

  void initServerList() {
    final params = UrlState.read();
    if (params['tab'] == urlTab) {
      search.text = params['q'] ?? '';
      _startPage = int.tryParse(params['page'] ?? '') ?? 1;
      readUrlFilters(params);
    }
    rows.addListener(_rowsChanged);
    // Saves here and changes from other devices (LiveSync feeds it).
    invoiceChanges.addListener(_liveChange);
  }

  void disposeServerList() {
    _searchTimer?.cancel();
    rows
      ..removeListener(_rowsChanged)
      ..dispose();
    invoiceChanges.removeListener(_liveChange);
    search.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final numbered = MediaQuery.sizeOf(context).width >= numberedPagesFrom;
    if (numbered == _numbered) return;
    final first = _numbered == null;
    _numbered = numbered;
    rows.appending = !numbered;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (numbered) {
        // Opens the page named in the web address the first time.
        if (first) rows.page = _startPage;
        rows.setAppending(false, size: ListPrefs.pageSize.value);
      } else {
        rows.setAppending(true, size: defaultPageSize);
      }
    });
  }

  bool get numbered => _numbered ?? true;

  void _rowsChanged() {
    if (!mounted) return;
    setState(() {});
    if (!rows.loading) writeUrl();
  }

  void _liveChange() {
    if (mounted) rows.refresh();
  }

  /// Puts this list's view in the web address.
  void writeUrl() => UrlState.replace({
    'tab': urlTab,
    'q': search.text.trim(),
    'page': numbered && rows.page > 1 ? '${rows.page}' : '',
    ...urlFilters,
  });

  /// Called as the search text changes: waits for typing to pause.
  void onSearchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), rows.restart);
    setState(() {});
  }

  /// After a filter or sort change: back to page 1.
  void filtersChanged() => rows.restart();

  bool get hasSearch => search.text.trim().isNotEmpty;

  /// The list body: [header] widgets, then the rows (or [empty]), then the
  /// pager (wide) or "loading more" (phones), with pull to refresh.
  Widget pagedListBody({
    required List<Widget> header,
    required List<Widget> Function(List<Map<String, dynamic>> rows) build,
    required Widget empty,
    required Widget noMatch,
    required bool filtered,
    EdgeInsets padding = const EdgeInsets.fromLTRB(16, 0, 16, 96),
    String noun = 'rows',
  }) {
    final theme = Theme.of(context);
    final list = rows.rows;
    final loadingFirst = rows.loading && list.isEmpty && rows.error == null;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!numbered && notification.metrics.extentAfter < 600) {
          rows.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: rows.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [
            ...header,
            if (rows.error != null && list.isEmpty)
              _loadError(
                _connectionMessage(rows.error!, fallback: 'Unable to load.'),
                rows.refresh,
              )
            else if (loadingFirst)
              const SkeletonRows()
            else if (list.isEmpty)
              filtered ? noMatch : empty
            else ...[
              if (!numbered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${rows.total} $noun · '
                    '${pageOfLabel(rows.pagesShown, rows.pageCount)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ...build(list),
              const SizedBox(height: 8),
              if (numbered)
                PagerBar(
                  rows: rows,
                  onPage: rows.goTo,
                  onSize: (size) {
                    ListPrefs.set(size);
                    rows.setSize(size);
                  },
                )
              else if (rows.hasMore)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: rows.loading
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: rows.loadMore,
                            child: const Text('Show more'),
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small sort menu button: the chosen option has a tick.
class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  /// (url value, label).
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (value, label) in options)
          CheckedPopupMenuItem(
            value: value,
            checked: value == selected,
            child: Text(label),
          ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: const Icon(Icons.sort),
      ),
    );
  }
}

/// The period button for Invoices and Reports: "This month · 1 Nov – 30 Nov".
class _PeriodButton extends StatelessWidget {
  const _PeriodButton({required this.period, required this.onChanged});
  final DatePeriod period;
  final ValueChanged<DatePeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Pressable(
            onTap: () async {
              final chosen = await pickDatePeriod(context, period);
              if (chosen != null) onChanged(chosen);
            },
            semanticLabel: 'Dates: ${period.label}',
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: dark ? SimplekColors.darkLine : SimplekColors.skyLine,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: dark ? SimplekColors.sky : SimplekColors.skyText,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      period.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: inter(
                        15,
                        FontWeight.w600,
                        theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        if (period.preset != DatePreset.all) ...[
          const SizedBox(width: 8),
          SquareIconButton(
            icon: Icons.close,
            tooltip: 'Show all dates',
            onPressed: () => onChanged(DatePeriod.all),
          ),
        ],
      ],
    );
  }
}

/// Totals worked out on the server (`dashboard_totals`).
class _Totals {
  const _Totals(this.values);
  static const empty = _Totals({});
  final Map<String, dynamic> values;

  Paise money(String key) => Paise.parse(values[key]);
  int count(String key) => (values[key] as num?)?.toInt() ?? 0;

  static Future<_Totals> load({
    DateTime? from,
    DateTime? to,
    String? customer,
  }) async {
    final result = await Supabase.instance.client.rpc(
      'dashboard_totals',
      params: {
        'p_from': from == null ? null : DatePeriod.dbDate(from),
        'p_to': to == null ? null : DatePeriod.dbDate(to),
        'p_customer': customer,
      },
    );
    return _Totals(Map<String, dynamic>.from(result as Map));
  }
}
