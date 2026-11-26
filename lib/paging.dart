/// Server-side pages for the lists (CR-25B B2, BUILD-STANDARDS section 5).
///
/// A list asks the server for one page of rows plus the total count
/// ([PagedRows.fetch] maps to PostgREST `range` with an exact count), so
/// search, filters and totals always cover the whole list, not the rows that
/// happen to be loaded.
///
/// * From 600 px wide: numbered pages, "Showing 26–50 of 287",
///   ‹ Prev 1 2 3 … Next ›, and a choice of 10 / 25 / 50 / 100 rows that is
///   remembered for the signed-in user on this device ([ListPrefs]).
/// * Narrower (phones): pages of 25 load as the list scrolls, with
///   "Page 2 of 12" in the list header.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Search text made safe for a PostgREST `or=(…ilike…)` filter: the
/// characters that filter syntax uses (`, ( ) " * % \ :`) become spaces.
String searchTerm(String text) => text
    .trim()
    .replaceAll(RegExp(r'[,()"*%\\:]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// `a.ilike."*term*",b.ilike."*term*"`: any of [columns] contains [term].
String ilikeAny(List<String> columns, String term) =>
    columns.map((column) => '$column.ilike."*$term*"').join(',');

/// One page of rows and the number of rows that match in all.
class PageResult {
  const PageResult(this.rows, this.total);
  final List<Map<String, dynamic>> rows;
  final int total;
}

/// Loads rows [from]..[to] (inclusive, as PostgREST `range`).
typedef PageFetch = Future<PageResult> Function(int from, int to);

/// Width from which lists show numbered pages instead of scrolling on.
const numberedPagesFrom = 600.0;

/// The page sizes on offer, and the default.
const pageSizes = [10, 25, 50, 100];
const defaultPageSize = 25;

/// The page size chosen by the signed-in user, kept on this device.
abstract final class ListPrefs {
  static final pageSize = ValueNotifier(defaultPageSize);
  static String? _user;

  static String _key(String user) => 'list_page_size_$user';

  /// Reads the choice of [user] (call after sign-in).
  static Future<void> load(String? user) async {
    _user = user;
    if (user == null) {
      pageSize.value = defaultPageSize;
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getInt(_key(user));
    pageSize.value = pageSizes.contains(saved) ? saved! : defaultPageSize;
  }

  static Future<void> set(int size) async {
    if (!pageSizes.contains(size)) return;
    pageSize.value = size;
    final user = _user;
    if (user == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_key(user), size);
  }
}

/// The rows of one list, a page at a time.
class PagedRows extends ChangeNotifier {
  PagedRows(this.fetch, {int pageSize = defaultPageSize, this.page = 1})
    : _size = pageSize;

  PageFetch fetch;
  int page;
  int _size;
  int total = 0;
  List<Map<String, dynamic>> rows = const [];
  bool loading = false;
  Object? error;

  /// True when pages are added below each other (phones) instead of
  /// replacing each other.
  bool appending = false;
  int _request = 0;
  bool _disposed = false;

  int get size => _size;
  int get pageCount => total <= 0 ? 1 : (total + _size - 1) ~/ _size;

  /// Pages loaded so far when appending, else the page shown.
  int get pagesShown => appending
      ? (rows.isEmpty ? 1 : (rows.length + _size - 1) ~/ _size)
      : page;
  bool get hasMore => appending && rows.length < total;

  /// Shows page [number] (from 1), or with [appending] the first pages up to
  /// it. Out-of-range numbers are clamped once the total is known.
  Future<void> goTo(int number) async {
    final request = ++_request;
    loading = true;
    error = null;
    _notify();
    try {
      var target = number < 1 ? 1 : number;
      var result = await fetch((target - 1) * _size, target * _size - 1);
      if (request != _request) return;
      // A page past the end (rows deleted, or an old link): show the last.
      final last = result.total <= 0 ? 1 : (result.total + _size - 1) ~/ _size;
      if (result.rows.isEmpty && target > last) {
        target = last;
        result = await fetch((target - 1) * _size, target * _size - 1);
        if (request != _request) return;
      }
      page = target;
      total = result.total;
      rows = result.rows;
    } catch (e) {
      if (request != _request) return;
      error = e;
    }
    loading = false;
    _notify();
  }

  /// Back to page 1, for a new search, filter or sort.
  Future<void> restart() => goTo(1);

  /// Loads the same page again, keeping the place.
  Future<void> refresh() => appending ? goTo(1) : goTo(page);

  /// Appends the next page (phones).
  Future<void> loadMore() async {
    if (!appending || loading || !hasMore) return;
    final request = ++_request;
    loading = true;
    _notify();
    try {
      final from = rows.length;
      final result = await fetch(from, from + _size - 1);
      if (request != _request) return;
      total = result.total;
      rows = [...rows, ...result.rows];
      page = pagesShown;
    } catch (e) {
      if (request != _request) return;
      error = e;
    }
    loading = false;
    _notify();
  }

  /// Changes the rows per page and goes back to page 1.
  Future<void> setSize(int size) {
    _size = size;
    return goTo(1);
  }

  /// Switches between numbered pages and appending, and reloads page 1.
  Future<void> setAppending(bool value, {int? size}) {
    appending = value;
    if (size != null) _size = size;
    return goTo(value ? 1 : page);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// "Showing 26–50 of 287".
String showingLabel({
  required int page,
  required int size,
  required int total,
}) {
  if (total <= 0) return 'No rows';
  final first = (page - 1) * size + 1;
  final last = (page * size).clamp(first, total);
  return 'Showing $first–$last of $total';
}

/// "Page 2 of 12".
String pageOfLabel(int page, int count) => 'Page $page of $count';

/// The page buttons to show: the first, the last, and two either side of
/// [current]; null marks a gap ("…").
List<int?> pageNumbers(int current, int count) {
  if (count <= 7) return [for (var i = 1; i <= count; i++) i];
  final shown = <int>{1, count};
  for (var i = current - 1; i <= current + 1; i++) {
    if (i > 1 && i < count) shown.add(i);
  }
  if (current <= 3) shown.addAll([2, 3, 4]);
  if (current >= count - 2) shown.addAll([count - 3, count - 2, count - 1]);
  final sorted = shown.toList()..sort();
  final result = <int?>[];
  for (final number in sorted) {
    if (result.isNotEmpty && number - (result.last ?? 0) > 1) result.add(null);
    result.add(number);
  }
  return result;
}

/// The bar under a list on wider screens: "Showing 26–50 of 287", the rows
/// per page, and ‹ Prev 1 2 3 … Next ›.
class PagerBar extends StatelessWidget {
  const PagerBar({
    super.key,
    required this.rows,
    required this.onPage,
    required this.onSize,
  });

  final PagedRows rows;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final count = rows.pageCount;
    final page = rows.page;
    Widget number(int value) {
      final selected = value == page;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 40,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: selected
                  ? (dark ? SimplekColors.orange : SimplekColors.orangeTint)
                  : null,
              foregroundColor: selected
                  ? (dark ? SimplekColors.navy : SimplekColors.orangeText)
                  : theme.colorScheme.onSurface,
            ),
            onPressed: selected || rows.loading ? null : () => onPage(value),
            child: Semantics(
              label: selected ? 'Page $value, current page' : 'Page $value',
              child: Text('$value'),
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      spacing: 12,
      children: [
        Text(
          showingLabel(page: page, size: rows.size, total: rows.total),
          style: theme.textTheme.bodyMedium,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rows', style: theme.textTheme.bodySmall),
            const SizedBox(width: 6),
            DropdownButton<int>(
              value: rows.size,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              items: [
                for (final size in pageSizes)
                  DropdownMenuItem(value: size, child: Text('$size')),
              ],
              onChanged: (size) {
                if (size != null) onSize(size);
              },
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: page > 1 && !rows.loading
                  ? () => onPage(page - 1)
                  : null,
              child: const Text('‹ Prev'),
            ),
            for (final value in pageNumbers(page, count))
              if (value == null)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('…'),
                )
              else
                number(value),
            TextButton(
              onPressed: page < count && !rows.loading
                  ? () => onPage(page + 1)
                  : null,
              child: const Text('Next ›'),
            ),
          ],
        ),
      ],
    );
  }
}
