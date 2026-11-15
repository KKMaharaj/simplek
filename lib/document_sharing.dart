import 'dart:io';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

String documentPdfFilename(String kind, String number) =>
    '${kind}_${number.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.pdf';

Future<void> sharePdfAttachment({
  required Uint8List bytes,
  required String number,
  required String subject,
  required String body,
  String kind = 'invoice',
  String target = 'share',
  String recipient = '',
  bool? android,
}) async {
  final filename = documentPdfFilename(kind, number);
  if (android ?? Platform.isAndroid) {
    await const MethodChannel('simplek/document_share').invokeMethod('share', {
      'bytes': bytes,
      'filename': filename,
      'target': target,
      'recipient': recipient,
      'subject': subject,
      'body': body,
    });
  } else {
    final shared = await Printing.sharePdf(
      bytes: bytes,
      filename: filename,
      subject: subject,
      body: body,
    );
    if (!shared) throw StateError('No PDF sharing application is available.');
  }
}
