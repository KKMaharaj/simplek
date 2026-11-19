import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';

import 'platform/local_files.dart';

bool _isUpiId(String value) =>
    RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$').hasMatch(value.trim());

/// The UPI payment link encoded in the QR. [amount] pre-fills the amount in
/// the payer's app; leave it out for an open amount.
String upiPaymentLink(String upiId, String payeeName, {double? amount}) => Uri(
  scheme: 'upi',
  host: 'pay',
  queryParameters: {
    'pa': upiId.trim().toLowerCase(),
    if (payeeName.trim().isNotEmpty) 'pn': payeeName.trim(),
    if (amount != null && amount > 0) 'am': amount.toStringAsFixed(2),
    'cu': 'INR',
  },
).toString();

/// QR image for the business: generated from its UPI ID when it has one,
/// otherwise the QR image it uploaded. Null when it has neither.
Future<pw.MemoryImage?> paymentQrImage(
  Map<String, String> profile, {
  double? amount,
}) async {
  final upi = (profile['upiId'] ?? '').trim();
  if (_isUpiId(upi)) {
    final data = await QrPainter(
      data: upiPaymentLink(upi, profile['name'] ?? '', amount: amount),
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: true,
    ).toImageData(400, format: ui.ImageByteFormat.png);
    return data == null ? null : pw.MemoryImage(data.buffer.asUint8List());
  }
  final bytes = await readLocalFile(profile['qrPath']);
  return bytes == null ? null : pw.MemoryImage(bytes);
}

Uint8List? _upiLogo;

Future<pw.MemoryImage> upiLogoImage() async => pw.MemoryImage(
  _upiLogo ??= (await rootBundle.load(
    'assets/branding/upi-logo.png',
  )).buffer.asUint8List(),
);

/// A self-contained QR block (QR, caption, UPI logo).
Future<pw.Widget?> buildPaymentQr(Map<String, String> profile) async {
  final qr = await paymentQrImage(profile);
  if (qr == null) return null;
  final logo = await upiLogoImage();
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
