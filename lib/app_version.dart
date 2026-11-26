import 'package:flutter/material.dart';

/// The app's version, kept in step with `version:` in pubspec.yaml
/// (test/app_version_test.dart fails if they differ).
const appVersion = '1.4.0';
const appBuild = '20261127';

/// "Simplek 1.3.0 (build 20261126)", shown under the login form and at the
/// bottom of Business Settings so testers can see which build they're on.
const appVersionLine = 'Simplek $appVersion (build $appBuild)';

/// The version line in small grey text.
class VersionLine extends StatelessWidget {
  const VersionLine({super.key});
  @override
  Widget build(BuildContext context) => Text(
    appVersionLine,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodySmall,
  );
}
