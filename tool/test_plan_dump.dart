// Prints the sheets and the ONB / NAV / INV / DOC rows of the test plan.
// Run: dart run tool/test_plan_dump.dart
import 'dart:io';

import 'package:excel_plus/excel_plus.dart';

void main() {
  final excel = Excel.decodeBytes(
    File('docs/Simplek_Test_Plan.xlsx').readAsBytesSync(),
  );
  for (final name in excel.tables.keys) {
    final sheet = excel.tables[name]!;
    stdout.writeln('=== $name (${sheet.maxRows} rows x ${sheet.maxColumns} cols)');
    for (var r = 0; r < sheet.maxRows; r++) {
      final row = sheet.row(r);
      final cells = [for (final c in row) c?.value?.toString() ?? ''];
      final id = cells.isEmpty ? '' : cells.first;
      if (r < 3 ||
          RegExp(r'^(ONB|NAV-008|INV|DOC)').hasMatch(id)) {
        stdout.writeln('$r | ${cells.map((c) => c.replaceAll('\n', ' / ')).join(' | ')}');
      }
    }
  }
}
