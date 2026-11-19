/// Crop, rotate and clean an uploaded signature, logo or payment QR image,
/// and the tile that shows one in onboarding and Business Settings.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import 'platform/local_files.dart';
import 'signature_image.dart';

enum BusinessImageKind { logo, signature, qr }

extension on BusinessImageKind {
  String get noun => switch (this) {
    BusinessImageKind.logo => 'logo',
    BusinessImageKind.signature => 'signature',
    BusinessImageKind.qr => 'payment QR',
  };
}

/// Opens the editor full screen. Returns the path of the edited PNG, or null
/// when the user cancels.
Future<String?> editBusinessImage(
  BuildContext context, {
  required Uint8List bytes,
  required BusinessImageKind kind,
  String businessName = '',
}) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) =>
        ImageEditorPage(bytes: bytes, kind: kind, businessName: businessName),
  ),
);

/// Rotates encoded image bytes by a quarter turn and returns PNG bytes.
Future<Uint8List> rotateQuarter(
  Uint8List bytes, {
  required bool clockwise,
}) async {
  final image = (await (await ui.instantiateImageCodec(
    bytes,
  )).getNextFrame()).image;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(image.height / 2, image.width / 2)
    ..rotate((clockwise ? 1 : -1) * math.pi / 2)
    ..translate(-image.width / 2, -image.height / 2);
  canvas.drawImage(image, Offset.zero, Paint());
  final rotated = await recorder.endRecording().toImage(
    image.height,
    image.width,
  );
  final png = await rotated.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// Pixels of an image scaled to at most [maxSide], as RGBA bytes.
class _Pixels {
  _Pixels(this.width, this.height, this.rgba);
  final int width;
  final int height;
  final Uint8List rgba;

  static Future<_Pixels> decode(Uint8List bytes, {int maxSide = 1400}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final source = (await codec.getNextFrame()).image;
    final scale = math.min(
      1.0,
      maxSide / math.max(source.width, source.height),
    );
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return _Pixels(width, height, data!.buffer.asUint8List());
  }
}

/// Makes paper transparent so only the ink remains. [strength] 0 removes
/// only near-white paper; 1 also removes light-grey paper and shadows.
Uint8List cleanBackground(Uint8List rgba, double strength) {
  final out = Uint8List.fromList(rgba);
  final cutoff = 246 - strength.clamp(0, 1) * 96; // 246 .. 150
  const band = 28.0;
  for (var i = 0; i < out.length; i += 4) {
    final lum = 0.299 * out[i] + 0.587 * out[i + 1] + 0.114 * out[i + 2];
    final keep = ((cutoff - lum) / band).clamp(0.0, 1.0);
    out[i + 3] = (out[i + 3] * keep).round();
  }
  return out;
}

Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({
    super.key,
    required this.bytes,
    required this.kind,
    this.businessName = '',
  });

  final Uint8List bytes;
  final BusinessImageKind kind;
  final String businessName;

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _Preset {
  const _Preset(this.label, this.ratio);
  final String label;
  final double? ratio;
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  final _crop = CropController();
  late Uint8List _working = widget.bytes;
  late _Preset _preset = _presets.first;
  bool _cropping = false;
  bool _rotating = false;

  // Finishing step
  _Pixels? _pixels;
  ui.Image? _preview;
  late bool _clean = widget.kind == BusinessImageKind.signature;
  double _strength = 0.45;
  bool _saving = false;
  int _renderToken = 0;

  List<_Preset> get _presets => switch (widget.kind) {
    BusinessImageKind.signature => const [
      _Preset('Signature shape', 200 / 84),
      _Preset('Free', null),
    ],
    BusinessImageKind.logo => const [
      _Preset('Free', null),
      _Preset('Square', 1),
    ],
    BusinessImageKind.qr => const [_Preset('Square', 1), _Preset('Free', null)],
  };

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _rotate(bool clockwise) async {
    if (_rotating) return;
    setState(() => _rotating = true);
    try {
      final rotated = await rotateQuarter(_working, clockwise: clockwise);
      if (!mounted) return;
      setState(() => _working = rotated);
      _crop.image = rotated;
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  void _reset() {
    setState(() {
      _working = widget.bytes;
      _preset = _presets.first;
    });
    _crop.image = widget.bytes;
    _crop.aspectRatio = _preset.ratio;
  }

  Future<void> _onCropped(CropResult result) async {
    if (result is! CropSuccess) {
      setState(() => _cropping = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not crop this image.')),
        );
      }
      return;
    }
    final pixels = await _Pixels.decode(result.croppedImage);
    if (!mounted) return;
    setState(() {
      _pixels = pixels;
      _cropping = false;
    });
    await _render();
  }

  Future<void> _render() async {
    final pixels = _pixels;
    if (pixels == null) return;
    final token = ++_renderToken;
    final rgba = _clean ? cleanBackground(pixels.rgba, _strength) : pixels.rgba;
    final image = await _imageFromRgba(rgba, pixels.width, pixels.height);
    if (!mounted || token != _renderToken) {
      image.dispose();
      return;
    }
    final old = _preview;
    setState(() => _preview = image);
    old?.dispose();
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null || _saving) return;
    setState(() => _saving = true);
    try {
      final png = await preview.toByteData(format: ui.ImageByteFormat.png);
      var bytes = png!.buffer.asUint8List();
      if (widget.kind == BusinessImageKind.signature) {
        bytes = await trimSignatureImage(bytes);
      }
      final path = await writeTempFile(
        'simplek_${widget.kind.name}_${DateTime.now().millisecondsSinceEpoch}.png',
        bytes,
      );
      if (mounted) Navigator.of(context).pop(path);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _pixels == null ? _cropStep(context) : _finishStep(context);

  Widget _cropStep(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Crop ${widget.kind.noun}'),
        actions: [TextButton(onPressed: _reset, child: const Text('Reset'))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Drag the corners or edges to crop. Pinch or scroll to zoom, '
              'and drag to move.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Crop(
                  image: _working,
                  controller: _crop,
                  aspectRatio: _preset.ratio,
                  interactive: true,
                  baseColor: const Color(0xFF1B2133),
                  maskColor: Colors.black.withValues(alpha: 0.55),
                  radius: 4,
                  onCropped: _onCropped,
                  progressIndicator: const CircularProgressIndicator(),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final preset in _presets)
                        ChoiceChip(
                          label: Text(preset.label),
                          selected: preset == _preset,
                          onSelected: (_) {
                            setState(() => _preset = preset);
                            _crop.aspectRatio = preset.ratio;
                          },
                        ),
                      IconButton(
                        tooltip: 'Rotate left',
                        onPressed: _rotating ? null : () => _rotate(false),
                        icon: const Icon(Icons.rotate_left),
                      ),
                      IconButton(
                        tooltip: 'Rotate right',
                        onPressed: _rotating ? null : () => _rotate(true),
                        icon: const Icon(Icons.rotate_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _cropping
                              ? null
                              : () {
                                  setState(() => _cropping = true);
                                  _crop.crop();
                                },
                          child: Text(_cropping ? 'Cropping...' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _finishStep(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    final image = preview == null
        ? const Center(child: CircularProgressIndicator())
        : RawImage(image: preview, fit: BoxFit.contain);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => setState(() {
            _pixels = null;
            _preview?.dispose();
            _preview = null;
          }),
        ),
        title: Text('Check ${widget.kind.noun}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Clean background'),
              subtitle: const Text(
                'Makes white or grey paper transparent so only the ink '
                'prints.',
              ),
              value: _clean,
              onChanged: (value) {
                setState(() => _clean = value);
                _render();
              },
            ),
          ),
          if (_clean) ...[
            const SizedBox(height: 8),
            Text('Strength', style: theme.textTheme.titleSmall),
            Slider(
              value: _strength,
              onChanged: (value) {
                setState(() => _strength = value);
                _render();
              },
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PreviewTile(
                  label: 'On white',
                  background: const ColoredBox(color: Colors.white),
                  child: image,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PreviewTile(
                  label: 'Transparent parts',
                  background: const CustomPaint(painter: _CheckerPainter()),
                  child: image,
                ),
              ),
            ],
          ),
          if (widget.kind == BusinessImageKind.signature) ...[
            const SizedBox(height: 20),
            Text('On the invoice', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _SignatureBoxPreview(
              businessName: widget.businessName,
              image: image,
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: preview == null || _saving ? null : _save,
            child: Text(_saving ? 'Saving...' : 'Use this ${widget.kind.noun}'),
          ),
        ),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.label,
    required this.background,
    required this.child,
  });
  final String label;
  final Widget background;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      AspectRatio(
        aspectRatio: 1.6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              background,
              Padding(padding: const EdgeInsets.all(8), child: child),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The signature box as printed on invoices, at the same proportions.
class _SignatureBoxPreview extends StatelessWidget {
  const _SignatureBoxPreview({required this.businessName, required this.image});
  final String businessName;
  final Widget image;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1E3A8A);
    final name = businessName.trim().isEmpty
        ? 'YOUR BUSINESS'
        : businessName.trim().toUpperCase();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(color: Color(0xFF1F2430), fontSize: 13),
              children: [
                const TextSpan(text: 'For '),
                TextSpan(
                  text: name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(constraints.maxWidth, 260.0);
              return SizedBox(
                width: width,
                height: width * signaturePdfHeight / signaturePdfWidth,
                child: Align(alignment: Alignment.bottomCenter, child: image),
              );
            },
          ),
          const SizedBox(height: 4),
          const SizedBox(
            width: 260,
            child: Divider(color: ink, thickness: 1.2, height: 8),
          ),
          const Text(
            'Authorised signatory',
            style: TextStyle(color: Color(0xFF1F2430), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFFF2F3F7);
    final dark = Paint()..color = const Color(0xFFD9DCE5);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final even = ((x / cell).floor() + (y / cell).floor()).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), even ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A logo, signature or QR tile. Tapping opens the actions for that image.
class BusinessImageTile extends StatelessWidget {
  const BusinessImageTile({
    super.key,
    required this.label,
    required this.path,
    required this.onUpload,
    this.onEdit,
    this.onDraw,
    this.onRemove,
  });

  final String label;
  final String path;
  final VoidCallback onUpload;
  final VoidCallback? onEdit;
  final VoidCallback? onDraw;
  final VoidCallback? onRemove;

  bool get _hasImage => localFileExists(path);

  Future<void> _actions(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasImage && onEdit != null)
              ListTile(
                leading: const Icon(Icons.crop),
                title: const Text('Edit / crop'),
                onTap: () => Navigator.pop(sheet, 'edit'),
              ),
            ListTile(
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(_hasImage ? 'Upload a new one' : 'Upload a photo'),
              onTap: () => Navigator.pop(sheet, 'upload'),
            ),
            if (onDraw != null)
              ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: Text(_hasImage ? 'Draw again' : 'Draw it'),
                onTap: () => Navigator.pop(sheet, 'draw'),
              ),
            if (_hasImage && onRemove != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove'),
                onTap: () => Navigator.pop(sheet, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'edit':
        onEdit?.call();
      case 'upload':
        onUpload();
      case 'draw':
        onDraw?.call();
      case 'remove':
        onRemove?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _hasImage || onDraw != null ? _actions(context) : onUpload(),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 112,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Expanded(
              child: _hasImage
                  ? ColoredBox(color: Colors.white, child: localImage(path))
                  : Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 32,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                if (_hasImage) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
