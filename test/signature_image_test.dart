import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/signature_image.dart';
import 'package:simplek/signature_pad.dart';

Future<Uint8List> _png(int width, int height, Rect ink, {Color? paper}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (paper != null) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = paper,
    );
  }
  canvas.drawRect(ink, Paint()..color = const Color(0xFF0B1B3A));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<Size> _size(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  return Size(image.width.toDouble(), image.height.toDouble());
}

void main() {
  testWidgets('a small signature on a large white page is cropped to its ink', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await _png(
        640,
        360,
        const Rect.fromLTWH(250, 150, 120, 40),
        paper: Colors.white,
      );
      final size = await _size(await trimSignatureImage(source));
      expect(size.width, inInclusiveRange(120, 160));
      expect(size.height, inInclusiveRange(40, 80));
    });
  });

  testWidgets('transparent margins are cropped too', (tester) async {
    await tester.runAsync(() async {
      final source = await _png(
        600,
        300,
        const Rect.fromLTWH(40, 200, 200, 60),
      );
      final size = await _size(await trimSignatureImage(source));
      expect(size.width, lessThan(260));
      expect(size.height, lessThan(110));
    });
  });

  testWidgets('an image already filled with ink is returned unchanged', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = await _png(200, 80, const Rect.fromLTWH(0, 0, 200, 80));
      expect(await trimSignatureImage(source), same(source));
    });
  });

  testWidgets('unreadable data is returned unchanged', (tester) async {
    await tester.runAsync(() async {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      expect(await trimSignatureImage(junk), same(junk));
    });
  });

  testWidgets('signature pad fits a 320px phone and enables saving after ink', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SignaturePadDialog())),
    );
    expect(tester.takeException(), isNull);
    FilledButton save() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Use signature'),
    );
    expect(save().onPressed, isNull);
    await tester.drag(find.byType(AspectRatio), const Offset(80, 10));
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(save().onPressed, isNull);
  });
}
