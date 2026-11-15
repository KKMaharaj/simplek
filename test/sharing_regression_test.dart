import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/document_sharing.dart';
import 'package:simplek/document_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simplek/document_share');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('document filenames never treat invoice number as a path', () {
    expect(
      documentPdfFilename('invoice', 'INV/2026-27/01'),
      'invoice_INV_2026-27_01.pdf',
    );
    expect(
      documentPdfFilename('invoice', r'../../folder\file'),
      'invoice_.._.._folder_file.pdf',
    );
  });
  test(
    'optional document number allows automatic numbering and rejects unsafe characters',
    () {
      expect(validateDocumentNumber(''), isNull);
      expect(validateDocumentNumber('INV/2026-27/01'), isNull);
      expect(validateDocumentNumber('bad\\path'), isNotNull);
      expect(validateDocumentNumber('A' * 41), isNotNull);
    },
  );
  for (final target in ['share', 'email', 'whatsapp', 'whatsapp_picker']) {
    test(
      '$target receives a PDF attachment, safe filename, message and recipient',
      () async {
        final bytes = Uint8List.fromList([37, 80, 68, 70]);
        await sharePdfAttachment(
          bytes: bytes,
          number: 'INV/2026-27/01',
          subject: 'Invoice',
          body: 'Please find attached',
          target: target,
          recipient: '919876543210',
          android: true,
        );
        expect(calls.single.method, 'share');
        final args = calls.single.arguments as Map;
        expect(args['filename'], 'invoice_INV_2026-27_01.pdf');
        expect(args['bytes'], bytes);
        expect(args['target'], target);
        expect(args['recipient'], '919876543210');
        expect(args['body'], 'Please find attached');
      },
    );
  }
  test('native share failures propagate for visible UI errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'SHARE_FAILED'),
        );
    await expectLater(
      sharePdfAttachment(
        bytes: Uint8List(4),
        number: '01',
        subject: 'Invoice',
        body: '',
        android: true,
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
