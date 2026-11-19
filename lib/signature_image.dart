import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'platform/local_files.dart';

/// Size of the signature on invoices and quotations, in PDF points.
const signaturePdfWidth = 200.0;
const signaturePdfHeight = 84.0;

/// Crops empty paper around a signature so the ink fills its box on the
/// document. Photos and old drawn signatures have large blank margins, which
/// made the signature print very small. Returns the input if nothing can be
/// trimmed or the image cannot be read.
Future<Uint8List> trimSignatureImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return bytes;
    final width = image.width, height = image.height;
    var left = width, top = height, right = -1, bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (data.getUint8(i + 3) < 24) continue;
        // Near-white pixels are paper, not ink.
        if (data.getUint8(i) > 228 &&
            data.getUint8(i + 1) > 228 &&
            data.getUint8(i + 2) > 228) {
          continue;
        }
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
    if (right < left || bottom < top) return bytes;
    final pad = (width > height ? width : height) ~/ 50 + 2;
    left = (left - pad).clamp(0, width - 1);
    top = (top - pad).clamp(0, height - 1);
    right = (right + pad).clamp(0, width - 1);
    bottom = (bottom + pad).clamp(0, height - 1);
    final cropWidth = right - left + 1, cropHeight = bottom - top + 1;
    if (cropWidth > width * 0.92 && cropHeight > height * 0.92) return bytes;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        cropWidth.toDouble(),
        cropHeight.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
      ui.Paint(),
    );
    final cropped = await recorder.endRecording().toImage(
      cropWidth,
      cropHeight,
    );
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    return png?.buffer.asUint8List() ?? bytes;
  } catch (_) {
    return bytes;
  }
}

final _trimmed = <String, Uint8List>{};

/// Loads the saved signature for a document, trimmed to its ink.
Future<pw.MemoryImage?> loadPdfSignature(String? path) async {
  final bytes = await readLocalFile(path);
  if (bytes == null) return null;
  final key = '$path:${bytes.length}';
  return pw.MemoryImage(_trimmed[key] ??= await trimSignatureImage(bytes));
}

/// The signature area: the signature centred above a rule, then
/// "Authorised signatory". The image keeps its proportions and is never
/// stretched, cut off or pushed to one side.
pw.Widget pdfSignatureBlock(
  pw.MemoryImage? signature, {
  PdfColor lineColor = PdfColors.black,
}) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.center,
  children: [
    pw.Container(
      width: signaturePdfWidth,
      height: signaturePdfHeight,
      alignment: pw.Alignment.bottomCenter,
      child: signature == null
          ? null
          : pw.Image(signature, fit: pw.BoxFit.contain),
    ),
    pw.Container(
      width: signaturePdfWidth,
      margin: const pw.EdgeInsets.only(top: 4),
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 1, color: lineColor)),
      ),
      child: pw.Text('Authorised signatory', textAlign: pw.TextAlign.center),
    ),
  ],
);
