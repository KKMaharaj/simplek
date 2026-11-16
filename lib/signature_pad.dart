import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'platform/local_files.dart';

/// A large signing area. Returns the path of a PNG cropped tightly to the ink
/// on a transparent background, so it prints at full size on documents.
class SignaturePadDialog extends StatefulWidget {
  const SignaturePadDialog({super.key});

  @override
  State<SignaturePadDialog> createState() => _SignaturePadDialogState();
}

const _strokeWidth = 3.2;

Path _strokePath(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) {
    return path..lineTo(points.first.dx + 0.1, points.first.dy + 0.1);
  }
  for (var i = 1; i < points.length - 1; i++) {
    final mid = (points[i] + points[i + 1]) / 2;
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  return path..lineTo(points.last.dx, points.last.dy);
}

Paint _inkPaint() => Paint()
  ..color = const Color(0xFF0B1B3A)
  ..style = PaintingStyle.stroke
  ..strokeWidth = _strokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _SignaturePadDialogState extends State<SignaturePadDialog> {
  final List<List<Offset>> _strokes = [];
  bool _saving = false;

  Future<void> _save() async {
    if (_strokes.isEmpty || _saving) return;
    setState(() => _saving = true);
    var bounds = Rect.fromPoints(_strokes.first.first, _strokes.first.first);
    for (final stroke in _strokes) {
      for (final point in stroke) {
        bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
      }
    }
    bounds = bounds.inflate(_strokeWidth + 4);
    // Render at a generous fixed resolution so small signatures stay sharp.
    final scale = (1200 / bounds.width).clamp(2.0, 8.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    for (final stroke in _strokes) {
      canvas.drawPath(_strokePath(stroke), _inkPaint());
    }
    final image = await recorder.endRecording().toImage(
      (bounds.width * scale).ceil(),
      (bounds.height * scale).ceil(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    if (data == null) {
      setState(() => _saving = false);
      return;
    }
    final path = await writeTempFile(
      'simplek_signature_${DateTime.now().millisecondsSinceEpoch}.png',
      data.buffer.asUint8List(),
    );
    if (mounted) Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Draw your signature',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Sign along the line. It prints at full size on documents.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 2.1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: GestureDetector(
                      onPanStart: (details) =>
                          setState(() => _strokes.add([details.localPosition])),
                      onPanUpdate: (details) => setState(
                        () => _strokes.last.add(details.localPosition),
                      ),
                      child: CustomPaint(
                        painter: _SignaturePainter(
                          _strokes,
                          _strokes.fold(0, (sum, s) => sum + s.length),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 8,
                overflowSpacing: 4,
                children: [
                  OverflowBar(
                    overflowAlignment: OverflowBarAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(_strokes.removeLast),
                        icon: const Icon(Icons.undo),
                        label: const Text('Undo'),
                      ),
                      TextButton.icon(
                        onPressed: _strokes.isEmpty
                            ? null
                            : () => setState(_strokes.clear),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                  OverflowBar(
                    spacing: 8,
                    overflowSpacing: 4,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: _strokes.isEmpty || _saving ? null : _save,
                        child: const Text('Use signature'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.strokes, this.pointCount);
  final List<List<Offset>> strokes;
  final int pointCount;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1.2;
    final y = size.height * 0.72;
    canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), guide);
    for (final stroke in strokes) {
      canvas.drawPath(_strokePath(stroke), _inkPaint());
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) =>
      oldDelegate.pointCount != pointCount;
}
