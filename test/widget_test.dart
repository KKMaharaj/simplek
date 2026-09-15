import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/main.dart';

void main() {
  testWidgets('application shell renders its configured home', (tester) async {
    await tester.pumpWidget(
      const MyApp(home: Scaffold(body: Text('Simplek smoke test'))),
    );

    expect(find.text('Simplek smoke test'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
