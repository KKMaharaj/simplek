// CR-25B B2: server-side pages, date presets and the web address.
// (Totals over all the data are tested on the database in
// supabase/tests/20261127_cr25b_b2_regressions.sql.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simplek/date_presets.dart';
import 'package:simplek/modern_ui.dart';
import 'package:simplek/paging.dart';
import 'package:simplek/url_state.dart';

/// A server with [total] rows numbered from 1; records every request.
class _FakeServer {
  _FakeServer(this.total);
  int total;
  final requests = <(int, int)>[];

  Future<PageResult> fetch(int from, int to) async {
    requests.add((from, to));
    final last = to < total ? to : total - 1;
    return PageResult([
      for (var i = from; i <= last; i++) {'n': i + 1},
    ], total);
  }
}

void main() {
  group('page labels', () {
    test('showing 26–50 of 287', () {
      expect(
        showingLabel(page: 2, size: 25, total: 287),
        'Showing 26–50 of 287',
      );
      expect(
        showingLabel(page: 12, size: 25, total: 287),
        'Showing 276–287 of 287',
      );
      expect(showingLabel(page: 1, size: 25, total: 0), 'No rows');
      expect(pageOfLabel(2, 12), 'Page 2 of 12');
    });

    test('page buttons: first, last and two either side', () {
      expect(pageNumbers(1, 5), [1, 2, 3, 4, 5]);
      expect(pageNumbers(1, 12), [1, 2, 3, 4, null, 12]);
      expect(pageNumbers(6, 12), [1, null, 5, 6, 7, null, 12]);
      expect(pageNumbers(12, 12), [1, null, 9, 10, 11, 12]);
      expect(pageNumbers(13, 20), [1, null, 12, 13, 14, null, 20]);
    });
  });

  group('PagedRows', () {
    test('page 13 of 25 asks for rows 301–325 only', () async {
      final server = _FakeServer(650);
      final rows = PagedRows(server.fetch);
      await rows.goTo(13);
      expect(server.requests.single, (300, 324));
      expect(rows.rows.first['n'], 301);
      expect(rows.rows.length, 25);
      expect(rows.pageCount, 26);
      expect(rows.page, 13);
    });

    test('a page past the end shows the last page', () async {
      final server = _FakeServer(60);
      final rows = PagedRows(server.fetch);
      await rows.goTo(9);
      expect(rows.page, 3);
      expect(rows.rows.map((row) => row['n']), [
        51,
        52,
        53,
        54,
        55,
        56,
        57,
        58,
        59,
        60,
      ]);
    });

    test('phones add pages below each other', () async {
      final server = _FakeServer(60);
      final rows = PagedRows(server.fetch)..appending = true;
      await rows.restart();
      expect(rows.rows.length, 25);
      expect(rows.pagesShown, 1);
      await rows.loadMore();
      await rows.loadMore();
      expect(rows.rows.length, 60);
      expect(rows.pagesShown, 3);
      expect(rows.hasMore, isFalse);
      await rows.loadMore();
      expect(server.requests.length, 3);
    });

    test('a new page size starts again at page 1', () async {
      final server = _FakeServer(287);
      final rows = PagedRows(server.fetch);
      await rows.goTo(4);
      await rows.setSize(100);
      expect(rows.page, 1);
      expect(rows.rows.length, 100);
      expect(rows.pageCount, 3);
    });

    test('a slow old answer never replaces a newer one', () async {
      var call = 0;
      final rows = PagedRows((from, to) async {
        final mine = ++call;
        await Future<void>.delayed(Duration(milliseconds: mine == 1 ? 50 : 1));
        return PageResult([
          {'call': mine},
        ], 1);
      });
      final first = rows.goTo(1);
      final second = rows.goTo(1);
      await Future.wait([first, second]);
      expect(rows.rows.single['call'], 2);
    });
  });

  group('page size per user', () {
    test('is remembered per user and only from the list of sizes', () async {
      SharedPreferences.setMockInitialValues({});
      await ListPrefs.load('user-a');
      expect(ListPrefs.pageSize.value, 25);
      await ListPrefs.set(50);
      await ListPrefs.set(30);
      expect(ListPrefs.pageSize.value, 50);
      await ListPrefs.load('user-b');
      expect(ListPrefs.pageSize.value, 25);
      await ListPrefs.load('user-a');
      expect(ListPrefs.pageSize.value, 50);
      await ListPrefs.load(null);
      expect(ListPrefs.pageSize.value, 25);
    });
  });

  group('search text', () {
    test('filter syntax characters are removed', () {
      expect(searchTerm('  INV/2026-27/24 '), 'INV/2026-27/24');
      expect(searchTerm('a,b(c)"d*e%f:g\\h'), 'a b c d e f g h');
      expect(
        ilikeAny(['invoice_number', 'customer_name'], 'kiran'),
        'invoice_number.ilike."*kiran*",customer_name.ilike."*kiran*"',
      );
    });
  });

  group('date presets', () {
    final now = DateTime(2026, 11, 27, 18, 30);
    DateTimeRange range(DatePreset preset, [DateTime? at]) =>
        DatePeriod.of(preset, now: at ?? now).range!;

    test('today, last 7 days and this month', () {
      expect(range(DatePreset.today).start, DateTime(2026, 11, 27));
      expect(range(DatePreset.today).end, DateTime(2026, 11, 27));
      expect(range(DatePreset.last7Days).start, DateTime(2026, 11, 21));
      expect(range(DatePreset.thisMonth).start, DateTime(2026, 11, 1));
      expect(range(DatePreset.thisMonth).end, DateTime(2026, 11, 30));
    });

    test('quarters and the year follow the financial year', () {
      expect(range(DatePreset.thisQuarter).start, DateTime(2026, 10, 1));
      expect(range(DatePreset.thisQuarter).end, DateTime(2026, 12, 31));
      final february = DateTime(2027, 2, 10);
      expect(
        range(DatePreset.thisQuarter, february).start,
        DateTime(2027, 1, 1),
      );
      expect(
        range(DatePreset.thisQuarter, february).end,
        DateTime(2027, 3, 31),
      );
      expect(range(DatePreset.thisYear).start, DateTime(2026, 4, 1));
      expect(range(DatePreset.thisYear).end, DateTime(2027, 3, 31));
      expect(range(DatePreset.thisYear, february).start, DateTime(2026, 4, 1));
      expect(
        range(DatePreset.thisYear, DateTime(2027, 4, 1)).start,
        DateTime(2027, 4, 1),
      );
    });

    test('kept in the address and read back', () {
      final month = DatePeriod.of(DatePreset.thisMonth, now: now);
      expect(month.toUrl(), {'period': 'this_month', 'from': '', 'to': ''});
      expect(DatePeriod.fromUrl(month.toUrl(), now: now), month);
      final custom = DatePeriod.of(
        DatePreset.custom,
        custom: DateTimeRange(
          start: DateTime(2026, 4, 1),
          end: DateTime(2026, 6, 30),
        ),
      );
      expect(custom.toUrl(), {
        'period': 'custom',
        'from': '2026-04-01',
        'to': '2026-06-30',
      });
      expect(DatePeriod.fromUrl(custom.toUrl()), custom);
      expect(DatePeriod.fromUrl({'period': 'nonsense'}), DatePeriod.all);
      expect(
        DatePeriod.fromUrl({
          'period': 'custom',
          'from': '2026-06-30',
          'to': '2026-04-01',
        }),
        DatePeriod.all,
      );
      expect(DatePeriod.all.toUrl()['period'], '');
    });

    test('labels', () {
      expect(DatePeriod.all.label, 'All dates');
      expect(
        DatePeriod.of(DatePreset.thisMonth, now: now).label,
        'This month · 01 Nov 2026 – 30 Nov 2026',
      );
      expect(
        DatePeriod.of(DatePreset.today, now: now).label,
        'Today · 27 Nov 2026',
      );
    });
  });

  group('web address', () {
    const base = 'https://simplek.pages.dev/app/';
    test('sets the list keys and keeps everything else', () {
      expect(
        withListQuery('$base#/', {'tab': 'invoices', 'page': '3', 'q': ''}),
        '$base?tab=invoices&page=3#/',
      );
      expect(
        withListQuery('$base?code=abc&tab=home&q=old#/', {'tab': 'customers'}),
        '$base?code=abc&tab=customers#/',
      );
      expect(
        withListQuery('$base?signup=1&tab=invoices', {}),
        '$base?signup=1',
      );
      expect(withListQuery(base, {'unknown': 'x'}), base);
    });

    test('phones have no address bar', () {
      expect(UrlState.read(), isEmpty);
      UrlState.replace({'tab': 'invoices'});
    });
  });

  testWidgets('the pager shows the range, sizes and pages', (tester) async {
    final server = _FakeServer(287);
    final rows = PagedRows(server.fetch);
    await rows.goTo(2);
    int? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: simplekTheme(Brightness.light),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: PagerBar(
              rows: rows,
              onPage: (p) => opened = p,
              onSize: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Showing 26–50 of 287'), findsOneWidget);
    expect(find.text('‹ Prev'), findsOneWidget);
    expect(find.text('Next ›'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    await tester.tap(find.text('Next ›'));
    expect(opened, 3);
    await tester.tap(find.text('12'));
    expect(opened, 12);
  });
}
