/// Date filter presets for Invoices and Reports (CR-25B B2): Today, Last 7
/// days, This month, This quarter, This year and Custom, plus "All dates".
///
/// Quarters and the year follow the Indian financial year (April to March),
/// as GST returns do: this quarter is Apr–Jun, Jul–Sep, Oct–Dec or Jan–Mar,
/// and this year runs from 1 April to 31 March.
library;

import 'package:flutter/material.dart';

import 'ui_kit.dart' show screenDate;

enum DatePreset {
  all('All dates', 'all'),
  today('Today', 'today'),
  last7Days('Last 7 days', 'last_7_days'),
  thisMonth('This month', 'this_month'),
  thisQuarter('This quarter', 'this_quarter'),
  thisYear('This year', 'this_year'),
  custom('Custom', 'custom');

  const DatePreset(this.label, this.urlValue);
  final String label;
  final String urlValue;
}

/// A chosen period: a preset and, except for "All dates", its days.
class DatePeriod {
  const DatePeriod._(this.preset, this.range);

  static const all = DatePeriod._(DatePreset.all, null);

  /// [preset] as of [now] (today by default). For [DatePreset.custom] give
  /// [custom].
  factory DatePeriod.of(
    DatePreset preset, {
    DateTime? now,
    DateTimeRange? custom,
  }) {
    final day = DateUtils.dateOnly(now ?? DateTime.now());
    DateTimeRange span(DateTime start, DateTime end) =>
        DateTimeRange(start: start, end: end);
    switch (preset) {
      case DatePreset.all:
        return all;
      case DatePreset.today:
        return DatePeriod._(preset, span(day, day));
      case DatePreset.last7Days:
        return DatePeriod._(
          preset,
          span(DateTime(day.year, day.month, day.day - 6), day),
        );
      case DatePreset.thisMonth:
        return DatePeriod._(
          preset,
          span(
            DateTime(day.year, day.month),
            DateTime(day.year, day.month + 1, 0),
          ),
        );
      case DatePreset.thisQuarter:
        // Financial-year quarters start in April, July, October, January.
        final startMonth = ((day.month - 1) ~/ 3) * 3 + 1;
        return DatePeriod._(
          preset,
          span(
            DateTime(day.year, startMonth),
            DateTime(day.year, startMonth + 3, 0),
          ),
        );
      case DatePreset.thisYear:
        final startYear = day.month >= 4 ? day.year : day.year - 1;
        return DatePeriod._(
          preset,
          span(DateTime(startYear, 4), DateTime(startYear + 1, 3, 31)),
        );
      case DatePreset.custom:
        final range = custom ?? span(day, day);
        return DatePeriod._(
          preset,
          span(DateUtils.dateOnly(range.start), DateUtils.dateOnly(range.end)),
        );
    }
  }

  final DatePreset preset;
  final DateTimeRange? range;

  DateTime? get from => range?.start;
  DateTime? get to => range?.end;

  /// "2026-11-01", for the server and the address bar.
  static String dbDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String? get fromDb => from == null ? null : dbDate(from!);
  String? get toDb => to == null ? null : dbDate(to!);

  /// "1 Nov 2026 – 30 Nov 2026", or "All dates".
  String get rangeText {
    final range = this.range;
    if (range == null) return 'All dates';
    if (DateUtils.isSameDay(range.start, range.end)) {
      return screenDate(range.start);
    }
    return '${screenDate(range.start)} – ${screenDate(range.end)}';
  }

  /// "This month · 1 Nov 2026 – 30 Nov 2026".
  String get label => preset == DatePreset.all || preset == DatePreset.custom
      ? rangeText
      : '${preset.label} · $rangeText';

  /// The address-bar keys: `period`, and `from`/`to` for a custom period.
  Map<String, String> toUrl() => {
    'period': preset == DatePreset.all ? '' : preset.urlValue,
    'from': preset == DatePreset.custom ? fromDb ?? '' : '',
    'to': preset == DatePreset.custom ? toDb ?? '' : '',
  };

  /// Reads [toUrl] back; anything unknown is "All dates".
  static DatePeriod fromUrl(Map<String, String> params, {DateTime? now}) {
    final value = params['period'];
    for (final preset in DatePreset.values) {
      if (preset.urlValue != value) continue;
      if (preset != DatePreset.custom) return DatePeriod.of(preset, now: now);
      final from = DateTime.tryParse(params['from'] ?? '');
      final to = DateTime.tryParse(params['to'] ?? '');
      if (from == null || to == null || to.isBefore(from)) return all;
      return DatePeriod.of(
        preset,
        custom: DateTimeRange(start: from, end: to),
      );
    }
    return all;
  }

  @override
  bool operator ==(Object other) =>
      other is DatePeriod && other.preset == preset && other.range == range;

  @override
  int get hashCode => Object.hash(preset, range);
}

/// Shows the presets; Custom opens a date-range picker. Null when cancelled.
Future<DatePeriod?> pickDatePeriod(
  BuildContext context,
  DatePeriod current,
) async {
  final preset = await showModalBottomSheet<DatePreset>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Show invoices dated',
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            for (final option in DatePreset.values)
              ListTile(
                title: Text(option.label),
                subtitle: option == DatePreset.all
                    ? null
                    : option == DatePreset.custom
                    ? const Text('Pick the first and last day')
                    : Text(DatePeriod.of(option).rangeText),
                trailing: option == current.preset
                    ? const Icon(Icons.check)
                    : null,
                selected: option == current.preset,
                onTap: () => Navigator.of(sheet).pop(option),
              ),
          ],
        ),
      ),
    ),
  );
  if (preset == null || !context.mounted) return null;
  if (preset != DatePreset.custom) return DatePeriod.of(preset);
  final now = DateTime.now();
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - 10),
    lastDate: DateTime(now.year + 1, 12, 31),
    initialDateRange: current.range,
    helpText: 'Select the dates',
    saveText: 'Apply',
  );
  if (range == null) return null;
  return DatePeriod.of(DatePreset.custom, custom: range);
}
