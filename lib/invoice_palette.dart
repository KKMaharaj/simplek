import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

class InvoicePalette {
  const InvoicePalette(this.id, this.label, this.paper, this.ink);
  final String id;
  final String label;
  final int paper;
  final int ink;
  Color get paperColor => Color(paper);
  Color get inkColor => Color(ink);
  PdfColor get pdfPaper => PdfColor.fromInt(paper);
  PdfColor get pdfInk => PdfColor.fromInt(ink);

  static const options = [
    InvoicePalette('white-red', 'White & red', 0xFFFFFFFF, 0xFF9F1239),
    InvoicePalette('white-blue', 'White & blue', 0xFFFFFFFF, 0xFF1E3A8A),
    InvoicePalette('cream-blue', 'Cream & blue', 0xFFFFF4DC, 0xFF173B67),
    InvoicePalette(
      'yellow-blue',
      'Light yellow & blue',
      0xFFFFF9C4,
      0xFF163A70,
    ),
    InvoicePalette('white-green', 'White & dark green', 0xFFFFFFFF, 0xFF14532D),
  ];

  static InvoicePalette resolve(String? id) =>
      options.firstWhere((option) => option.id == id, orElse: () => options[1]);
}
