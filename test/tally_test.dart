// Change request 26 Nov 2026, Tally: the app's copy of the standard names
// must match the edge function's (supabase/functions/tally-export/tally.ts),
// so "Standard: …" on Tally settings shows what the file really uses; and
// the help panel. The XML itself is tested in
// supabase/functions/tally-export/tally_test.ts, the data and access rules
// in supabase/tests/20261127_tally_regressions.sql.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/main.dart';
import 'package:simplek/modern_ui.dart';

void main() {
  final server = File(
    'supabase/functions/tally-export/tally.ts',
  ).readAsStringSync();

  test('rate keys and standard names follow the kit pattern', () {
    expect(TallyNames.pct(18), '18');
    expect(TallyNames.pct(2.5), '2.5');
    expect(TallyNames.pct(0.25), '0.25');
    expect(TallyNames.pct(12.0), '12');
    expect(TallyNames.rateDefault(18, 'salesLocal'), 'Sales GST 18% Local');
    expect(TallyNames.rateDefault(5, 'cgst'), 'Output CGST 2.5%');
    expect(TallyNames.rateDefault(12, 'igst'), 'Output IGST 12%');
    expect(
      TallyNames.rateDefault(18, 'serviceInterstate'),
      'Service Sales GST 18% Interstate',
    );
    expect(TallyNames.unitDefault('kgs'), 'Kgs');
    expect(TallyNames.unitDefault('XYZ'), 'Nos');
  });

  test('the app and the edge function use the same standard names', () {
    for (final entry in TallyNames.fixed.entries) {
      expect(server, contains("${entry.key}: '${entry.value}'"));
    }
    for (final entry in TallyNames.units.entries) {
      expect(server, contains("${entry.key}: '${entry.value}'"));
    }
    for (final entry in TallyNames.rateLabels.entries) {
      expect(server, contains("${entry.key}: '${entry.value}'"));
    }
    expect(server, contains(r'`Sales GST ${pct(rate)}% Local`'));
    expect(server, contains(r'`Output CGST ${pct(rate / 2)}%`'));
  });

  testWidgets('the help panel gives the import steps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: simplekTheme(Brightness.light),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: TallyHelpPanel(initiallyExpanded: true),
          ),
        ),
      ),
    );
    expect(find.text('How to import into TallyPrime'), findsOneWidget);
    expect(
      find.textContaining('Gateway of Tally → Import → Transactions'),
      findsOneWidget,
    );
    expect(find.textContaining('must match'), findsOneWidget);
  });

  test('the old one-line Tally export is gone', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, isNot(contains('_exportTallyXml')));
    expect(main, isNot(contains('Export TallyPrime XML')));
    expect(main, contains('Export for Tally'));
  });
}
