import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/image_editor.dart';
import 'package:simplek/main.dart' show prefixLengthWarning;

Uint8List _pixel(int r, int g, int b, [int a = 255]) =>
    Uint8List.fromList([r, g, b, a]);

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.black,
  );
  final image = await recorder.endRecording().toImage(width, height);
  return (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

void main() {
  test('clean background removes white paper and keeps dark ink', () {
    final white = cleanBackground(_pixel(255, 255, 255), 0.45);
    final ink = cleanBackground(_pixel(20, 30, 60), 0.45);
    expect(white[3], 0);
    expect(ink[3], 255);
  });

  test('a stronger clean also removes light-grey paper', () {
    final grey = _pixel(205, 205, 205);
    expect(cleanBackground(grey, 0)[3], 255);
    expect(cleanBackground(grey, 1)[3], 0);
  });

  testWidgets('rotating a quarter turn swaps width and height', (tester) async {
    await tester.runAsync(() async {
      final rotated = await rotateQuarter(await _png(40, 10), clockwise: true);
      final image = (await (await ui.instantiateImageCodec(
        rotated,
      )).getNextFrame()).image;
      expect(image.width, 10);
      expect(image.height, 40);
    });
  });

  testWidgets('image tile offers draw and upload when empty', (tester) async {
    var uploads = 0;
    var draws = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: BusinessImageTile(
              label: 'Signature',
              path: '',
              onUpload: () => uploads++,
              onDraw: () => draws++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Signature'));
    await tester.pumpAndSettle();
    expect(find.text('Upload a photo'), findsOneWidget);
    expect(find.text('Draw it'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    await tester.tap(find.text('Draw it'));
    await tester.pumpAndSettle();
    expect(draws, 1);
    expect(uploads, 0);
  });

  test('invoice prefixes that break the 16-character GST limit warn', () {
    expect(prefixLengthWarning('INV'), isNull);
    expect(prefixLengthWarning('EHB'), isNull);
    expect(prefixLengthWarning('ABCDE'), isNotNull);
    expect(prefixLengthWarning('SIMPLEK'), contains('16'));
  });
}
