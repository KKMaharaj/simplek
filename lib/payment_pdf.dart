import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import 'platform/local_files.dart';

Future<pw.Widget?> buildPaymentQr(Map<String, String> profile) async {
  final upi = (profile['upiId'] ?? '').trim();
  pw.MemoryImage? qr;
  if (RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$').hasMatch(upi)) {
    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upi.toLowerCase(),
        if ((profile['name'] ?? '').trim().isNotEmpty)
          'pn': profile['name']!.trim(),
        'cu': 'INR',
      },
    ).toString();
    final data = await QrPainter(
      data: uri,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    ).toImageData(400, format: ui.ImageByteFormat.png);
    if (data != null) qr = pw.MemoryImage(data.buffer.asUint8List());
  } else {
    final bytes = await readLocalFile(profile['qrPath']);
    if (bytes != null) qr = pw.MemoryImage(bytes);
  }
  if (qr == null) return null;
  final logo = pw.MemoryImage(
    (await rootBundle.load(
      'assets/branding/upi-logo.png',
    )).buffer.asUint8List(),
  );
  return pw.SizedBox(
    width: 125,
    child: pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Image(qr, width: 90, height: 90, fit: pw.BoxFit.contain),
        ),
        pw.Text(
          'Scan to pay through UPI',
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 5),
        pw.Image(logo, width: 76, fit: pw.BoxFit.contain),
      ],
    ),
  );
}
