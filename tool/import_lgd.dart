// Builds the State and District master data from a Local Government
// Directory (LGD) download (https://lgdirectory.gov.in, "Download Directory"
// -> Districts, all states). Save the report as CSV first (Excel: File >
// Save As > CSV UTF-8), then run:
//
//   dart run tool/import_lgd.dart <districts.csv> <download date, e.g. 2026-11-26>
//
// Writes:
//   supabase/imports/lgd_states.csv
//   supabase/imports/lgd_districts.csv
//   assets/data/states_districts.json      (bundled with the app)
//   supabase/migrations/20261126000002_seed_states_districts.sql
//
// The 36 states and UTs and their GST codes come from lib/india_states.dart
// (taken from LGD's state list); district rows are matched to them by the
// LGD state code. Nothing is typed by hand.
import 'dart:convert';
import 'dart:io';

import 'package:simplek/india_states.dart';

List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((value) => value.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(char);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((value) => value.isNotEmpty)) rows.add(row);
  return rows;
}

String csvCell(Object value) {
  final text = value.toString();
  return text.contains(RegExp(r'[",\n]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

String sql(String value) => "'${value.replaceAll("'", "''")}'";

/// "SHIVAMOGGA" -> "Shivamogga"; keeps short all-capital words.
String tidy(String value) => value
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .split(' ')
    .map((word) {
      if (word.isEmpty) return word;
      final lower = word.toLowerCase();
      if (['and', 'of', 'the'].contains(lower)) return lower;
      return lower
          .split('-')
          .map((part) => part.isEmpty ? part : part[0].toUpperCase() + part.substring(1))
          .join('-');
    })
    .join(' ')
    .replaceFirstMapped(RegExp('^([a-z])'), (m) => m[1]!.toUpperCase());

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/import_lgd.dart <districts.csv> <YYYY-MM-DD>');
    exit(64);
  }
  final downloaded = args[1];
  var text = File(args[0]).readAsStringSync();
  if (text.startsWith('﻿')) text = text.substring(1);
  final rows = parseCsv(text);
  final headerIndex = rows.indexWhere(
    (row) => row.any((cell) => cell.toLowerCase().contains('district code')),
  );
  if (headerIndex < 0) {
    stderr.writeln('No "District Code" header row found.');
    exit(65);
  }
  final header = [for (final cell in rows[headerIndex]) cell.toLowerCase()];
  int column(bool Function(String name) test) {
    final index = header.indexWhere(test);
    if (index < 0) throw StateError('Missing column in $header');
    return index;
  }

  final stateCode = column((name) => name.contains('state code'));
  final districtCode = column((name) => name.contains('district code'));
  final districtName = column(
    (name) =>
        name.contains('district name') &&
        (name.contains('english') || !name.contains('local')),
  );

  final statesByLgd = {for (final state in indiaStates) state.lgdCode: state};
  final districts = <IndiaState, List<(int, String)>>{};
  final unknown = <String>{};
  for (final row in rows.skip(headerIndex + 1)) {
    if (row.length <= districtName) continue;
    final lgdState = int.tryParse(row[stateCode]);
    final code = int.tryParse(row[districtCode]);
    final name = tidy(row[districtName]);
    if (lgdState == null || code == null || name.isEmpty) continue;
    final state = statesByLgd[lgdState];
    if (state == null) {
      unknown.add(row[stateCode]);
      continue;
    }
    districts.putIfAbsent(state, () => []).add((code, name));
  }
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown LGD state codes: $unknown');
    exit(66);
  }
  final total = districts.values.fold<int>(0, (sum, list) => sum + list.length);
  final missing = indiaStates.where((state) => !districts.containsKey(state));
  if (missing.isNotEmpty) {
    stderr.writeln('States with no districts: ${missing.map((s) => s.name)}');
    exit(67);
  }
  for (final list in districts.values) {
    list.sort((a, b) => a.$2.compareTo(b.$2));
  }

  const source =
      'Local Government Directory (LGD), https://lgdirectory.gov.in, Download Directory: Districts';
  File('supabase/imports/lgd_states.csv').writeAsStringSync(
    [
      'lgd_code,name,gst_state_code,type',
      for (final state in indiaStates)
        [
          state.lgdCode,
          csvCell(state.name),
          state.gstCode,
          state.isUnionTerritory ? 'UT' : 'State',
        ].join(','),
    ].join('\n'),
  );
  File('supabase/imports/lgd_districts.csv').writeAsStringSync(
    [
      'lgd_code,name,state_lgd_code',
      for (final state in indiaStates)
        for (final (code, name) in districts[state]!)
          [code, csvCell(name), state.lgdCode].join(','),
    ].join('\n'),
  );
  Directory('assets/data').createSync(recursive: true);
  File('assets/data/states_districts.json').writeAsStringSync(
    const JsonEncoder.withIndent(' ').convert({
      'source': '$source (downloaded $downloaded)',
      'states': [
        for (final state in indiaStates)
          {
            'lgd_code': state.lgdCode,
            'name': state.name,
            'gst_state_code': state.gstCode,
            'type': state.isUnionTerritory ? 'UT' : 'State',
            'districts': [
              for (final (code, name) in districts[state]!)
                {'lgd_code': code, 'name': name},
            ],
          },
      ],
    }),
  );
  final seed = StringBuffer()
    ..writeln('-- States and districts from $source,')
    ..writeln('-- downloaded $downloaded. Generated by tool/import_lgd.dart;')
    ..writeln('-- do not edit by hand. Safe to run again: rows are upserted.')
    ..writeln('begin;')
    ..writeln(
      'insert into public.states (lgd_code, name, gst_state_code, type) values',
    )
    ..writeln(
      [
        for (final state in indiaStates)
          '  (${state.lgdCode}, ${sql(state.name)}, ${sql(state.gstCode)}, '
              '${sql(state.isUnionTerritory ? 'UT' : 'State')})',
      ].join(',\n'),
    )
    ..writeln(
      'on conflict (lgd_code) do update set name = excluded.name, '
      'gst_state_code = excluded.gst_state_code, type = excluded.type;',
    )
    ..writeln('insert into public.districts (lgd_code, name, state_id) values')
    ..writeln(
      [
        for (final state in indiaStates)
          for (final (code, name) in districts[state]!)
            '  ($code, ${sql(name)}, (select id from public.states where lgd_code = ${state.lgdCode}))',
      ].join(',\n'),
    )
    ..writeln(
      'on conflict (lgd_code) do update set name = excluded.name, state_id = excluded.state_id;',
    )
    ..writeln('commit;');
  File(
    'supabase/migrations/20261126000002_seed_states_districts.sql',
  ).writeAsStringSync(seed.toString());
  stdout.writeln(
    'Wrote ${indiaStates.length} states/UTs and $total districts '
    '(LGD download of $downloaded).',
  );
}
