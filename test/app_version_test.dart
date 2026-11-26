import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/app_version.dart';

void main() {
  test('the version line matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\+(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!;
    expect(appVersion, match.group(1));
    expect(appBuild, match.group(2));
    expect(
      appVersionLine,
      'Simplek ${match.group(1)} (build ${match.group(2)})',
    );
  });
}
