import 'dart:async';
import 'document_defaults.dart';
import 'invoice_palette.dart';
import 'whatsapp_contact.dart';
import 'payment_pdf.dart';
import 'modern_ui.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:excel_plus/excel_plus.dart' as xlsx;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

String _titleCase(String value) =>
    value.replaceAllMapped(RegExp(r'\S+'), (match) {
      final word = match.group(0)!;
      if (word.length <= 3 && word == word.toUpperCase()) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    });

Future<void> showGstinResult(BuildContext context, String message) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('GSTIN verification'),
      content: SingleChildScrollView(child: Text(message)),
    ),
  );
  final completion = navigator.push(route);
  final timer = Timer(const Duration(seconds: 2), () {
    if (route.isActive) navigator.removeRoute(route);
  });
  try {
    await completion;
  } finally {
    timer.cancel();
  }
}

class _TitleCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: _titleCase(newValue.text));
}

String _normaliseIndianMobile(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length > 10 && digits.startsWith('91')) {
    digits = digits.substring(2);
  }
  if (digits.length > 10 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return digits.length > 10 ? digits.substring(0, 10) : digits;
}

String _upiPaymentUri(String upiId, String payeeName) => Uri(
  scheme: 'upi',
  host: 'pay',
  queryParameters: {
    'pa': upiId.trim().toLowerCase(),
    if (payeeName.trim().isNotEmpty) 'pn': payeeName.trim(),
    'cu': 'INR',
  },
).toString();

bool _isValidUpiId(String value) =>
    RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z0-9.-]{2,}$').hasMatch(value.trim());

String? _prefixValidator(String? value) =>
    RegExp(r'^[A-Za-z0-9-]{1,20}$').hasMatch(value?.trim() ?? '')
    ? null
    : 'Use 1-20 letters, numbers, or hyphens';

String _normaliseState(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _isOfflineError(Object error) {
  if (error is SocketException) return true;
  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('clientexception');
}

Future<Map<String, dynamic>?> _showSearchableRecordPicker(
  BuildContext context, {
  required String title,
  required String hint,
  required List<Map<String, dynamic>> records,
  required String Function(Map<String, dynamic>) titleFor,
  required String Function(Map<String, dynamic>) subtitleFor,
  required String Function(Map<String, dynamic>) searchableTextFor,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      var query = '';
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final visible = records.where((record) {
            return searchableTextFor(
              record,
            ).toLowerCase().contains(query.toLowerCase());
          }).toList();
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 430,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: hint,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => query = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('No matching records'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, index) {
                              final record = visible[index];
                              final subtitle = subtitleFor(record);
                              return ListTile(
                                title: Text(titleFor(record)),
                                subtitle: subtitle.isEmpty
                                    ? null
                                    : Text(subtitle),
                                onTap: () =>
                                    Navigator.of(dialogContext).pop(record),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

const _indianStatesAndUnionTerritories = <String>[
  'Andaman and Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

const _gstStateByCode = <String, String>{
  '01': 'Jammu and Kashmir',
  '02': 'Himachal Pradesh',
  '03': 'Punjab',
  '04': 'Chandigarh',
  '05': 'Uttarakhand',
  '06': 'Haryana',
  '07': 'Delhi',
  '08': 'Rajasthan',
  '09': 'Uttar Pradesh',
  '10': 'Bihar',
  '11': 'Sikkim',
  '12': 'Arunachal Pradesh',
  '13': 'Nagaland',
  '14': 'Manipur',
  '15': 'Mizoram',
  '16': 'Tripura',
  '17': 'Meghalaya',
  '18': 'Assam',
  '19': 'West Bengal',
  '20': 'Jharkhand',
  '21': 'Odisha',
  '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh',
  '24': 'Gujarat',
  '25': 'Dadra and Nagar Haveli and Daman and Diu',
  '26': 'Dadra and Nagar Haveli and Daman and Diu',
  '27': 'Maharashtra',
  '29': 'Karnataka',
  '30': 'Goa',
  '31': 'Lakshadweep',
  '32': 'Kerala',
  '33': 'Tamil Nadu',
  '34': 'Puducherry',
  '35': 'Andaman and Nicobar Islands',
  '36': 'Telangana',
  '37': 'Andhra Pradesh',
  '38': 'Ladakh',
};

String? _stateFromGstin(String gstin) =>
    gstin.length >= 2 ? _gstStateByCode[gstin.substring(0, 2)] : null;

class _RecordAutocompleteField extends StatefulWidget {
  const _RecordAutocompleteField({
    super.key,
    required this.controller,
    required this.loadOptions,
    required this.displayStringForOption,
    required this.searchTextForOption,
    required this.onSelected,
    required this.label,
    required this.helperText,
    required this.emptyError,
    this.leadingIcon,
    this.onAddRequested,
    this.addOptionDescription = 'Create a new record',
  });

  final TextEditingController controller;
  final Future<List<Map<String, dynamic>>> Function() loadOptions;
  final String Function(Map<String, dynamic>) displayStringForOption;
  final String Function(Map<String, dynamic>) searchTextForOption;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final String label;
  final String helperText;
  final String emptyError;
  final IconData? leadingIcon;
  final Future<Map<String, dynamic>?> Function(String name)? onAddRequested;
  final String addOptionDescription;

  @override
  State<_RecordAutocompleteField> createState() =>
      _RecordAutocompleteFieldState();
}

class _RecordAutocompleteFieldState extends State<_RecordAutocompleteField> {
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _options = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await widget.loadOptions();
      if (mounted) setState(() => _options = options);
    } catch (_) {
      if (mounted) setState(() => _options = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<Map<String, dynamic>>(
    textEditingController: widget.controller,
    focusNode: _focusNode,
    displayStringForOption: widget.displayStringForOption,
    optionsBuilder: (value) {
      final query = value.text.trim().toLowerCase();
      final matches = _options
          .where(
            (option) =>
                query.isEmpty ||
                widget
                    .searchTextForOption(option)
                    .toLowerCase()
                    .contains(query),
          )
          .take(50)
          .toList();
      final hasExact = matches.any(
        (option) =>
            widget.displayStringForOption(option).trim().toLowerCase() == query,
      );
      if (widget.onAddRequested != null && query.isNotEmpty && !hasExact) {
        matches.add({'__add_new__': true, 'name': value.text.trim()});
      }
      return matches;
    },
    onSelected: (option) async {
      if (option['__add_new__'] == true) {
        final created = await widget.onAddRequested!(
          option['name']?.toString() ?? '',
        );
        if (created != null && mounted) {
          setState(() => _options = [..._options, created]);
          widget.onSelected(created);
        }
      } else {
        widget.onSelected(option);
      }
    },
    fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          onFieldSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            border: const OutlineInputBorder(),
            prefixIcon: widget.leadingIcon == null
                ? null
                : Icon(widget.leadingIcon),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Show saved options',
                    icon: const Icon(Icons.arrow_drop_down),
                    onPressed: () {
                      _focusNode.requestFocus();
                      widget.controller.selection = TextSelection.collapsed(
                        offset: widget.controller.text.length,
                      );
                    },
                  ),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? widget.emptyError : null,
        ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 300),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, index) {
              final optionList = options.toList(growable: false);
              final option = optionList[index];
              if (option['__add_new__'] == true) {
                final name = option['name']?.toString() ?? '';
                return ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text('Add "$name"'),
                  subtitle: Text(widget.addOptionDescription),
                  onTap: () => onSelected(option),
                );
              }
              final details = widget.searchTextForOption(option);
              return ListTile(
                title: Text(widget.displayStringForOption(option)),
                subtitle: details == widget.displayStringForOption(option)
                    ? null
                    : Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _IndianMobileFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _normaliseIndianMobile(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

Future<Map<String, dynamic>?> _addProductFromDocumentBuilder(
  BuildContext context,
  String name,
) async {
  final saved = await Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute<Map<String, dynamic>>(
      builder: (_) => AddProductPage(initialName: name, returnRecord: true),
    ),
  );
  return saved;
}

Future<Map<String, dynamic>?> _addCustomerFromDocumentBuilder(
  BuildContext context,
  String name,
) async {
  final saved = await _showCustomerForm(context, initialName: name);
  return saved;
}

class OfflineStore {
  static String _key(String name) {
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? 'signed_out';
    return 'offline_${userId}_$name';
  }

  static Future<List<Map<String, dynamic>>> readList(String name) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_key(name));
    if (encoded == null || encoded.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(jsonDecode(encoded) as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeList(
    String name,
    List<Map<String, dynamic>> rows,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(name), jsonEncode(rows));
  }

  static Future<void> addCached(String name, Map<String, dynamic> row) async {
    final rows = await readList(name);
    rows.removeWhere((item) => item['id'] == row['id']);
    rows.insert(0, {...row, 'offline_pending': true});
    await writeList(name, rows);
  }

  static Future<void> enqueue(String name, Map<String, dynamic> payload) async {
    final queue = await readList('${name}_queue');
    final queued = Map<String, dynamic>.from(payload);
    final identity = queued['id'] ?? queued['_queue_id'] ?? const Uuid().v4();
    if (queued['id'] == null) queued['_queue_id'] = identity;
    queue.removeWhere((item) => (item['id'] ?? item['_queue_id']) == identity);
    queue.add(queued);
    await writeList('${name}_queue', queue);
  }

  static Future<int> flush(String table, String name) async {
    final queue = await readList('${name}_queue');
    if (queue.isEmpty) return 0;
    var synced = 0;
    final remaining = <Map<String, dynamic>>[];
    for (var index = 0; index < queue.length; index++) {
      final payload = queue[index];
      try {
        await Supabase.instance.client.from(table).insert(payload);
        synced++;
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          synced++;
        } else {
          remaining.addAll(queue.skip(index));
          break;
        }
      } catch (_) {
        remaining.addAll(queue.skip(index));
        break;
      }
    }
    await writeList('${name}_queue', remaining);
    return synced;
  }

  static Future<int> flushInvoiceDrafts() async {
    final queue = await readList('invoice_drafts_queue');
    if (queue.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (var index = 0; index < queue.length; index++) {
      final queued = queue[index];
      try {
        final header = Map<String, dynamic>.from(queued['header'] as Map);
        final invoiceNumber =
            await Supabase.instance.client.rpc(
                  'next_invoice_number',
                  params: Map<String, dynamic>.from(
                    queued['number_params'] as Map,
                  ),
                )
                as String;
        header['invoice_number'] = invoiceNumber;
        await Supabase.instance.client.from('invoices').upsert(header);
        final items = List<Map<String, dynamic>>.from(queued['items'] as List);
        await Supabase.instance.client.from('invoice_items').upsert(items);
        synced++;
      } catch (error) {
        remaining.addAll(queue.skip(index));
        break;
      }
    }
    await writeList('invoice_drafts_queue', remaining);
    return synced;
  }

  static Future<int> flushPayments() async {
    final queue = await readList('payments_queue');
    if (queue.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (var index = 0; index < queue.length; index++) {
      try {
        final params = Map<String, dynamic>.from(queue[index])
          ..remove('_queue_id');
        await Supabase.instance.client.rpc(
          'record_invoice_payment',
          params: params,
        );
        synced++;
      } catch (_) {
        remaining.addAll(queue.skip(index));
        break;
      }
    }
    await writeList('payments_queue', remaining);
    return synced;
  }
}

Future<String?> _pickAndEditImage(
  BuildContext context, {
  required String label,
}) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  if (image == null || !context.mounted) return null;
  var turns = 0;
  var cropSquare = false;
  final edit = await showDialog<(int, bool)?>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text('Edit $label'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: cropSquare ? 1 : 4 / 3,
                child: ClipRect(
                  child: RotatedBox(
                    quarterTurns: turns,
                    child: Image.file(
                      File(image.path),
                      fit: cropSquare ? BoxFit.cover : BoxFit.contain,
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Crop to square'),
                value: cropSquare,
                onChanged: (value) => setDialogState(() => cropSquare = value),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Rotate left',
                    onPressed: () =>
                        setDialogState(() => turns = (turns + 3) % 4),
                    icon: const Icon(Icons.rotate_left),
                  ),
                  IconButton(
                    tooltip: 'Rotate right',
                    onPressed: () =>
                        setDialogState(() => turns = (turns + 1) % 4),
                    icon: const Icon(Icons.rotate_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (turns, cropSquare)),
            child: const Text('Use image'),
          ),
        ],
      ),
    ),
  );
  if (edit == null) return null;
  final bytes = await image.readAsBytes();
  final source = await ui.instantiateImageCodec(bytes);
  final frame = await source.getNextFrame();
  final original = frame.image;
  final side = original.width < original.height
      ? original.width
      : original.height;
  final src = edit.$2
      ? Rect.fromLTWH(
          (original.width - side) / 2,
          (original.height - side) / 2,
          side.toDouble(),
          side.toDouble(),
        )
      : Rect.fromLTWH(
          0,
          0,
          original.width.toDouble(),
          original.height.toDouble(),
        );
  final rotated = edit.$1.isOdd;
  final outWidth = (rotated ? src.height : src.width).round();
  final outHeight = (rotated ? src.width : src.height).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(outWidth / 2, outHeight / 2)
    ..rotate(edit.$1 * 3.141592653589793 / 2);
  canvas.drawImageRect(
    original,
    src,
    Rect.fromCenter(center: Offset.zero, width: src.width, height: src.height),
    Paint(),
  );
  final output = await recorder.endRecording().toImage(outWidth, outHeight);
  final png = await output.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return image.path;
  final path = '${image.path}.simplek.png';
  await File(path).writeAsBytes(png.buffer.asUint8List(), flush: true);
  return path;
}

class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog();

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final _boundaryKey = GlobalKey();
  final List<Offset?> _points = [];

  Future<void> _save() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || !mounted) return;
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}simplek_signature_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
    if (mounted) Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Draw signature'),
    content: RepaintBoundary(
      key: _boundaryKey,
      child: GestureDetector(
        onPanStart: (details) =>
            setState(() => _points.add(details.localPosition)),
        onPanUpdate: (details) =>
            setState(() => _points.add(details.localPosition)),
        onPanEnd: (_) => setState(() => _points.add(null)),
        child: CustomPaint(
          painter: _SignaturePainter(_points),
          child: const SizedBox(width: 320, height: 180),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => setState(_points.clear),
        child: const Text('Clear'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _points.isEmpty ? null : _save,
        child: const Text('Use signature'),
      ),
    ],
  );
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter(this.points);
  final List<Offset?> points;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final ink = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, ink);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vvzaoxhygzhentywnlwr.supabase.co',
    publishableKey: 'sb_publishable_E3AJ4JWTv4yL656X9P5JuQ_H6Iwm1aY',
  );

  await BusinessSettings.load();
  await DesignSettings.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3157A4),
      brightness: Brightness.light,
    );
    return ValueListenableBuilder<bool>(
      valueListenable: DesignSettings.modern,
      builder: (context, modern, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: BusinessSettings.themeMode,
        builder: (context, mode, _) => MaterialApp(
          themeMode: mode,
          darkTheme: modern
              ? simplekTheme(Brightness.dark)
              : ThemeData(
                  useMaterial3: true,
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xFF3157A4),
                    brightness: Brightness.dark,
                  ),
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                  filledButtonTheme: FilledButtonThemeData(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 52),
                    ),
                  ),
                ),
          debugShowCheckedModeBanner: false,
          title: 'Simplek',
          theme: modern
              ? simplekTheme(Brightness.light)
              : ThemeData(
                  useMaterial3: true,
                  colorScheme: colorScheme,
                  scaffoldBackgroundColor: const Color(0xFFF6F7FB),
                  appBarTheme: const AppBarTheme(
                    backgroundColor: Color(0xFFF6F7FB),
                    surfaceTintColor: Colors.transparent,
                    centerTitle: false,
                  ),
                  inputDecorationTheme: InputDecorationTheme(
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  cardTheme: CardThemeData(
                    elevation: 0,
                    color: Colors.white,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  filledButtonTheme: FilledButtonThemeData(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  floatingActionButtonTheme: FloatingActionButtonThemeData(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
          home: home ?? const AppLaunchSplash(),
        ),
      ),
    );
  }
}

class AppLaunchSplash extends StatefulWidget {
  const AppLaunchSplash({super.key});
  @override
  State<AppLaunchSplash> createState() => _AppLaunchSplashState();
}

class _AppLaunchSplashState extends State<AppLaunchSplash> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, animation, secondaryAnimation) => const AuthGate(),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF7F9FF),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/branding/simplek-logo-hd.png', width: 230),
          const SizedBox(height: 18),
          const Text(
            'Invoicing made easy',
            style: TextStyle(fontSize: 17, color: Color(0xFF193A73)),
          ),
        ],
      ),
    ),
  );
}

const _authRedirectUrl = 'simplek://login-callback/';

class PendingSignup {
  static const _nameKey = 'pending_signup_name';
  static const _businessKey = 'pending_signup_business';
  static const _mobileKey = 'pending_signup_mobile';

  static Future<void> save({
    required String name,
    required String businessName,
    required String mobile,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nameKey, name);
    await preferences.setString(_businessKey, businessName);
    await preferences.setString(_mobileKey, mobile);
  }

  static Future<Map<String, String>?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final name = preferences.getString(_nameKey);
    if (name == null || name.isEmpty) return null;
    return {
      'name': name,
      'businessName': preferences.getString(_businessKey) ?? '',
      'mobile': preferences.getString(_mobileKey) ?? '',
    };
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_nameKey);
    await preferences.remove(_businessKey);
    await preferences.remove(_mobileKey);
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSubscription;
  Map<String, String>? _pendingSignup;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => _refresh(),
    );
    _refresh();
  }

  Future<void> _refresh() async {
    if (Supabase.instance.client.auth.currentSession != null) {
      await BusinessSettings.syncFromCloud();
    }
    final pendingSignup = await PendingSignup.load();
    if (mounted) {
      setState(() {
        _pendingSignup = pendingSignup;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (Supabase.instance.client.auth.currentSession == null) {
      return const LoginPage();
    }
    final pendingSignup = _pendingSignup;
    if (pendingSignup != null) {
      return PasswordSetupPage(
        name: pendingSignup['name']!,
        businessName: pendingSignup['businessName']!,
        mobile: pendingSignup['mobile']!,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: DesignSettings.modern,
      builder: (_, modern, _) =>
          modern ? const _ModernHome() : const DashboardPage(),
    );
  }
}

void _openPage(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

void _returnToDashboard(BuildContext context) {
  DesignSettings.destination.value = 0;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

class _ModernHome extends StatelessWidget {
  const _ModernHome();

  Future<void> _create(BuildContext context) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: EditorSection(
                  'Create something new',
                  'Choose your next action.',
                ),
              ),
              for (final entry in const [
                (Icons.receipt_long_outlined, 'New invoice'),
                (Icons.description_outlined, 'New quotation'),
                (Icons.payments_outlined, 'Record payment'),
              ].indexed)
                ListTile(
                  leading: Icon(entry.$2.$1),
                  title: Text(entry.$2.$2),
                  onTap: () => Navigator.of(sheet).pop(entry.$1),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    _openPage(context, switch (choice) {
      0 => const InvoiceBuilderPage(),
      1 => const QuotationBuilderPage(),
      _ => const PaymentsPage(),
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: DesignSettings.destination,
    builder: (context, index, _) => PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) DesignSettings.destination.value = 0;
      },
      child: Scaffold(
        body: switch (index) {
          1 => const InvoiceHistoryPage(),
          2 => const CustomersPage(),
          3 => const ProductsPage(),
          4 => const _MorePage(),
          _ => const DashboardPage(),
        },
        floatingActionButton: index == 0 || index == 4
            ? FloatingActionButton.extended(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          onDestinationSelected: (value) =>
              DesignSettings.destination.value = value,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              label: 'Invoices',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'Customers',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              label: 'Products',
            ),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    ),
  );
}

class _MorePage extends StatelessWidget {
  const _MorePage();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const EditorSection(
          'Your business tools',
          'Documents, payments and preferences.',
        ),
        for (final entry in <(IconData, String, Widget)>[
          (Icons.description_outlined, 'Quotations', const QuotationsPage()),
          (Icons.payments_outlined, 'Payments', const PaymentsPage()),
          (Icons.bar_chart_outlined, 'Reports', const ReportsPage()),
          (Icons.search, 'Search everything', const GlobalSearchPage()),
          (
            Icons.settings_outlined,
            'Business Profile & Settings',
            const BusinessSettingsPage(),
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: Icon(entry.$1),
                title: Text(entry.$2),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPage(context, entry.$3),
              ),
            ),
          ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () async => Supabase.instance.client.auth.signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    ),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberEmail = true;
  bool _showPassword = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _rememberEmail =
          preferences.getBool('auth_remember_email_enabled') ?? true;
      if (_rememberEmail) {
        _emailController.text =
            preferences.getString('auth_remembered_email') ?? '';
      }
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim().toLowerCase();
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _passwordController.text,
      );
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('auth_remember_email_enabled', _rememberEmail);
      if (_rememberEmail) {
        await preferences.setString('auth_remembered_email', email);
      } else {
        await preferences.remove('auth_remembered_email');
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to log in: $error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/branding/simplek-logo-hd.png',
                    height: 180,
                    fit: BoxFit.contain,
                    semanticLabel: 'Simplek logo',
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Login',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(color: Colors.indigo),
                            ),
                            const SizedBox(height: 22),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                                border: OutlineInputBorder(),
                              ),
                              validator: _emailValidator,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: !_showPassword,
                              autofillHints: const [AutofillHints.password],
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Password is required'
                                  : null,
                              onFieldSubmitted: (_) => _login(),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberEmail,
                                  onChanged: (value) => setState(
                                    () => _rememberEmail = value ?? true,
                                  ),
                                ),
                                const Text('Remember my email'),
                              ],
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _loading ? null : _login,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(_loading ? 'Logging in...' : 'Login'),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _openPage(context, const SignupPage()),
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              label: const Text('New user? Please sign up'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

String? _emailValidator(String? value) {
  final email = value?.trim() ?? '';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
      ? null
      : 'Enter a valid email address';
}

String _connectionMessage(Object error, {required String fallback}) {
  final message = error.toString().toLowerCase();
  if (message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('no address associated with hostname') ||
      message.contains('network is unreachable')) {
    return 'No internet connection. Check Wi-Fi or mobile data and try again.';
  }
  return fallback;
}

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _businessController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  bool _sendingEmail = false;

  Future<void> _sendVerificationEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sendingEmail = true);
    final email = _emailController.text.trim().toLowerCase();
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        emailRedirectTo: _authRedirectUrl,
        data: {
          'full_name': _nameController.text.trim(),
          'business_name': _businessController.text.trim(),
          'mobile': _mobileController.text.trim(),
        },
      );
      if (!mounted) return;
      await PendingSignup.save(
        name: _nameController.text.trim(),
        businessName: _businessController.text.trim(),
        mobile: _mobileController.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EmailLinkWaitingPage(email: email),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _connectionMessage(
                error,
                fallback: 'Unable to send the verification email right now.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingEmail = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _businessController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Tell us about you',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'We will email a verification link before asking you to create a password.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [_TitleCaseFormatter()],
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name is required'
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _businessController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [_TitleCaseFormatter()],
              autofillHints: const [AutofillHints.organizationName],
              decoration: const InputDecoration(
                labelText: 'Business name (optional)',
                prefixIcon: Icon(Icons.business_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              inputFormatters: [_IndianMobileFormatter()],
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: Icon(Icons.phone_outlined),
                border: OutlineInputBorder(),
                helperText: 'India: enter 10 digits',
              ),
              validator: (value) =>
                  RegExp(r'^[6-9]\d{9}$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Enter a valid 10-digit mobile number',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _emailValidator,
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _sendingEmail ? null : _sendVerificationEmail,
              icon: _sendingEmail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              label: Text(
                _sendingEmail ? 'Sending email...' : 'Send verification email',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class EmailLinkWaitingPage extends StatefulWidget {
  const EmailLinkWaitingPage({super.key, required this.email});
  final String email;

  @override
  State<EmailLinkWaitingPage> createState() => _EmailLinkWaitingPageState();
}

class _EmailLinkWaitingPageState extends State<EmailLinkWaitingPage> {
  StreamSubscription<AuthState>? _authSubscription;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (state.session != null && mounted) {
        _returnToDashboard(context);
      }
    });
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: widget.email,
        shouldCreateUser: true,
        emailRedirectTo: _authRedirectUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A new verification email was sent.')),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Check your email')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 72,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 20),
                Text(
                  'Verify your email',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a sign-in link to ${widget.email}. Open the email and tap the link. The app will return here automatically so you can set your password.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.hourglass_top_outlined),
                  label: const Text('Waiting for verification link'),
                ),
                TextButton(
                  onPressed: _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Sending...' : 'Resend verification email',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class PasswordSetupPage extends StatefulWidget {
  const PasswordSetupPage({
    super.key,
    required this.name,
    required this.businessName,
    required this.mobile,
  });
  final String name;
  final String businessName;
  final String mobile;

  @override
  State<PasswordSetupPage> createState() => _PasswordSetupPageState();
}

class _PasswordSetupPageState extends State<PasswordSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showPasswords = false;
  bool _saving = false;

  Future<void> _setPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: _passwordController.text,
          data: {
            'full_name': widget.name,
            'business_name': widget.businessName,
            'mobile': widget.mobile,
          },
        ),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BusinessOnboardingPage(
            ownerName: widget.name,
            businessName: widget.businessName,
            mobile: widget.mobile,
          ),
        ),
      );
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to set password: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Set your password')),
    body: SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Create a secure password',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android/Google Password Manager may offer to save this password.',
            ),
            const SizedBox(height: 24),
            AutofillGroup(
              child: Column(
                children: [
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_showPasswords,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _showPasswords = !_showPasswords),
                        icon: Icon(
                          _showPasswords
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => value != null && value.length >= 8
                        ? null
                        : 'Use at least 8 characters',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: !_showPasswords,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == _passwordController.text
                        ? null
                        : 'Passwords do not match',
                    onFieldSubmitted: (_) => _setPassword(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _saving ? null : _setPassword,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_reset_outlined),
              label: Text(_saving ? 'Saving...' : 'Set password and continue'),
            ),
          ],
        ),
      ),
    ),
  );
}

class BusinessOnboardingPage extends StatefulWidget {
  const BusinessOnboardingPage({
    super.key,
    required this.ownerName,
    required this.businessName,
    required this.mobile,
  });

  final String ownerName;
  final String businessName;
  final String mobile;

  @override
  State<BusinessOnboardingPage> createState() => _BusinessOnboardingPageState();
}

class _BusinessOnboardingPageState extends State<BusinessOnboardingPage> {
  static const _standardQuotationTerms = DocumentDefaults.quotation;
  static const _standardInvoiceTerms = DocumentDefaults.invoice;

  final _detailsKey = GlobalKey<FormState>();
  final _termsKey = GlobalKey<FormState>();
  final _brandingKey = GlobalKey<FormState>();
  late final TextEditingController _ownerController;
  late final TextEditingController _businessController;
  late final TextEditingController _gstinController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _panController;
  late final TextEditingController _stateController;
  late final TextEditingController _placeOfSupplyController;
  late final TextEditingController _financialYearController;
  late final TextEditingController _invoicePrefixController;
  late final TextEditingController _quotationPrefixController;
  late final TextEditingController _quotationTermsController;
  late final TextEditingController _invoiceTermsController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _branchController;
  late final TextEditingController _accountController;
  late final TextEditingController _ifscController;
  final _upiController = TextEditingController();
  bool _gstRegistered = false;
  String _gstRegistrationType = 'Regular';
  bool _verifying = false;
  bool _gstVerified = false;
  bool _saving = false;
  bool _lookingUpIfsc = false;
  String? _ifscMessage;
  int _step = 0;
  String _logoPath = '';
  String _signaturePath = '';
  String _qrPath = '';

  @override
  void initState() {
    super.initState();
    _ownerController = TextEditingController(text: widget.ownerName);
    _businessController = TextEditingController(text: widget.businessName);
    _gstinController = TextEditingController();
    _addressController = TextEditingController();
    _phoneController = TextEditingController(text: widget.mobile);
    _emailController = TextEditingController(
      text: Supabase.instance.client.auth.currentUser?.email ?? '',
    );
    _quotationTermsController = TextEditingController(
      text: _standardQuotationTerms,
    );
    _invoiceTermsController = TextEditingController(
      text: _standardInvoiceTerms,
    );
    _bankNameController = TextEditingController();
    _branchController = TextEditingController();
    _accountController = TextEditingController();
    _ifscController = TextEditingController();
    _panController = TextEditingController();
    _stateController = TextEditingController();
    _placeOfSupplyController = TextEditingController();
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    _financialYearController = TextEditingController(
      text: '$startYear-${(startYear + 1).toString().substring(2)}',
    );
    _invoicePrefixController = TextEditingController(text: 'INV');
    _quotationPrefixController = TextEditingController(text: 'QTN');
  }

  @override
  void dispose() {
    for (final controller in [
      _ownerController,
      _businessController,
      _gstinController,
      _addressController,
      _phoneController,
      _emailController,
      _quotationTermsController,
      _invoiceTermsController,
      _bankNameController,
      _branchController,
      _accountController,
      _ifscController,
      _upiController,
      _panController,
      _stateController,
      _placeOfSupplyController,
      _financialYearController,
      _invoicePrefixController,
      _quotationPrefixController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _verifyGstin() async {
    final gstin = _gstinController.text.trim().toUpperCase();
    if (!RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
    ).hasMatch(gstin)) {
      await showGstinResult(context, 'Enter a valid 15-character GSTIN.');
      return;
    }
    setState(() => _verifying = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'gstin-lookup',
        body: {'gstin': gstin},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw Exception(
          body is Map
              ? body['error'] ?? 'GSTIN verification failed.'
              : 'GSTIN verification failed.',
        );
      }
      final data = Map<String, dynamic>.from(body['data'] as Map);
      if (!mounted) return;
      setState(() {
        _gstinController.text = data['gstin']?.toString() ?? gstin;
        final legalName = data['legal_name']?.toString().trim() ?? '';
        final tradeName = data['trade_name']?.toString().trim() ?? '';
        if (tradeName.isNotEmpty || legalName.isNotEmpty) {
          _businessController.text = _titleCase(
            tradeName.isNotEmpty ? tradeName : legalName,
          );
        }
        final address = data['address']?.toString().trim() ?? '';
        if (address.isNotEmpty) _addressController.text = _titleCase(address);
        _gstVerified = true;
      });
      await showGstinResult(
        context,
        'GSTIN verified: ${data['status'] ?? 'active'}',
      );
    } catch (error) {
      if (mounted) {
        final message = error is FunctionException && error.details is Map
            ? error.details['error']?.toString() ?? 'GSTIN verification failed.'
            : error.toString().replaceFirst('Exception: ', '');
        await showGstinResult(context, message);
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _pickImage(String type) async {
    final path = await _pickAndEditImage(
      context,
      label: type == 'qr' ? 'payment QR' : type,
    );
    if (path == null || !mounted) return;
    setState(() {
      if (type == 'logo') _logoPath = path;
      if (type == 'signature') _signaturePath = path;
      if (type == 'qr') _qrPath = path;
    });
  }

  Future<void> _drawSignature() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => const _SignaturePadDialog(),
    );
    if (path != null && mounted) setState(() => _signaturePath = path);
  }

  Future<void> _lookupOnboardingIfsc(String value) async {
    final ifsc = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) {
      setState(() => _ifscMessage = null);
      return;
    }
    setState(() {
      _lookingUpIfsc = true;
      _ifscMessage = null;
    });
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(
        Uri.parse('https://ifsc.razorpay.com/$ifsc'),
      )).close();
      if (response.statusCode != 200) throw const HttpException('Not found');
      final data =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _bankNameController.text = data['BANK']?.toString() ?? '';
        _branchController.text = data['BRANCH']?.toString() ?? '';
        _ifscMessage = 'Bank and branch filled from IFSC.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _ifscMessage = 'Unable to verify this IFSC right now.');
      }
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _lookingUpIfsc = false);
    }
  }

  void _continue() {
    if (_step == 0) {
      if (!_detailsKey.currentState!.validate()) return;
      if (_gstRegistered && !_gstVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verify the GSTIN before continuing.')),
        );
        return;
      }
    }
    if (_step == 1 && !_termsKey.currentState!.validate()) return;
    setState(() => _step++);
  }

  Future<void> _finish() async {
    if (!_brandingKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await BusinessSettings.setGstRegistered(_gstRegistered);
      await BusinessSettings.setDocumentTerms(
        quotation: _quotationTermsController.text.trim(),
        invoice: _invoiceTermsController.text.trim(),
      );
      await BusinessSettings.saveProfile({
        'ownerName': _ownerController.text.trim(),
        'name': _businessController.text.trim(),
        'address': _addressController.text.trim(),
        'gstin': _gstRegistered
            ? _gstinController.text.trim().toUpperCase()
            : '',
        'phone': _normaliseIndianMobile(_phoneController.text),
        'email': _emailController.text.trim(),
        'bankName': _bankNameController.text.trim(),
        'bankBranch': _branchController.text.trim(),
        'bankAccount': _accountController.text.trim(),
        'ifsc': _ifscController.text.trim().toUpperCase(),
        'logoPath': _logoPath,
        'signaturePath': _signaturePath,
        'qrPath': _qrPath,
        'upiId': _upiController.text.trim().toLowerCase(),
        'pan': _panController.text.trim().toUpperCase(),
        'gstRegistrationType': _gstRegistrationType,
        'businessState': _stateController.text.trim(),
        'placeOfSupply': _placeOfSupplyController.text.trim(),
        'financialYear': _financialYearController.text.trim(),
        'invoicePrefix': _invoicePrefixController.text.trim().toUpperCase(),
        'quotationPrefix': _quotationPrefixController.text.trim().toUpperCase(),
      });
      await PendingSignup.clear();
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Setup complete'),
          content: const Text(
            'Your business profile is ready. Please log in with your new password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go to login'),
            ),
          ],
        ),
      );
      if (mounted) _returnToDashboard(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to complete setup: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Set up your business'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: Stepper(
        currentStep: _step,
        onStepContinue: _step == 2 ? (_saving ? null : _finish) : _continue,
        onStepCancel: _step == 0 ? null : () => setState(() => _step--),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Row(
            children: [
              FilledButton(
                onPressed: details.onStepContinue,
                child: Text(
                  _saving
                      ? 'Saving...'
                      : _step == 2
                      ? 'Finish setup'
                      : 'Next',
                ),
              ),
              if (_step > 0) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: details.onStepCancel,
                  child: const Text('Back'),
                ),
              ],
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('Business details'),
            isActive: _step >= 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: _detailsStep(),
          ),
          Step(
            title: const Text('Terms and conditions'),
            isActive: _step >= 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: _termsStep(),
          ),
          Step(
            title: const Text('Branding and payments'),
            isActive: _step >= 2,
            content: _brandingStep(),
          ),
        ],
      ),
    ),
  );

  Widget _detailsStep() => Form(
    key: _detailsKey,
    child: Column(
      children: [
        TextFormField(
          controller: _ownerController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Name is required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _businessController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Business name',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().length < 2
              ? 'Business name is required'
              : null,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Is your business registered under GST?'),
          value: _gstRegistered,
          onChanged: (value) => setState(() {
            _gstRegistered = value;
            _gstVerified = false;
            if (!value) _gstinController.clear();
          }),
        ),
        if (_gstRegistered) ...[
          DropdownButtonFormField<String>(
            initialValue: _gstRegistrationType,
            decoration: const InputDecoration(
              labelText: 'GST registration type',
              border: OutlineInputBorder(),
            ),
            items: const ['Regular', 'Composition', 'Casual', 'Non-resident']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() => _gstRegistrationType = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _gstinController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (_, value) => value.copyWith(
                  text: value.text.toUpperCase(),
                  selection: value.selection,
                ),
              ),
            ],
            onChanged: (_) => setState(() => _gstVerified = false),
            decoration: InputDecoration(
              labelText: 'Business GSTIN',
              helperText: _gstVerified
                  ? 'Verified'
                  : 'Verify to auto-fill registered business details.',
              border: const OutlineInputBorder(),
              suffixIcon: _gstVerified
                  ? const Icon(Icons.verified, color: Colors.green)
                  : null,
            ),
            validator: (value) =>
                RegExp(
                  r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                ).hasMatch(value?.trim().toUpperCase() ?? '')
                ? null
                : 'Enter a valid GSTIN',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _verifying ? null : _verifyGstin,
              icon: _verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(_verifying ? 'Verifying...' : 'Verify GSTIN'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextFormField(
          controller: _panController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'PAN',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value!.trim().isEmpty ||
                  RegExp(
                    r'^[A-Z]{5}[0-9]{4}[A-Z]$',
                  ).hasMatch(value.trim().toUpperCase())
              ? null
              : 'Enter a valid PAN',
        ),
        const SizedBox(height: 12),
        SearchableStateField(
          initialValue:
              _indianStatesAndUnionTerritories.contains(_stateController.text)
              ? _stateController.text
              : null,
          decoration: const InputDecoration(
            labelText: 'Business state',
            border: OutlineInputBorder(),
          ),
          items: _indianStatesAndUnionTerritories
              .map(
                (state) => DropdownMenuItem(value: state, child: Text(state)),
              )
              .toList(),
          onChanged: (value) => setState(() {
            _stateController.text = value ?? '';
            if (_placeOfSupplyController.text.isEmpty) {
              _placeOfSupplyController.text = value ?? '';
            }
          }),
          validator: (value) =>
              value == null ? 'Select the business state' : null,
        ),
        const SizedBox(height: 12),
        SearchableStateField(
          initialValue:
              _indianStatesAndUnionTerritories.contains(
                _placeOfSupplyController.text,
              )
              ? _placeOfSupplyController.text
              : null,
          decoration: const InputDecoration(
            labelText: 'Default place of supply',
            border: OutlineInputBorder(),
          ),
          items: _indianStatesAndUnionTerritories
              .map(
                (state) => DropdownMenuItem(value: state, child: Text(state)),
              )
              .toList(),
          onChanged: (value) => _placeOfSupplyController.text = value ?? '',
          validator: (value) =>
              value == null ? 'Select the default place of supply' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _financialYearController,
          decoration: const InputDecoration(
            labelText: 'Financial year',
            hintText: '2026-27',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              RegExp(r'^20[0-9]{2}-[0-9]{2}$').hasMatch(value!.trim())
              ? null
              : 'Use format 2026-27',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _invoicePrefixController,
                decoration: const InputDecoration(
                  labelText: 'Invoice prefix',
                  border: OutlineInputBorder(),
                ),
                validator: _prefixValidator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _quotationPrefixController,
                decoration: const InputDecoration(
                  labelText: 'Quotation prefix',
                  border: OutlineInputBorder(),
                ),
                validator: _prefixValidator,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Business address',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().length < 5
              ? 'Enter the business address'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [_IndianMobileFormatter()],
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Business email',
            border: OutlineInputBorder(),
          ),
          validator: _emailValidator,
        ),
      ],
    ),
  );

  Widget _termsStep() => Form(
    key: _termsKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'These standard terms are editable now and on every document.',
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _quotationTermsController,
          minLines: 5,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: 'Default quotation terms',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Add quotation terms'
              : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _invoiceTermsController,
          minLines: 5,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: 'Default invoice terms',
            border: OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Add invoice terms'
              : null,
        ),
      ],
    ),
  );

  Widget _brandingStep() => Form(
    key: _brandingKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload your logo and signature. Enter a UPI ID to generate a QR code, or attach an existing payment QR image.',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _onboardingImage('Logo', _logoPath, () => _pickImage('logo')),
            const SizedBox(width: 10),
            _onboardingImage(
              'Signature',
              _signaturePath,
              () => _pickImage('signature'),
            ),
            const SizedBox(width: 10),
            _onboardingImage('Payment QR', _qrPath, () => _pickImage('qr')),
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: _drawSignature,
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Draw signature'),
          ),
        ),
        const SizedBox(height: 18),
        TextFormField(
          controller: _upiController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'UPI ID (optional)',
            hintText: 'business@bank',
            helperText:
                'A scannable UPI payment QR code will be generated automatically.',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final upi = value?.trim() ?? '';
            return upi.isEmpty || _isValidUpiId(upi)
                ? null
                : 'Enter a valid UPI ID';
          },
        ),
        if (_isValidUpiId(_upiController.text)) ...[
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                QrImageView(
                  data: _upiPaymentUri(
                    _upiController.text,
                    _businessController.text,
                  ),
                  size: 170,
                ),
                const Text('UPI payment QR preview'),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text('Bank details', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextFormField(
          controller: _ifscController,
          textCapitalization: TextCapitalization.characters,
          onChanged: _lookupOnboardingIfsc,
          decoration: const InputDecoration(
            labelText: 'IFSC code',
            helperText:
                'Enter the IFSC Code to prefill bank and branch details',
            border: OutlineInputBorder(),
          ),
          validator: (value) =>
              value == null ||
                  value.trim().isEmpty ||
                  RegExp(
                    r'^[A-Z]{4}0[A-Z0-9]{6}$',
                  ).hasMatch(value.trim().toUpperCase())
              ? null
              : 'Enter a valid IFSC code',
        ),
        if (_lookingUpIfsc || _ifscMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _lookingUpIfsc ? 'Looking up bank and branch...' : _ifscMessage!,
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _bankNameController,
          decoration: const InputDecoration(
            labelText: 'Bank name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _branchController,
          decoration: const InputDecoration(
            labelText: 'Branch',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _accountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Account number',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
  );

  Widget _onboardingImage(String label, String path, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 110,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Expanded(
                  child: path.isNotEmpty && File(path).existsSync()
                      ? Image.file(File(path), fit: BoxFit.contain)
                      : const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 34,
                        ),
                ),
                Text(label, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
}

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim().toLowerCase();
    if (query.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Future.wait([
        Supabase.instance.client.from('customers').select().limit(100),
        Supabase.instance.client
            .from('products')
            .select('id, name, product_type, sku, hsn_sac_code, selling_price')
            .eq('is_active', true)
            .limit(100),
        Supabase.instance.client
            .from('invoices')
            .select(
              'id, invoice_number, customer_name, invoice_date, status, total_amount',
            )
            .order('invoice_date', ascending: false)
            .limit(100),
        Supabase.instance.client
            .from('quotations')
            .select(
              'id, quotation_number, customer_name, quotation_date, status, total_amount',
            )
            .order('quotation_date', ascending: false)
            .limit(100),
      ]).timeout(const Duration(seconds: 15));
      final searchable = <Map<String, dynamic>>[];
      void addMatches(dynamic rows, String type, List<String> fields) {
        for (final raw in rows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final text = fields
              .map((field) => row[field]?.toString() ?? '')
              .join(' ')
              .toLowerCase();
          if (text.contains(query)) searchable.add({...row, '_type': type});
        }
      }

      addMatches(data[0], 'customer', ['name', 'phone', 'email', 'gstin']);
      addMatches(data[1], 'product', [
        'name',
        'product_type',
        'sku',
        'hsn_sac_code',
      ]);
      addMatches(data[2], 'invoice', [
        'invoice_number',
        'customer_name',
        'status',
      ]);
      addMatches(data[3], 'quotation', [
        'quotation_number',
        'customer_name',
        'status',
      ]);
      if (mounted && query == _controller.text.trim().toLowerCase()) {
        setState(() => _results = searchable);
      }
    } catch (error) {
      final cachedCustomers = await OfflineStore.readList('customers');
      final cachedProducts = await OfflineStore.readList('products');
      final cached = <Map<String, dynamic>>[];
      for (final row in cachedCustomers) {
        if ('${row['name']} ${row['phone']} ${row['email']} ${row['gstin']}'
            .toLowerCase()
            .contains(query)) {
          cached.add({...row, '_type': 'customer'});
        }
      }
      for (final row in cachedProducts) {
        if ('${row['name']} ${row['product_type']} ${row['sku']} ${row['hsn_sac_code']}'
            .toLowerCase()
            .contains(query)) {
          cached.add({...row, '_type': 'product'});
        }
      }
      if (mounted) {
        setState(() {
          _results = cached;
          _error = cached.isEmpty
              ? 'Search is unavailable while offline.'
              : 'Showing cached customers and items.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Map<String, dynamic> result) {
    final type = result['_type'];
    final page = switch (type) {
      'customer' => CustomerHistoryPage(customer: result),
      'product' => const ProductsPage(),
      'invoice' => const InvoiceHistoryPage(),
      _ => const QuotationsPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search Simplek')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _scheduleSearch,
            decoration: InputDecoration(
              labelText: 'Customers, items, invoices, quotations',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _controller.text.trim().length < 2
                        ? 'Enter at least 2 characters.'
                        : 'No matching records.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, index) {
                    final result = _results[index];
                    final type = result['_type']?.toString() ?? '';
                    final title = switch (type) {
                      'customer' => result['name'],
                      'product' => result['name'],
                      'invoice' => result['invoice_number'],
                      _ => result['quotation_number'],
                    };
                    final subtitle = switch (type) {
                      'customer' =>
                        '${result['phone'] ?? ''} ${result['gstin'] ?? ''}',
                      'product' =>
                        '${result['product_type'] ?? ''} • ₹${result['selling_price'] ?? 0}',
                      _ =>
                        '${result['customer_name'] ?? ''} • ${(result['status'] ?? '').toString().toUpperCase()}',
                    };
                    final icon = switch (type) {
                      'customer' => Icons.person_outline,
                      'product' => Icons.inventory_2_outlined,
                      'invoice' => Icons.receipt_long_outlined,
                      _ => Icons.request_quote_outlined,
                    };
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(icon)),
                        title: Text(title?.toString() ?? 'Record'),
                        subtitle: Text(subtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(result),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _invoiceCount = 0;
  int _customerCount = 0;
  double _totalSales = 0;
  double _outstanding = 0;
  List<Map<String, dynamic>> _recentInvoices = [];
  bool _isLoadingSummary = true;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (mounted) {
      setState(() {
        _isLoadingSummary = true;
        _summaryError = null;
      });
    }
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('invoices')
            .select(
              'invoice_number, customer_name, invoice_date, status, total_amount, balance_amount',
            )
            .order('invoice_date', ascending: false)
            .limit(100),
        Supabase.instance.client.from('customers').select('id'),
      ]).timeout(const Duration(seconds: 15));
      final invoices = List<Map<String, dynamic>>.from(results[0] as List);
      final customers = List<Map<String, dynamic>>.from(results[1] as List);
      var totalSales = 0.0;
      var outstanding = 0.0;
      for (final invoice in invoices) {
        if (invoice['status']?.toString() != 'cancelled') {
          totalSales += _asDouble(invoice['total_amount']);
          outstanding += _asDouble(invoice['balance_amount']);
        }
      }
      if (!mounted) return;
      setState(() {
        _invoiceCount = invoices.length;
        _customerCount = customers.length;
        _totalSales = totalSales;
        _outstanding = outstanding;
        _recentInvoices = invoices.take(5).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _summaryError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingSummary = false);
    }
  }

  String _money(double amount) => '₹${amount.toStringAsFixed(2)}';

  double _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Simplek', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GlobalSearchPage()),
            ),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: _isLoadingSummary ? null : _loadSummary,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BusinessSettingsPage(),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),

      drawer: DesignSettings.modern.value
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      decoration: const BoxDecoration(color: Colors.indigo),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Image.asset(
                            'assets/branding/simplek-app-icon-hd.png',
                            width: 48,
                            height: 48,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Simplek',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Invoicing made easy',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),

                    ListTile(
                      leading: const Icon(Icons.dashboard_outlined),
                      title: const Text('Dashboard'),
                      selected: true,
                      onTap: () => Navigator.pop(context),
                    ),

                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Customers'),
                      onTap: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        navigator.push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CustomersPage(),
                          ),
                        );
                      },
                    ),

                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Products & Services'),
                      onTap: () => _openPage(context, const ProductsPage()),
                    ),

                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Invoices'),
                      onTap: () =>
                          _openPage(context, const InvoiceHistoryPage()),
                    ),

                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Quotations'),
                      onTap: () => _openPage(context, const QuotationsPage()),
                    ),

                    ListTile(
                      leading: const Icon(Icons.payments_outlined),
                      title: const Text('Payments'),
                      onTap: () => _openPage(context, const PaymentsPage()),
                    ),

                    ListTile(
                      leading: const Icon(Icons.bar_chart_outlined),
                      title: const Text('Reports'),
                      onTap: () => _openPage(context, const ReportsPage()),
                    ),

                    const Divider(),

                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Business Profile & Settings'),
                      onTap: () =>
                          _openPage(context, const BusinessSettingsPage()),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Log out'),
                      onTap: () async {
                        Navigator.pop(context);
                        await Supabase.instance.client.auth.signOut();
                      },
                    ),
                  ],
                ),
              ),
            ),

      body: DesignSettings.modern.value
          ? ModernOverview(
              sales: _money(_totalSales),
              outstanding: _money(_outstanding),
              invoiceCount: '$_invoiceCount',
              customerCount: '$_customerCount',
              loading: _isLoadingSummary,
              error: _summaryError,
              recent: _recentInvoices
                  .map(
                    (row) => <String, String>{
                      'number': row['invoice_number']?.toString() ?? 'Invoice',
                      'customer': row['customer_name']?.toString() ?? '',
                      'amount': _money(_asDouble(row['total_amount'])),
                      'status': row['status']?.toString() ?? 'draft',
                      'date': row['invoice_date']?.toString() ?? '',
                    },
                  )
                  .toList(),
              onNewInvoice: () =>
                  _openPage(context, const InvoiceBuilderPage()),
              onNewQuotation: () =>
                  _openPage(context, const QuotationBuilderPage()),
              onCustomer: () async {
                await _showCustomerForm(context);
                if (mounted) await _loadSummary();
              },
              onProduct: () => _openPage(context, const AddProductPage()),
              onInvoices: () => DesignSettings.destination.value = 1,
              onRefresh: _loadSummary,
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dashboard',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    'Here is your business overview',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                  ),

                  if (_summaryError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Unable to refresh dashboard: $_summaryError',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Summary cards
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          title: 'Total Sales',
                          value: _money(_totalSales),
                          icon: Icons.trending_up,
                          iconColor: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _summaryCard(
                          title: 'Outstanding',
                          value: _money(_outstanding),
                          icon: Icons.account_balance_wallet_outlined,
                          iconColor: Colors.orange,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          title: 'Invoices',
                          value: _invoiceCount.toString(),
                          icon: Icons.receipt_long_outlined,
                          iconColor: Colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _summaryCard(
                          title: 'Customers',
                          value: _customerCount.toString(),
                          icon: Icons.people_outline,
                          iconColor: Colors.purple,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          icon: Icons.add,
                          title: 'New Invoice',
                          color: Colors.indigo,
                          onTap: () =>
                              _openPage(context, const InvoiceBuilderPage()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionButton(
                          icon: Icons.person_add_outlined,
                          title: 'New Customer',
                          color: Colors.green,
                          onTap: () {
                            debugPrint('NEW CUSTOMER TAPPED');
                            _showCustomerForm(context);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          icon: Icons.inventory_2_outlined,
                          title: 'Add Product',
                          color: Colors.orange,
                          onTap: () => _openPage(context, const ProductsPage()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionButton(
                          icon: Icons.payment_outlined,
                          title: 'Record Payment',
                          color: Colors.purple,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PaymentsPage(),
                              ),
                            );
                            await _loadSummary();
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  const Text(
                    'Recent Invoices',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 14),

                  if (_isLoadingSummary)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_recentInvoices.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 52,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No invoices yet',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Create your first invoice to get started.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () =>
                                _openPage(context, const InvoiceBuilderPage()),
                            icon: const Icon(Icons.add),
                            label: const Text('Create Invoice'),
                          ),
                        ],
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: List.generate(_recentInvoices.length, (
                          index,
                        ) {
                          final invoice = _recentInvoices[index];
                          final status =
                              invoice['status']?.toString() ?? 'draft';
                          return Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    status == 'paid'
                                        ? Icons.check
                                        : Icons.receipt_long_outlined,
                                  ),
                                ),
                                title: Text(
                                  invoice['invoice_number']?.toString() ??
                                      'Invoice',
                                ),
                                subtitle: Text(
                                  '${invoice['customer_name'] ?? ''} • ${invoice['invoice_date'] ?? ''}\n${status.toUpperCase()}',
                                ),
                                isThreeLine: true,
                                trailing: Text(
                                  _money(_asDouble(invoice['total_amount'])),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onTap: () => _openPage(
                                  context,
                                  const InvoiceHistoryPage(),
                                ),
                              ),
                              if (index < _recentInvoices.length - 1)
                                const Divider(height: 1),
                            ],
                          );
                        }),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Supabase status
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_done_outlined, color: Colors.green),
                        SizedBox(width: 10),
                        Text(
                          'Supabase connected',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> _showCustomerForm(
  BuildContext context, {
  Map<String, dynamic>? customer,
  String? initialName,
}) async {
  final saved = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) =>
        _CustomerFormDialog(customer: customer, initialName: initialName),
  );

  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Customer saved successfully')),
    );
  }

  return saved;
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _showingCached = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applySearch);
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await OfflineStore.flush('customers', 'customers');
      final rows = await Supabase.instance.client
          .from('customers')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      final customers = List<Map<String, dynamic>>.from(rows);
      await OfflineStore.writeList('customers', customers);
      setState(() {
        _customers = customers;
        _showingCached = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = await OfflineStore.readList('customers');
      setState(() {
        _customers = cached;
        _showingCached = cached.isNotEmpty;
        _errorMessage = cached.isEmpty ? 'Unable to load customers: $e' : null;
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _visibleCustomers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _customers;
    return _customers.where((customer) {
      return [
        customer['name'],
        customer['phone'],
        customer['email'],
        customer['gstin'],
      ].whereType<String>().any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _addCustomer() async {
    final saved = await _showCustomerForm(context);
    if (saved != null) await _loadCustomers();
  }

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    final saved = await _showCustomerForm(context, customer: customer);
    if (saved != null) await _loadCustomers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showingCached ? 'Customers • Offline' : 'Customers'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('New Customer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search customers',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadCustomers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final customers = _visibleCustomers;
    if (customers.isEmpty) {
      final hasSearch = _searchController.text.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: _loadCustomers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 360,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 56,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      hasSearch ? 'No matching customers' : 'No customers yet',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasSearch
                          ? 'Try a different name, mobile number, or email.'
                          : 'Add a customer to start creating invoices.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCustomers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        itemCount: customers.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final customer = customers[index];
          final name = customer['name'] as String? ?? 'Unnamed customer';
          final contact = (customer['phone'] as String?)?.isNotEmpty == true
              ? customer['phone'] as String
              : customer['email'] as String? ?? '';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(name.characters.first.toUpperCase()),
              ),
              title: Text(name),
              subtitle: contact.isEmpty ? null : Text(contact),
              trailing: IconButton(
                tooltip: 'Edit customer',
                onPressed: () => _editCustomer(customer),
                icon: const Icon(Icons.edit_outlined),
              ),
              onTap: () =>
                  _openPage(context, CustomerHistoryPage(customer: customer)),
            ),
          );
        },
      ),
    );
  }
}

class CustomerHistoryPage extends StatefulWidget {
  const CustomerHistoryPage({super.key, required this.customer});

  final Map<String, dynamic> customer;

  @override
  State<CustomerHistoryPage> createState() => _CustomerHistoryPageState();
}

class _CustomerHistoryPageState extends State<CustomerHistoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _quotations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final name = widget.customer['name']?.toString() ?? '';
      final results = await Future.wait([
        Supabase.instance.client
            .from('invoices')
            .select(
              'invoice_number, invoice_date, status, total_amount, balance_amount',
            )
            .eq('customer_name', name)
            .order('invoice_date', ascending: false),
        Supabase.instance.client
            .from('quotations')
            .select('quotation_number, quotation_date, status, total_amount')
            .eq('customer_name', name)
            .order('quotation_date', ascending: false),
      ]).timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          _invoices = List<Map<String, dynamic>>.from(results[0] as List);
          _quotations = List<Map<String, dynamic>>.from(results[1] as List);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final name = widget.customer['name']?.toString() ?? 'Customer';
    final sales = _invoices.fold<double>(
      0,
      (sum, invoice) => sum + _amount(invoice['total_amount']),
    );
    final outstanding = _invoices.fold<double>(
      0,
      (sum, invoice) => sum + _amount(invoice['balance_amount']),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Customer History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Unable to load history:\n$_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  if ((widget.customer['phone']?.toString() ?? '').isNotEmpty)
                    Text(widget.customer['phone'].toString()),
                  if ((widget.customer['email']?.toString() ?? '').isNotEmpty)
                    Text(widget.customer['email'].toString()),
                  if ((widget.customer['gstin']?.toString() ?? '').isNotEmpty)
                    Text('GSTIN: ${widget.customer['gstin']}'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          'Total billed',
                          _money(sales),
                          Colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metric(
                          'Outstanding',
                          _money(outstanding),
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Invoices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_invoices.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No invoices for this customer yet.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: _invoices
                            .map(
                              (invoice) => ListTile(
                                title: Text(
                                  invoice['invoice_number']?.toString() ??
                                      'Invoice',
                                ),
                                subtitle: Text(
                                  '${invoice['invoice_date'] ?? ''} • ${(invoice['status'] ?? 'draft').toString().toUpperCase()}',
                                ),
                                trailing: Text(
                                  _money(_amount(invoice['total_amount'])),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Quotations',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (_quotations.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No quotations for this customer yet.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: _quotations
                            .map(
                              (quote) => ListTile(
                                title: Text(
                                  quote['quotation_number']?.toString() ??
                                      'Quotation',
                                ),
                                subtitle: Text(
                                  '${quote['quotation_date'] ?? ''} • ${(quote['status'] ?? 'draft').toString().toUpperCase()}',
                                ),
                                trailing: Text(
                                  _money(_amount(quote['total_amount'])),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _metric(String label, String value, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

class BusinessSettings {
  static String get _invoiceThemeCacheKey {
    final user = Supabase.instance.client.auth.currentUser;
    return 'business_invoice_theme_${user?.id ?? 'signed_out'}';
  }
  static final themeMode = ValueNotifier(ThemeMode.system);

  static Future<void> setThemeMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('app_theme_mode', mode.name);
    themeMode.value = mode;
  }

  static const _secureStorage = FlutterSecureStorage();
  static const _gstRegisteredKey = 'business_gst_registered';
  static const _defaultDueDayKey = 'business_default_due_day';
  static const _defaultTermsKey = 'business_default_terms';
  static const _quotationTermsKey = 'business_quotation_terms';
  static const _invoiceTermsKey = 'business_invoice_terms';
  static const _ownerNameKey = 'business_owner_name';
  static const _businessNameKey = 'business_name';
  static const _businessAddressKey = 'business_address';
  static const _businessGstinKey = 'business_gstin';
  static const _businessPhoneKey = 'business_phone';
  static const _businessEmailKey = 'business_email';
  static const _bankNameKey = 'business_bank_name';
  static const _bankBranchKey = 'business_bank_branch';
  static const _bankAccountKey = 'business_bank_account';
  static const _bankIfscKey = 'business_bank_ifsc';
  static const _logoPathKey = 'business_logo_path';
  static const _signaturePathKey = 'business_signature_path';
  static const _qrPathKey = 'business_qr_path';
  static const _upiIdKey = 'business_upi_id';
  static const _panKey = 'business_pan';
  static const _gstRegistrationTypeKey = 'business_gst_registration_type';
  static const _businessStateKey = 'business_state';
  static const _placeOfSupplyKey = 'business_place_of_supply';
  static const _financialYearKey = 'business_financial_year';
  static const _invoicePrefixKey = 'business_invoice_prefix';
  static const _quotationPrefixKey = 'business_quotation_prefix';
  static final ValueNotifier<bool> isGstRegistered = ValueNotifier(false);
  static final ValueNotifier<int?> defaultDueDay = ValueNotifier(7);
  static final ValueNotifier<String> defaultTerms = ValueNotifier('');
  static final ValueNotifier<String> quotationTerms = ValueNotifier('');
  static final ValueNotifier<String> invoiceTerms = ValueNotifier('');
  static final ValueNotifier<Map<String, String>> profile = ValueNotifier({});

  static Future<String> _readProtected(
    SharedPreferences preferences,
    String key,
  ) async {
    final protectedValue = await _secureStorage.read(key: key);
    if (protectedValue != null) return protectedValue;
    final legacyValue = preferences.getString(key) ?? '';
    if (legacyValue.isNotEmpty) {
      await _secureStorage.write(key: key, value: legacyValue);
      await preferences.remove(key);
    }
    return legacyValue;
  }

  static Future<void> _writeProtected(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    if (value.isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
    await preferences.remove(key);
  }

  static Future<String> _uploadBusinessMedia(
    String localPath,
    String type,
    String userId,
  ) async {
    if (localPath.isEmpty || !File(localPath).existsSync()) return '';
    try {
      final extension = localPath.split('.').last.toLowerCase();
      final safeExtension = ['png', 'jpg', 'jpeg', 'webp'].contains(extension)
          ? extension
          : 'png';
      final objectPath = '$userId/$type.$safeExtension';
      final contentType = switch (safeExtension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        _ => 'image/png',
      };
      await Supabase.instance.client.storage
          .from('business-media')
          .uploadBinary(
            objectPath,
            await File(localPath).readAsBytes(),
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return objectPath;
    } catch (_) {
      return '';
    }
  }

  static Future<String> _downloadBusinessMedia(
    String objectPath,
    String type,
    String fallback,
  ) async {
    if (objectPath.isEmpty) return fallback;
    try {
      final bytes = await Supabase.instance.client.storage
          .from('business-media')
          .download(objectPath);
      final extension = objectPath.split('.').last.toLowerCase();
      final directory = await getApplicationDocumentsDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}business_$type.$extension',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    themeMode.value = ThemeMode.values.firstWhere(
      (mode) => mode.name == preferences.getString('app_theme_mode'),
      orElse: () => ThemeMode.system,
    );
    final protectedValues = await Future.wait([
      _readProtected(preferences, _businessGstinKey),
      _readProtected(preferences, _bankNameKey),
      _readProtected(preferences, _bankBranchKey),
      _readProtected(preferences, _bankAccountKey),
      _readProtected(preferences, _bankIfscKey),
      _readProtected(preferences, _upiIdKey),
      _readProtected(preferences, _panKey),
    ]);
    isGstRegistered.value = preferences.getBool(_gstRegisteredKey) ?? false;
    defaultDueDay.value = preferences.getInt(_defaultDueDayKey) ?? 7;
    defaultTerms.value = preferences.getString(_defaultTermsKey) ?? '';
    quotationTerms.value = DocumentDefaults.resolve(
      preferences.getString(_quotationTermsKey) ?? defaultTerms.value,
      isQuotation: true,
    );
    invoiceTerms.value = DocumentDefaults.resolve(
      preferences.getString(_invoiceTermsKey) ?? defaultTerms.value,
      isQuotation: false,
    );
    profile.value = {
      'ownerName': preferences.getString(_ownerNameKey) ?? '',
      'name': preferences.getString(_businessNameKey) ?? '',
      'address': preferences.getString(_businessAddressKey) ?? '',
      'gstin': protectedValues[0],
      'phone': preferences.getString(_businessPhoneKey) ?? '',
      'email': preferences.getString(_businessEmailKey) ?? '',
      'bankName': protectedValues[1],
      'bankBranch': protectedValues[2],
      'bankAccount': protectedValues[3],
      'ifsc': protectedValues[4],
      'logoPath': preferences.getString(_logoPathKey) ?? '',
      'signaturePath': preferences.getString(_signaturePathKey) ?? '',
      'qrPath': preferences.getString(_qrPathKey) ?? '',
      'upiId': protectedValues[5],
      'pan': protectedValues[6],
      'gstRegistrationType':
          preferences.getString(_gstRegistrationTypeKey) ?? 'Regular',
      'businessState': preferences.getString(_businessStateKey) ?? '',
      'placeOfSupply': preferences.getString(_placeOfSupplyKey) ?? '',
      'financialYear': preferences.getString(_financialYearKey) ?? '',
      'invoicePrefix': preferences.getString(_invoicePrefixKey) ?? 'INV',
      'invoiceTheme': preferences.getString(_invoiceThemeCacheKey) ?? 'white-blue',
      'quotationPrefix': preferences.getString(_quotationPrefixKey) ?? 'QTN',
    };
  }

  static Future<void> syncFromCloud() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await Supabase.instance.client
          .from('business_profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) return;
      isGstRegistered.value = row['gst_registered'] == true;
      defaultDueDay.value = row['default_due_day'] as int? ?? 7;
      quotationTerms.value = DocumentDefaults.resolve(
        row['quotation_terms']?.toString(),
        isQuotation: true,
      );
      invoiceTerms.value = DocumentDefaults.resolve(
        row['invoice_terms']?.toString(),
        isQuotation: false,
      );
      final localMedia = profile.value;
      final logoPath = await _downloadBusinessMedia(
        row['logo_object_path']?.toString() ?? '',
        'logo',
        localMedia['logoPath'] ?? '',
      );
      final signaturePath = await _downloadBusinessMedia(
        row['signature_object_path']?.toString() ?? '',
        'signature',
        localMedia['signaturePath'] ?? '',
      );
      final qrPath = await _downloadBusinessMedia(
        row['qr_object_path']?.toString() ?? '',
        'qr',
        localMedia['qrPath'] ?? '',
      );
      await _saveLocalProfile({
        'ownerName': row['owner_name']?.toString() ?? '',
        'name': row['business_name']?.toString() ?? '',
        'address': row['address']?.toString() ?? '',
        'gstin': row['gstin']?.toString() ?? '',
        'phone': row['phone']?.toString() ?? '',
        'email': row['email']?.toString() ?? '',
        'bankName': row['bank_name']?.toString() ?? '',
        'bankBranch': row['bank_branch']?.toString() ?? '',
        'bankAccount': row['bank_account']?.toString() ?? '',
        'ifsc': row['ifsc']?.toString() ?? '',
        'upiId': row['upi_id']?.toString() ?? '',
        'pan': row['pan']?.toString() ?? '',
        'gstRegistrationType':
            row['gst_registration_type']?.toString() ?? 'Regular',
        'businessState': row['business_state']?.toString() ?? '',
        'placeOfSupply': row['place_of_supply']?.toString() ?? '',
        'financialYear': row['financial_year']?.toString() ?? '',
        'invoicePrefix': row['invoice_prefix']?.toString() ?? 'INV',
        'invoiceTheme': InvoicePalette.resolve(user.userMetadata?['invoice_theme']?.toString()).id,
        'quotationPrefix': row['quotation_prefix']?.toString() ?? 'QTN',
        'logoPath': logoPath,
        'signaturePath': signaturePath,
        'qrPath': qrPath,
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_gstRegisteredKey, isGstRegistered.value);
      if (defaultDueDay.value == null) {
        await preferences.remove(_defaultDueDayKey);
      } else {
        await preferences.setInt(_defaultDueDayKey, defaultDueDay.value!);
      }
      await preferences.setString(_quotationTermsKey, quotationTerms.value);
      await preferences.setString(_invoiceTermsKey, invoiceTerms.value);
    } on PostgrestException catch (error) {
      // Allows the local cache to keep working until the migration is applied.
      if (error.code != '42P01' && error.code != 'PGRST205') rethrow;
    }
  }

  static Future<void> setGstRegistered(bool value) async {
    isGstRegistered.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_gstRegisteredKey, value);
  }

  static Future<void> setDefaultDueDay(int? value) async {
    defaultDueDay.value = value;
    final preferences = await SharedPreferences.getInstance();
    if (value == null) {
      await preferences.remove(_defaultDueDayKey);
    } else {
      await preferences.setInt(_defaultDueDayKey, value);
    }
  }

  /* Invoice picker helpers belong to _InvoiceBuilderPageState.
  Future<void> _chooseCustomer() async {
    try {
      final rows = await Supabase.instance.client
          .from('customers')
          .select('name, phone, email')
          .order('name')
          .limit(100);
      if (!mounted) return;
      final customer = await _showCustomerPicker(
        List<Map<String, dynamic>>.from(rows),
      );
      if (customer == null || !mounted) return;
      setState(() {
        _customerController.text = customer['name']?.toString() ?? '';
        _customerPhoneController.text = customer['phone']?.toString() ?? '';
        _customerEmailController.text = customer['email']?.toString() ?? '';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load customers: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showCustomerPicker(
    List<Map<String, dynamic>> customers,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final matches = customers.where((customer) {
              final searchable = '${customer['name'] ?? ''} ${customer['phone'] ?? ''} ${customer['email'] ?? ''}'.toLowerCase();
              return searchable.contains(query);
            }).toList();
            return AlertDialog(
              title: const Text('Select customer'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (value) => setDialogState(
                        () => query = value.trim().toLowerCase(),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search name, phone, or email',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: matches.isEmpty
                          ? const Center(child: Text('No saved customers found'))
                          : ListView.builder(
                              itemCount: matches.length,
                              itemBuilder: (_, index) {
                                final customer = matches[index];
                                final contact = [
                                  customer['phone'],
                                  customer['email'],
                                ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');
                                return ListTile(
                                  title: Text(customer['name']?.toString() ?? 'Unnamed customer'),
                                  subtitle: contact.isEmpty ? null : Text(contact),
                                  onTap: () => Navigator.of(context).pop(customer),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _chooseProduct(InvoiceLineItem item) async {
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id, name, product_type, selling_price, uqc_code, gst_rate')
          .eq('is_active', true)
          .order('name')
          .limit(100);
      if (!mounted) return;
      final product = await _showProductPicker(List<Map<String, dynamic>>.from(rows));
      if (product == null || !mounted) return;
      setState(() {
        item.productId = product['id']?.toString();
        item.uqcCode = product['uqc_code']?.toString();
        item.productController.text = product['name']?.toString() ?? '';
        final price = product['selling_price'];
        if (price != null) item.rateController.text = price.toString();
        // This is only a saved business default. The invoice field remains
        // editable so the user confirms or changes the tax rate per invoice.
        final gstRate = product['gst_rate'];
        if (gstRate != null) item.gstRateController.text = gstRate.toString();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load products: $e')),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showProductPicker(
    List<Map<String, dynamic>> products,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final matches = products.where((product) {
              final searchable = '${product['name'] ?? ''} ${product['product_type'] ?? ''} ${product['uqc_code'] ?? ''}'.toLowerCase();
              return searchable.contains(query);
            }).toList();
            return AlertDialog(
              title: const Text('Select product or service'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (value) => setDialogState(
                        () => query = value.trim().toLowerCase(),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search products and services',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: matches.isEmpty
                          ? const Center(child: Text('No saved products or services found'))
                          : ListView.builder(
                              itemCount: matches.length,
                              itemBuilder: (_, index) {
                                final product = matches[index];
                                final details = [
                                  product['product_type']?.toString(),
                                  product['uqc_code']?.toString(),
                                  if (product['selling_price'] != null) '₹${product['selling_price']}',
                                ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');
                                return ListTile(
                                  title: Text(product['name']?.toString() ?? 'Unnamed item'),
                                  subtitle: details.isEmpty ? null : Text(details),
                                  onTap: () => Navigator.of(context).pop(product),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  */

  static Future<void> setDefaultTerms(String value) async {
    defaultTerms.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_defaultTermsKey, value);
  }

  static Future<void> setDocumentTerms({
    required String quotation,
    required String invoice,
  }) async {
    quotationTerms.value = quotation;
    invoiceTerms.value = invoice;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_quotationTermsKey, quotation);
    await preferences.setString(_invoiceTermsKey, invoice);
  }

  static Future<void> saveProfile(Map<String, String> value) async {
    await _saveLocalProfile(value);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final mediaPaths = await Future.wait([
      _uploadBusinessMedia(value['logoPath'] ?? '', 'logo', user.id),
      _uploadBusinessMedia(value['signaturePath'] ?? '', 'signature', user.id),
      _uploadBusinessMedia(value['qrPath'] ?? '', 'qr', user.id),
    ]);
    await Supabase.instance.client.from('business_profiles').upsert({
      'user_id': user.id,
      'owner_name': value['ownerName'] ?? '',
      'business_name': value['name'] ?? '',
      'address': value['address'] ?? '',
      'gst_registered': isGstRegistered.value,
      'gstin': value['gstin'] ?? '',
      'phone': value['phone'] ?? '',
      'email': value['email'] ?? '',
      'bank_name': value['bankName'] ?? '',
      'bank_branch': value['bankBranch'] ?? '',
      'bank_account': value['bankAccount'] ?? '',
      'ifsc': value['ifsc'] ?? '',
      'upi_id': value['upiId'] ?? '',
      'quotation_terms': quotationTerms.value,
      'invoice_terms': invoiceTerms.value,
      'default_due_day': defaultDueDay.value,
      'pan': value['pan'] ?? '',
      'gst_registration_type': value['gstRegistrationType'] ?? 'Regular',
      'business_state': value['businessState'] ?? '',
      'place_of_supply': value['placeOfSupply'] ?? '',
      'financial_year': value['financialYear'] ?? '',
      'invoice_prefix': value['invoicePrefix'] ?? 'INV',
      'quotation_prefix': value['quotationPrefix'] ?? 'QTN',
      'logo_object_path': mediaPaths[0],
      'signature_object_path': mediaPaths[1],
      'qr_object_path': mediaPaths[2],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await Supabase.instance.client.auth.updateUser(UserAttributes(data: {
      'invoice_theme': InvoicePalette.resolve(value['invoiceTheme']).id,
    }));
  }

  static Future<void> _saveLocalProfile(Map<String, String> value) async {
    profile.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_invoiceThemeCacheKey, InvoicePalette.resolve(value['invoiceTheme']).id);
    await preferences.setString(_ownerNameKey, value['ownerName'] ?? '');
    await preferences.setString(_businessNameKey, value['name'] ?? '');
    await preferences.setString(_businessAddressKey, value['address'] ?? '');
    await _writeProtected(preferences, _businessGstinKey, value['gstin'] ?? '');
    await preferences.setString(_businessPhoneKey, value['phone'] ?? '');
    await preferences.setString(_businessEmailKey, value['email'] ?? '');
    await _writeProtected(preferences, _bankNameKey, value['bankName'] ?? '');
    await _writeProtected(
      preferences,
      _bankBranchKey,
      value['bankBranch'] ?? '',
    );
    await _writeProtected(
      preferences,
      _bankAccountKey,
      value['bankAccount'] ?? '',
    );
    await _writeProtected(preferences, _bankIfscKey, value['ifsc'] ?? '');
    await preferences.setString(_logoPathKey, value['logoPath'] ?? '');
    await preferences.setString(
      _signaturePathKey,
      value['signaturePath'] ?? '',
    );
    await preferences.setString(_qrPathKey, value['qrPath'] ?? '');
    await _writeProtected(preferences, _upiIdKey, value['upiId'] ?? '');
    await _writeProtected(preferences, _panKey, value['pan'] ?? '');
    await preferences.setString(
      _gstRegistrationTypeKey,
      value['gstRegistrationType'] ?? 'Regular',
    );
    await preferences.setString(
      _businessStateKey,
      value['businessState'] ?? '',
    );
    await preferences.setString(
      _placeOfSupplyKey,
      value['placeOfSupply'] ?? '',
    );
    await preferences.setString(
      _financialYearKey,
      value['financialYear'] ?? '',
    );
    await preferences.setString(
      _invoicePrefixKey,
      value['invoicePrefix'] ?? 'INV',
    );
    await preferences.setString(
      _quotationPrefixKey,
      value['quotationPrefix'] ?? 'QTN',
    );
  }
}

class BusinessSettingsPage extends StatefulWidget {
  const BusinessSettingsPage({super.key});

  @override
  State<BusinessSettingsPage> createState() => _BusinessSettingsPageState();
}

class _BusinessSettingsPageState extends State<BusinessSettingsPage> {
  Future<void> _previewInvoiceTheme() async {
    final sample = InvoiceLineItem();
    sample.productController.text = 'Sample product';
    sample.quantityController.text = '2';
    sample.rateController.text = '500';
    sample.gstRateController.text = '18';
    final previewProfile = <String, String>{
      ...BusinessSettings.profile.value,
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'phone': _phoneController.text.trim(), 'email': _emailController.text.trim(),
      'gstin': _gstinController.text.trim(),
      'bankName': _bankNameController.text.trim(), 'bankBranch': _branchController.text.trim(),
      'bankAccount': _accountController.text.trim(), 'ifsc': _ifscController.text.trim(),
      'upiId': _upiController.text.trim(),
      'logoPath': _logoPath, 'signaturePath': _signaturePath, 'qrPath': _qrPath,
      'businessState': _stateController.text.trim(), 'invoiceTheme': _invoiceTheme,
    };
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InvoicePreviewPage(
        customerName: 'Sample Customer', customerPhone: '', customerEmail: '',
        placeOfSupply: _stateController.text.trim(), invoiceDate: DateTime.now(),
        dueDate: DateTime.now().add(const Duration(days: 7)),
        terms: _invoiceTermsController.text, items: [sample],
        invoiceNumber: 'SAMPLE-001', balanceDue: 1180,
        previewProfile: previewProfile,
      )));
    } finally { sample.dispose(); }
  }

  final _formKey = GlobalKey<FormState>();
  late String _invoiceTheme;
  late final TextEditingController _quotationTermsController;
  late final TextEditingController _invoiceTermsController;
  late final TextEditingController _ownerController;
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _gstinController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _branchController;
  late final TextEditingController _accountController;
  late final TextEditingController _ifscController;
  late final TextEditingController _upiController;
  late final TextEditingController _panController;
  late final TextEditingController _stateController;
  late final TextEditingController _placeOfSupplyController;
  late final TextEditingController _financialYearController;
  late final TextEditingController _invoicePrefixController;
  late final TextEditingController _quotationPrefixController;
  String _gstRegistrationType = 'Regular';
  bool _isLookingUpIfsc = false;
  String? _ifscLookupMessage;
  String? _lastLookedUpIfsc;
  String _logoPath = '';
  String _signaturePath = '';
  String _qrPath = '';

  @override
  void initState() {
    super.initState();
    _quotationTermsController = TextEditingController(
      text: BusinessSettings.quotationTerms.value,
    );
    _invoiceTermsController = TextEditingController(
      text: BusinessSettings.invoiceTerms.value,
    );
    final profile = BusinessSettings.profile.value;
    _invoiceTheme = InvoicePalette.resolve(profile['invoiceTheme']).id;
    _ownerController = TextEditingController(text: profile['ownerName']);
    _nameController = TextEditingController(text: profile['name']);
    _addressController = TextEditingController(text: profile['address']);
    _gstinController = TextEditingController(text: profile['gstin']);
    _phoneController = TextEditingController(
      text: _normaliseIndianMobile(profile['phone'] ?? ''),
    );
    _emailController = TextEditingController(text: profile['email']);
    _bankNameController = TextEditingController(text: profile['bankName']);
    _branchController = TextEditingController(text: profile['bankBranch']);
    _accountController = TextEditingController(text: profile['bankAccount']);
    _ifscController = TextEditingController(text: profile['ifsc']);
    _upiController = TextEditingController(text: profile['upiId']);
    _panController = TextEditingController(text: profile['pan']);
    _stateController = TextEditingController(text: profile['businessState']);
    _placeOfSupplyController = TextEditingController(
      text: profile['placeOfSupply'],
    );
    _financialYearController = TextEditingController(
      text: profile['financialYear'],
    );
    _invoicePrefixController = TextEditingController(
      text: profile['invoicePrefix'] ?? 'INV',
    );
    _quotationPrefixController = TextEditingController(
      text: profile['quotationPrefix'] ?? 'QTN',
    );
    _gstRegistrationType = profile['gstRegistrationType'] ?? 'Regular';
    _logoPath = profile['logoPath'] ?? '';
    _signaturePath = profile['signaturePath'] ?? '';
    _qrPath = profile['qrPath'] ?? '';
  }

  @override
  void dispose() {
    _quotationTermsController.dispose();
    _invoiceTermsController.dispose();
    _ownerController.dispose();
    _nameController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bankNameController.dispose();
    _branchController.dispose();
    _accountController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    _panController.dispose();
    _stateController.dispose();
    _placeOfSupplyController.dispose();
    _financialYearController.dispose();
    _invoicePrefixController.dispose();
    _quotationPrefixController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String type) async {
    final path = await _pickAndEditImage(
      context,
      label: type == 'qr' ? 'payment QR' : type,
    );
    if (path == null || !mounted) return;
    setState(() {
      if (type == 'logo') _logoPath = path;
      if (type == 'signature') _signaturePath = path;
      if (type == 'qr') _qrPath = path;
    });
  }

  Future<void> _drawSignature() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => const _SignaturePadDialog(),
    );
    if (path != null && mounted) setState(() => _signaturePath = path);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _normaliseIndianMobile(_phoneController.text);
    _phoneController.value = TextEditingValue(
      text: phone,
      selection: TextSelection.collapsed(offset: phone.length),
    );
    await BusinessSettings.saveProfile({
      'ownerName': _ownerController.text.trim(),
      'name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'gstin': _gstinController.text.trim().toUpperCase(),
      'phone': phone,
      'email': _emailController.text.trim(),
      'bankName': _bankNameController.text.trim(),
      'bankBranch': _branchController.text.trim(),
      'bankAccount': _accountController.text.trim(),
      'ifsc': _ifscController.text.trim(),
      'logoPath': _logoPath,
      'signaturePath': _signaturePath,
      'qrPath': _qrPath,
      'upiId': _upiController.text.trim().toLowerCase(),
      'pan': _panController.text.trim().toUpperCase(),
      'gstRegistrationType': _gstRegistrationType,
      'businessState': _stateController.text.trim(),
      'placeOfSupply': _placeOfSupplyController.text.trim(),
      'financialYear': _financialYearController.text.trim(),
      'invoicePrefix': _invoicePrefixController.text.trim().toUpperCase(),
      'quotationPrefix': _quotationPrefixController.text.trim().toUpperCase(),
      'invoiceTheme': _invoiceTheme,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Business profile saved')));
  }

  Future<void> _lookupIfsc(String value) async {
    final ifsc = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)) {
      if (mounted) setState(() => _ifscLookupMessage = null);
      return;
    }
    if (_isLookingUpIfsc || _lastLookedUpIfsc == ifsc) return;
    _lastLookedUpIfsc = ifsc;
    setState(() {
      _isLookingUpIfsc = true;
      _ifscLookupMessage = null;
    });
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('https://ifsc.razorpay.com/$ifsc'),
      );
      final response = await request.close();
      if (response.statusCode == 404) {
        if (mounted) {
          setState(
            () =>
                _ifscLookupMessage = 'No bank branch was found for this IFSC.',
          );
        }
        return;
      }
      if (response.statusCode != 200) {
        if (mounted) {
          setState(
            () => _ifscLookupMessage = 'Unable to verify the IFSC right now.',
          );
        }
        return;
      }
      final data =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _bankNameController.text = data['BANK']?.toString() ?? '';
        _branchController.text = data['BRANCH']?.toString() ?? '';
        _ifscLookupMessage = 'Bank and branch filled from IFSC.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _ifscLookupMessage =
              'Unable to verify the IFSC right now. Check your connection.',
        );
      }
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _isLookingUpIfsc = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Business Profile & Settings'),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: BusinessSettings.isGstRegistered,
        builder: (context, isGstRegistered, _) {
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const DesignSelector(),
                const SizedBox(height: 24),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: BusinessSettings.themeMode,
                  builder: (context, mode, _) =>
                      DropdownButtonFormField<ThemeMode>(
                        initialValue: mode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Appearance',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('System default'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        onChanged: (value) async {
                          if (value != null) {
                            await BusinessSettings.setThemeMode(value);
                          }
                        },
                      ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Invoice colours',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: InvoicePalette.options.map((palette) => ChoiceChip(
                  label: Text(palette.label),
                  avatar: CircleAvatar(backgroundColor: palette.inkColor, child: Icon(Icons.receipt_outlined, color: palette.paperColor, size: 18)),
                  selected: _invoiceTheme == palette.id,
                  onSelected: (_) => setState(() => _invoiceTheme = palette.id),
                )).toList()),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _previewInvoiceTheme,
                  icon: const Icon(Icons.preview_outlined), label: const Text('Preview invoice format')),
                const Text('Save business profile to use this format for your invoices.'),
                const SizedBox(height: 24),
                Text(
                  'Business details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _profileField(
                  _ownerController,
                  'Owner name',
                  validator: (value) =>
                      value.trim().isEmpty ? 'Enter the owner name' : null,
                ),
                const SizedBox(height: 12),
                _profileField(
                  _nameController,
                  'Business name',
                  validator: (value) => value.trim().length < 2
                      ? 'Enter the business name'
                      : null,
                ),
                const SizedBox(height: 12),
                _profileField(
                  _addressController,
                  'Business address',
                  lines: 2,
                  validator: (value) => value.trim().length < 5
                      ? 'Enter a complete business address'
                      : null,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      _profileField(
                        _gstinController,
                        'GSTIN',
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (_, value) => value.copyWith(
                              text: value.text.toUpperCase(),
                              selection: value.selection,
                            ),
                          ),
                        ],
                        validator: (value) {
                          final gstin = value.trim().toUpperCase();
                          if (gstin.isEmpty) {
                            return isGstRegistered ? 'GSTIN is required' : null;
                          }
                          return RegExp(
                                r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                              ).hasMatch(gstin)
                              ? null
                              : 'Enter a valid 15-character GSTIN';
                        },
                      ),
                      _profileField(
                        _phoneController,
                        'Phone',
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_IndianMobileFormatter()],
                        validator: (value) {
                          final phone = _normaliseIndianMobile(value);
                          return phone.isEmpty ||
                                  RegExp(r'^[6-9][0-9]{9}$').hasMatch(phone)
                              ? null
                              : 'Enter a valid 10-digit mobile number';
                        },
                      ),
                    ];
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 12),
                          fields[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _profileField(
                  _emailController,
                  'Email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final email = value.trim();
                    if (email.isEmpty) return null;
                    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                        ? null
                        : 'Enter a valid email address';
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Tax and numbering',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _profileField(
                  _panController,
                  'PAN',
                  validator: (value) =>
                      value.trim().isEmpty ||
                          RegExp(
                            r'^[A-Z]{5}[0-9]{4}[A-Z]$',
                          ).hasMatch(value.trim().toUpperCase())
                      ? null
                      : 'Enter a valid PAN',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gstRegistrationType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'GST registration type',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      const ['Regular', 'Composition', 'Casual', 'Non-resident']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _gstRegistrationType = value!),
                ),
                const SizedBox(height: 12),
                SearchableStateField(
                  initialValue:
                      _indianStatesAndUnionTerritories.contains(
                        _stateController.text,
                      )
                      ? _stateController.text
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Business state',
                    border: OutlineInputBorder(),
                  ),
                  items: _indianStatesAndUnionTerritories
                      .map(
                        (state) =>
                            DropdownMenuItem(value: state, child: Text(state)),
                      )
                      .toList(),
                  onChanged: (value) => _stateController.text = value ?? '',
                  validator: (value) => value == null ? 'Select a state' : null,
                ),
                const SizedBox(height: 12),
                SearchableStateField(
                  initialValue:
                      _indianStatesAndUnionTerritories.contains(
                        _placeOfSupplyController.text,
                      )
                      ? _placeOfSupplyController.text
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Default place of supply',
                    border: OutlineInputBorder(),
                  ),
                  items: _indianStatesAndUnionTerritories
                      .map(
                        (state) =>
                            DropdownMenuItem(value: state, child: Text(state)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      _placeOfSupplyController.text = value ?? '',
                  validator: (value) => value == null ? 'Select a state' : null,
                ),
                const SizedBox(height: 12),
                _profileField(
                  _financialYearController,
                  'Financial year (example: 2026-27)',
                  validator: (value) =>
                      RegExp(r'^20[0-9]{2}-[0-9]{2}$').hasMatch(value.trim())
                      ? null
                      : 'Use format 2026-27',
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fields = [
                      _profileField(
                        _invoicePrefixController,
                        'Invoice prefix',
                        validator: (value) => _prefixValidator(value),
                      ),
                      _profileField(
                        _quotationPrefixController,
                        'Quotation prefix',
                        validator: (value) => _prefixValidator(value),
                      ),
                    ];
                    if (constraints.maxWidth < 520) {
                      return Column(
                        children: [
                          fields[0],
                          const SizedBox(height: 12),
                          fields[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Invoice branding',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _imageControl('Logo', _logoPath, () => _pickImage('logo')),
                    _imageControl(
                      'Signature',
                      _signaturePath,
                      () => _pickImage('signature'),
                    ),
                    _imageControl(
                      'Payment QR',
                      _qrPath,
                      () => _pickImage('qr'),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: _drawSignature,
                    icon: const Icon(Icons.draw_outlined),
                    label: const Text('Draw signature'),
                  ),
                ),
                const SizedBox(height: 12),
                _profileField(
                  _upiController,
                  'UPI ID',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      value.trim().isEmpty || _isValidUpiId(value)
                      ? null
                      : 'Enter a valid UPI ID',
                ),
                if (_isValidUpiId(_upiController.text)) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        QrImageView(
                          data: _upiPaymentUri(
                            _upiController.text,
                            _nameController.text,
                          ),
                          size: 170,
                        ),
                        const Text('Automatically generated UPI payment QR'),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Bank details',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _profileField(
                  _ifscController,
                  'IFSC code',
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (_, value) => value.copyWith(
                        text: value.text.toUpperCase(),
                        selection: value.selection,
                      ),
                    ),
                  ],
                  onChanged: _lookupIfsc,
                  validator: (value) {
                    final ifsc = value.trim().toUpperCase();
                    return ifsc.isEmpty ||
                            RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc)
                        ? null
                        : 'Enter a valid IFSC code';
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Enter the IFSC Code to prefill bank and branch details',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_isLookingUpIfsc || _ifscLookupMessage != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_isLookingUpIfsc)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      if (_isLookingUpIfsc) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isLookingUpIfsc
                              ? 'Looking up bank and branch...'
                              : _ifscLookupMessage!,
                          style: TextStyle(
                            color:
                                _ifscLookupMessage?.startsWith('Bank and') ==
                                    true
                                ? Colors.green.shade700
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _profileField(
                  _bankNameController,
                  'Bank name',
                  validator: (value) =>
                      value.trim().isEmpty || value.trim().length >= 2
                      ? null
                      : 'Enter a valid bank name',
                ),
                const SizedBox(height: 12),
                _profileField(
                  _branchController,
                  'Branch',
                  validator: (value) =>
                      value.trim().isEmpty || value.trim().length >= 2
                      ? null
                      : 'Enter a valid branch name',
                ),
                const SizedBox(height: 12),
                _profileField(
                  _accountController,
                  'Account number',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    final account = value.trim();
                    return account.isEmpty ||
                            RegExp(r'^[0-9]{9,18}$').hasMatch(account)
                        ? null
                        : 'Use 9 to 18 digits';
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save business profile'),
                ),
                const SizedBox(height: 20),
                Card(
                  child: SwitchListTile(
                    title: const Text('GST registered business'),
                    subtitle: const Text(
                      'Controls GST-only fields in product creation. Signup will set this automatically when implemented.',
                    ),
                    value: isGstRegistered,
                    onChanged: BusinessSettings.setGstRegistered,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ValueListenableBuilder<int?>(
                      valueListenable: BusinessSettings.defaultDueDay,
                      builder: (context, dueDay, _) => TextFormField(
                        initialValue: (dueDay ?? 7).toString(),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Invoices due after (days)',
                          helperText:
                              'Prefilled with 7 days. Each invoice can change it.',
                          suffixText: 'days',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final days = int.tryParse(value ?? '');
                          return days != null && days >= 0 && days <= 365
                              ? null
                              : 'Enter 0 to 365 days';
                        },
                        onChanged: (value) {
                          final days = int.tryParse(value);
                          if (days != null && days >= 0 && days <= 365) {
                            BusinessSettings.setDefaultDueDay(days);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default quotation and invoice terms',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _quotationTermsController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Quotation terms',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _invoiceTermsController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Invoice terms',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () async {
                            await BusinessSettings.setDocumentTerms(
                              quotation: _quotationTermsController.text.trim(),
                              invoice: _invoiceTermsController.text.trim(),
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text('Default document terms saved'),
                              ),
                            );
                          },
                          child: const Text('Save terms'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _profileField(
    TextEditingController controller,
    String label, {
    int lines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
    String? Function(String value)? validator,
  }) => TextFormField(
    controller: controller,
    minLines: lines,
    maxLines: lines,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    validator: validator == null ? null : (value) => validator(value ?? ''),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _imageControl(String label, String path, VoidCallback onPick) =>
      Expanded(
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 100,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Expanded(
                  child: path.isNotEmpty && File(path).existsSync()
                      ? Image.file(File(path), fit: BoxFit.contain)
                      : const Icon(Icons.add_photo_alternate_outlined),
                ),
                Text(label, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
}

class AddProductPage extends StatefulWidget {
  const AddProductPage({
    super.key,
    this.product,
    this.initialName,
    this.returnRecord = false,
  });
  final bool returnRecord;

  final Map<String, dynamic>? product;
  final String? initialName;

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  List<Map<String, dynamic>> _invoices = [];
  String? _invoiceId;
  String _method = 'upi';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final syncedPayments = await OfflineStore.flushPayments();
      final rows = await Supabase.instance.client
          .from('invoices')
          .select(
            'id, invoice_number, customer_name, invoice_date, balance_amount',
          )
          .gt('balance_amount', 0)
          .order('invoice_date', ascending: false);
      if (mounted) {
        setState(() => _invoices = List<Map<String, dynamic>>.from(rows));
        if (syncedPayments > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$syncedPayments offline payment(s) synced'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to load invoices: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _invoiceId == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc(
        'record_invoice_payment',
        params: {
          'p_invoice_id': _invoiceId,
          'p_amount': double.parse(_amountController.text.trim()),
          'p_payment_method': _method,
        },
      );
      if (!mounted) return;
      _amountController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded successfully')),
      );
      await _load();
    } catch (e) {
      if (_isOfflineError(e)) {
        await OfflineStore.enqueue('payments', {
          'p_invoice_id': _invoiceId,
          'p_amount': double.parse(_amountController.text.trim()),
          'p_payment_method': _method,
        });
        if (mounted) {
          _amountController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Payment saved offline and will sync automatically',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Payment was not recorded: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record Payment')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(_invoiceId),
                    initialValue: _invoiceId,
                    decoration: const InputDecoration(
                      labelText: 'Outstanding invoice',
                      helperText: 'Invoice number • party • invoice date',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: _invoices
                        .map(
                          (invoice) => DropdownMenuItem(
                            value: invoice['id'].toString(),
                            child: Text(
                              '${invoice['invoice_number']} • ${invoice['customer_name']} • ${invoice['invoice_date']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _invoiceId = value),
                    validator: (value) =>
                        value == null ? 'Select an invoice' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Payment amount',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        double.tryParse(value ?? '') == null ||
                            double.parse(value!) <= 0
                        ? 'Enter a valid amount'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_method),
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        const ['cash', 'upi', 'bank_transfer', 'card', 'cheque']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setState(() => _method = value ?? 'upi'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Record payment'),
                  ),
                ],
              ),
            ),
          ),
  );
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _invoiceItems = [];
  DateTimeRange? _reportPeriod;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('invoices')
          .select(
            'id, invoice_number, customer_name, customer_gstin, invoice_date, status, place_of_supply, tax_type, subtotal, tax_amount, cgst_amount, sgst_amount, igst_amount, total_amount, paid_amount, balance_amount',
          )
          .order('invoice_date', ascending: false)
          .limit(500);
      final itemRows = await Supabase.instance.client
          .from('invoice_items')
          .select(
            'invoice_id, item_name, quantity, taxable_amount, tax_amount, total_amount',
          )
          .limit(5000);
      if (mounted) {
        setState(() {
          _invoices = List<Map<String, dynamic>>.from(rows);
          _invoiceItems = List<Map<String, dynamic>>.from(itemRows);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  String _money(double value) => '₹${value.toStringAsFixed(2)}';

  DateTime? _invoiceDate(Map<String, dynamic> invoice) =>
      DateTime.tryParse(invoice['invoice_date']?.toString() ?? '');

  bool _isInReportPeriod(Map<String, dynamic> invoice) {
    final period = _reportPeriod;
    if (period == null) return true;
    final date = _invoiceDate(invoice);
    if (date == null) return false;
    final day = DateUtils.dateOnly(date);
    return !day.isBefore(DateUtils.dateOnly(period.start)) &&
        !day.isAfter(DateUtils.dateOnly(period.end));
  }

  String _shortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _selectReportPeriod() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _reportPeriod,
      helpText: 'Select report period',
      saveText: 'Apply',
    );
    if (selected != null && mounted) {
      setState(() => _reportPeriod = selected);
    }
  }

  Map<String, Map<String, double>> _customerSummary(
    List<Map<String, dynamic>> rows,
  ) {
    final result = <String, Map<String, double>>{};
    for (final invoice in rows) {
      final name = invoice['customer_name']?.toString().trim();
      final key = name == null || name.isEmpty ? 'Unnamed customer' : name;
      final summary = result.putIfAbsent(
        key,
        () => {'count': 0, 'sales': 0, 'tax': 0, 'outstanding': 0},
      );
      summary['count'] = summary['count']! + 1;
      summary['sales'] = summary['sales']! + _amount(invoice['total_amount']);
      summary['tax'] = summary['tax']! + _amount(invoice['tax_amount']);
      summary['outstanding'] =
          summary['outstanding']! + _amount(invoice['balance_amount']);
    }
    return result;
  }

  Map<String, Map<String, double>> _itemSummary(Set<String> invoiceIds) {
    final result = <String, Map<String, double>>{};
    for (final item in _invoiceItems.where(
      (row) => invoiceIds.contains(row['invoice_id']?.toString()),
    )) {
      final name = item['item_name']?.toString().trim();
      final key = name == null || name.isEmpty ? 'Unnamed item' : name;
      final summary = result.putIfAbsent(
        key,
        () => {'quantity': 0, 'taxable': 0, 'tax': 0, 'sales': 0},
      );
      summary['quantity'] = summary['quantity']! + _amount(item['quantity']);
      summary['taxable'] =
          summary['taxable']! + _amount(item['taxable_amount']);
      summary['tax'] = summary['tax']! + _amount(item['tax_amount']);
      summary['sales'] = summary['sales']! + _amount(item['total_amount']);
    }
    return result;
  }

  List<String> _gstrValidationIssues(Map<String, dynamic> invoice) {
    final issues = <String>[];
    final gstin =
        invoice['customer_gstin']?.toString().trim().toUpperCase() ?? '';
    final tax = _amount(invoice['tax_amount']);
    final cgst = _amount(invoice['cgst_amount']);
    final sgst = _amount(invoice['sgst_amount']);
    final igst = _amount(invoice['igst_amount']);
    if ((invoice['invoice_number']?.toString().trim() ?? '').isEmpty) {
      issues.add('Missing invoice number');
    }
    if (_invoiceDate(invoice) == null) issues.add('Invalid invoice date');
    if (gstin.isNotEmpty &&
        !RegExp(
          r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
        ).hasMatch(gstin)) {
      issues.add('Invalid customer GSTIN');
    }
    if (tax > 0 &&
        (invoice['place_of_supply']?.toString().trim() ?? '').isEmpty) {
      issues.add('Missing place of supply');
    }
    if ((tax - (cgst + sgst + igst)).abs() > 0.02) {
      issues.add('GST components do not match total tax');
    }
    if (igst > 0 && (cgst > 0 || sgst > 0)) {
      issues.add('Invoice mixes IGST and CGST/SGST');
    }
    if ((cgst - sgst).abs() > 0.02 && igst == 0) {
      issues.add('CGST and SGST are not equal');
    }
    return issues;
  }

  List<Map<String, dynamic>> get _exportInvoices => _invoices
      .where(
        (invoice) =>
            invoice['status']?.toString() != 'cancelled' &&
            invoice['status']?.toString() != 'draft' &&
            _isInReportPeriod(invoice),
      )
      .toList();

  String get _periodSlug {
    final period = _reportPeriod;
    if (period == null) return 'all_dates';
    String compact(DateTime date) =>
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return '${compact(period.start)}_${compact(period.end)}';
  }

  String _csvCell(dynamic value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  List<dynamic> _exportRow(Map<String, dynamic> invoice) => [
    invoice['invoice_number'],
    invoice['invoice_date'],
    invoice['customer_name'],
    invoice['customer_gstin'],
    invoice['place_of_supply'],
    invoice['status'],
    _amount(invoice['subtotal']),
    _amount(invoice['cgst_amount']),
    _amount(invoice['sgst_amount']),
    _amount(invoice['igst_amount']),
    _amount(invoice['tax_amount']),
    _amount(invoice['total_amount']),
    _amount(invoice['paid_amount']),
    _amount(invoice['balance_amount']),
  ];

  static const _exportHeaders = <String>[
    'Invoice Number',
    'Invoice Date',
    'Customer',
    'Customer GSTIN',
    'Place of Supply',
    'Status',
    'Taxable Value',
    'CGST',
    'SGST',
    'IGST',
    'Total Tax',
    'Invoice Total',
    'Paid',
    'Outstanding',
  ];

  Future<void> _shareExport(
    List<int> bytes, {
    required String filename,
    required String mimeType,
  }) async {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$filename';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Simplek report export',
        text: 'Simplek report for the selected period.',
        files: [XFile(path, mimeType: mimeType)],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final lines = <String>[
      _exportHeaders.map(_csvCell).join(','),
      ..._exportInvoices.map(
        (invoice) => _exportRow(invoice).map(_csvCell).join(','),
      ),
    ];
    await _shareExport(
      utf8.encode('\uFEFF${lines.join('\r\n')}'),
      filename: 'simplek_gstr1_$_periodSlug.csv',
      mimeType: 'text/csv',
    );
  }

  Future<void> _exportExcel() async {
    final workbook = xlsx.Excel.createExcel();
    final sheet = workbook['GSTR-1'];
    sheet.appendRow(
      _exportHeaders.map((value) => xlsx.TextCellValue(value)).toList(),
    );
    for (final invoice in _exportInvoices) {
      final row = _exportRow(invoice);
      sheet.appendRow(
        row
            .map<xlsx.CellValue>(
              (value) => value is num
                  ? xlsx.DoubleCellValue(value.toDouble())
                  : xlsx.TextCellValue(value?.toString() ?? ''),
            )
            .toList(),
      );
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Unable to create Excel workbook.');
    await _shareExport(
      bytes,
      filename: 'simplek_gstr1_$_periodSlug.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  String _xml(dynamic value) => (value?.toString() ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  Future<void> _exportTallyXml() async {
    final company = BusinessSettings.profile.value['name'] ?? 'Simplek';
    final vouchers = _exportInvoices.map((invoice) {
      return '''<TALLYMESSAGE xmlns:UDF="TallyUDF">
<VOUCHER VCHTYPE="Sales" ACTION="Create">
<DATE>${_xml(invoice['invoice_date']?.toString().replaceAll('-', ''))}</DATE>
<VOUCHERTYPENAME>Sales</VOUCHERTYPENAME>
<VOUCHERNUMBER>${_xml(invoice['invoice_number'])}</VOUCHERNUMBER>
<PARTYLEDGERNAME>${_xml(invoice['customer_name'])}</PARTYLEDGERNAME>
<PARTYGSTIN>${_xml(invoice['customer_gstin'])}</PARTYGSTIN>
<PLACEOFSUPPLY>${_xml(invoice['place_of_supply'])}</PLACEOFSUPPLY>
<AMOUNT>${_amount(invoice['total_amount']).toStringAsFixed(2)}</AMOUNT>
</VOUCHER></TALLYMESSAGE>''';
    }).join();
    final document =
        '''<?xml version="1.0" encoding="UTF-8"?>
<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>
<BODY><IMPORTDATA><REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME>
<STATICVARIABLES><SVCURRENTCOMPANY>${_xml(company)}</SVCURRENTCOMPANY></STATICVARIABLES>
</REQUESTDESC><REQUESTDATA>$vouchers</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>''';
    await _shareExport(
      utf8.encode(document),
      filename: 'simplek_tally_sales_$_periodSlug.xml',
      mimeType: 'application/xml',
    );
  }

  Future<void> _exportPdf() async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => [
          pw.Text(
            'Simplek GSTR-1 Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            _reportPeriod == null
                ? 'All invoice dates'
                : '${_shortDate(_reportPeriod!.start)} to ${_shortDate(_reportPeriod!.end)}',
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: _exportHeaders.take(12).toList(),
            data: _exportInvoices
                .map((invoice) => _exportRow(invoice).take(12).toList())
                .toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 7,
            ),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'simplek_gstr1_$_periodSlug.pdf',
    );
  }

  Future<void> _export(String format) async {
    if (_exportInvoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No non-draft invoices to export.')),
      );
      return;
    }
    try {
      switch (format) {
        case 'csv':
          await _exportCsv();
        case 'xlsx':
          await _exportExcel();
        case 'pdf':
          await _exportPdf();
        case 'xml':
          await _exportTallyXml();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to export report: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _invoices
        .where(
          (invoice) =>
              invoice['status']?.toString() != 'cancelled' &&
              _isInReportPeriod(invoice),
        )
        .toList();
    final sales = active.fold<double>(
      0,
      (sum, invoice) => sum + _amount(invoice['total_amount']),
    );
    final collected = active.fold<double>(
      0,
      (sum, invoice) => sum + _amount(invoice['paid_amount']),
    );
    final outstanding = active.fold<double>(
      0,
      (sum, invoice) => sum + _amount(invoice['balance_amount']),
    );
    final paid = active
        .where((invoice) => invoice['status']?.toString() == 'paid')
        .length;
    final pending = active
        .where(
          (invoice) => [
            'draft',
            'sent',
            'partial',
            'overdue',
          ].contains(invoice['status']?.toString()),
        )
        .length;
    final customers = _customerSummary(active).entries.toList()
      ..sort((a, b) => b.value['sales']!.compareTo(a.value['sales']!));
    final invoiceIds = active.map((row) => row['id']?.toString() ?? '').toSet();
    final items = _itemSummary(invoiceIds).entries.toList()
      ..sort((a, b) => b.value['sales']!.compareTo(a.value['sales']!));
    final filingInvoices = active
        .where((invoice) => invoice['status']?.toString() != 'draft')
        .toList();
    final b2bInvoices = filingInvoices
        .where(
          (invoice) =>
              (invoice['customer_gstin']?.toString().trim() ?? '').isNotEmpty,
        )
        .toList();
    final b2cInvoices = filingInvoices
        .where(
          (invoice) =>
              (invoice['customer_gstin']?.toString().trim() ?? '').isEmpty,
        )
        .toList();
    final invalidInvoices = filingInvoices
        .map(
          (invoice) =>
              (invoice: invoice, issues: _gstrValidationIssues(invoice)),
        )
        .where((entry) => entry.issues.isNotEmpty)
        .toList();
    final filingTaxable = filingInvoices.fold<double>(
      0,
      (sum, row) => sum + _amount(row['subtotal']),
    );
    final filingCgst = filingInvoices.fold<double>(
      0,
      (sum, row) => sum + _amount(row['cgst_amount']),
    );
    final filingSgst = filingInvoices.fold<double>(
      0,
      (sum, row) => sum + _amount(row['sgst_amount']),
    );
    final filingIgst = filingInvoices.fold<double>(
      0,
      (sum, row) => sum + _amount(row['igst_amount']),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export report',
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
              PopupMenuItem(value: 'xml', child: Text('Export TallyPrime XML')),
            ],
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: 'Select report period',
            onPressed: _loading ? null : _selectReportPeriod,
            icon: Icon(
              _reportPeriod == null
                  ? Icons.date_range_outlined
                  : Icons.event_available,
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Unable to load reports:\n$_error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: Text(
                        _reportPeriod == null
                            ? 'All invoice dates'
                            : '${_shortDate(_reportPeriod!.start)} to ${_shortDate(_reportPeriod!.end)}',
                      ),
                      subtitle: const Text(
                        'This period applies to every report below.',
                      ),
                      trailing: _reportPeriod == null
                          ? TextButton(
                              onPressed: _selectReportPeriod,
                              child: const Text('Select'),
                            )
                          : IconButton(
                              tooltip: 'Clear report period',
                              onPressed: () =>
                                  setState(() => _reportPeriod = null),
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Billing summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          'Sales',
                          _money(sales),
                          Icons.trending_up,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metric(
                          'Collected',
                          _money(collected),
                          Icons.payments_outlined,
                          Colors.indigo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          'Outstanding',
                          _money(outstanding),
                          Icons.account_balance_wallet_outlined,
                          Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metric(
                          'Invoices',
                          active.length.toString(),
                          Icons.receipt_long_outlined,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Payment status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _statusMetric('Paid', paid, Colors.green),
                          ),
                          Container(
                            height: 42,
                            width: 1,
                            color: Colors.grey.shade300,
                          ),
                          Expanded(
                            child: _statusMetric(
                              'Pending',
                              pending,
                              Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'GSTR-1 filing tables',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          'B2B invoices',
                          b2bInvoices.length.toString(),
                          Icons.business_outlined,
                          Colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metric(
                          'B2C invoices',
                          b2cInvoices.length.toString(),
                          Icons.person_outline,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: invalidInvoices.isEmpty
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    child: ListTile(
                      leading: Icon(
                        invalidInvoices.isEmpty
                            ? Icons.verified_outlined
                            : Icons.warning_amber_outlined,
                        color: invalidInvoices.isEmpty
                            ? Colors.green.shade700
                            : Colors.orange.shade800,
                      ),
                      title: Text(
                        invalidInvoices.isEmpty
                            ? 'GSTR-1 validation passed'
                            : '${invalidInvoices.length} invoice(s) need attention',
                      ),
                      subtitle: Text(
                        filingInvoices.isEmpty
                            ? 'No non-draft invoices in this period.'
                            : 'Draft invoices are excluded from filing tables.',
                      ),
                    ),
                  ),
                  if (invalidInvoices.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...invalidInvoices.map(
                      (entry) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(
                            entry.invoice['invoice_number']?.toString() ??
                                'Invoice',
                          ),
                          subtitle: Text(entry.issues.join(' • ')),
                        ),
                      ),
                    ),
                  ],
                  Card(
                    child: ExpansionTile(
                      title: Text('B2B supplies (${b2bInvoices.length})'),
                      subtitle: const Text('Registered customers with GSTIN'),
                      children: b2bInvoices.isEmpty
                          ? const [
                              ListTile(
                                title: Text('No B2B invoices in this period.'),
                              ),
                            ]
                          : b2bInvoices
                                .map(
                                  (invoice) => ListTile(
                                    title: Text(
                                      invoice['invoice_number']?.toString() ??
                                          'Invoice',
                                    ),
                                    subtitle: Text(
                                      '${invoice['customer_gstin']} • ${invoice['customer_name']}',
                                    ),
                                    trailing: Text(
                                      _money(_amount(invoice['total_amount'])),
                                    ),
                                  ),
                                )
                                .toList(),
                    ),
                  ),
                  Card(
                    child: ExpansionTile(
                      title: Text('B2C supplies (${b2cInvoices.length})'),
                      subtitle: const Text('Consumers without GSTIN'),
                      children: b2cInvoices.isEmpty
                          ? const [
                              ListTile(
                                title: Text('No B2C invoices in this period.'),
                              ),
                            ]
                          : b2cInvoices
                                .map(
                                  (invoice) => ListTile(
                                    title: Text(
                                      invoice['invoice_number']?.toString() ??
                                          'Invoice',
                                    ),
                                    subtitle: Text(
                                      invoice['customer_name']?.toString() ??
                                          'Customer',
                                    ),
                                    trailing: Text(
                                      _money(_amount(invoice['total_amount'])),
                                    ),
                                  ),
                                )
                                .toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Recent invoices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (active.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No invoice data is available yet.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: active
                            .take(10)
                            .map(
                              (invoice) => ListTile(
                                title: Text(
                                  invoice['invoice_number']?.toString() ??
                                      'Invoice',
                                ),
                                subtitle: Text(
                                  '${invoice['customer_name'] ?? ''} • ${(invoice['status'] ?? 'draft').toString().toUpperCase()}',
                                ),
                                trailing: Text(
                                  _money(_amount(invoice['total_amount'])),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'GSTR-1 summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _reportLine('Taxable value', filingTaxable),
                          _reportLine('CGST', filingCgst),
                          _reportLine('SGST', filingSgst),
                          _reportLine('IGST', filingIgst),
                          const Divider(),
                          _reportLine(
                            'Total GST',
                            filingCgst + filingSgst + filingIgst,
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Customer-wise report',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (customers.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No customer sales yet.'),
                      ),
                    ),
                  ...customers.map(
                    (entry) => Card(
                      child: ListTile(
                        title: Text(entry.key),
                        subtitle: Text(
                          '${entry.value['count']!.toInt()} invoices • Tax ${_money(entry.value['tax']!)} • Due ${_money(entry.value['outstanding']!)}',
                        ),
                        trailing: Text(
                          _money(entry.value['sales']!),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Item-wise report',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No item sales yet.'),
                      ),
                    ),
                  ...items.map(
                    (entry) => Card(
                      child: ListTile(
                        title: Text(entry.key),
                        subtitle: Text(
                          'Qty ${entry.value['quantity']!.toStringAsFixed(2)} • Taxable ${_money(entry.value['taxable']!)} • Tax ${_money(entry.value['tax']!)}',
                        ),
                        trailing: Text(
                          _money(entry.value['sales']!),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(label, style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );
  Widget _statusMetric(String label, int value, Color color) => Column(
    children: [
      Text(
        value.toString(),
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Text(label),
    ],
  );
  Widget _reportLine(String label, double value, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const Spacer(),
            Text(
              _money(value),
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class QuotationsPage extends StatefulWidget {
  const QuotationsPage({super.key});

  @override
  State<QuotationsPage> createState() => _QuotationsPageState();
}

class _QuotationsPageState extends State<QuotationsPage> {
  List<Map<String, dynamic>> _quotations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await Supabase.instance.client
          .from('quotations')
          .update({'status': 'expired'})
          .inFilter('status', ['draft', 'sent'])
          .lt('valid_until', today);
      final rows = await Supabase.instance.client
          .from('quotations')
          .select(
            'id, quotation_number, customer_name, quotation_date, valid_until, status, subtotal, tax_amount, total_amount, cgst_amount, sgst_amount, igst_amount, converted_invoice_id, terms, place_of_supply',
          )
          .order('quotation_date', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() => _quotations = List<Map<String, dynamic>>.from(rows));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newQuotation() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const QuotationBuilderPage()),
    );
    await _load();
  }

  Future<void> _editQuotation(Map<String, dynamic> quotation) async {
    if (quotation['converted_invoice_id'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A converted quotation cannot be edited.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuotationBuilderPage(quotation: quotation),
      ),
    );
    await _load();
  }

  Future<void> _duplicateQuotation(Map<String, dynamic> quotation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            QuotationBuilderPage(quotation: quotation, duplicate: true),
      ),
    );
    await _load();
  }

  Future<void> _openPreview(Map<String, dynamic> quotation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuotationPreviewPage(quotation: quotation),
      ),
    );
  }

  Future<void> _updateStatus(
    Map<String, dynamic> quotation,
    String status,
  ) async {
    try {
      await Supabase.instance.client
          .from('quotations')
          .update({'status': status})
          .eq('id', quotation['id']);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update quotation: $error')),
        );
      }
    }
  }

  Future<void> _convertToInvoice(Map<String, dynamic> quotation) async {
    if (quotation['converted_invoice_id'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This quotation was already converted to an invoice.'),
        ),
      );
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session has expired. Please sign in again.'),
        ),
      );
      return;
    }
    try {
      final items = await Supabase.instance.client
          .from('quotation_items')
          .select(
            'product_id, item_name, quantity, uqc_code, unit_price, taxable_amount, gst_rate, tax_amount, cgst_amount, sgst_amount, igst_amount, total_amount',
          )
          .eq('quotation_id', quotation['id']);
      final invoiceNumber =
          await Supabase.instance.client.rpc(
                'next_invoice_number',
                params: {
                  'p_prefix':
                      BusinessSettings.profile.value['invoicePrefix'] ?? 'INV',
                  'p_invoice_date': DateTime.now().toIso8601String().substring(
                    0,
                    10,
                  ),
                  'p_financial_year':
                      BusinessSettings.profile.value['financialYear'] ?? '',
                },
              )
              as String;
      final total = _asDouble(quotation['total_amount']);
      final invoice = await Supabase.instance.client
          .from('invoices')
          .insert({
            'user_id': user.id,
            'invoice_number': invoiceNumber,
            'customer_name': quotation['customer_name'],
            'invoice_date': DateTime.now().toIso8601String().substring(0, 10),
            'status': 'draft',
            'subtotal': items.fold<double>(
              0,
              (sum, row) => sum + _asDouble(row['taxable_amount']),
            ),
            'tax_amount': items.fold<double>(
              0,
              (sum, row) => sum + _asDouble(row['tax_amount']),
            ),
            'total_amount': total,
            'balance_amount': total,
            'terms': quotation['terms'],
            'place_of_supply': quotation['place_of_supply'],
            'tax_type': _asDouble(quotation['igst_amount']) > 0
                ? 'igst'
                : 'cgst_sgst',
            'cgst_amount': _asDouble(quotation['cgst_amount']),
            'sgst_amount': _asDouble(quotation['sgst_amount']),
            'igst_amount': _asDouble(quotation['igst_amount']),
          })
          .select('*')
          .single();
      await Supabase.instance.client
          .from('invoice_items')
          .insert(
            List<Map<String, dynamic>>.from(items)
                .map(
                  (item) => {
                    'invoice_id': invoice['id'],
                    'product_id': item['product_id'],
                    'product_name': item['item_name'],
                    'item_name': item['item_name'],
                    'quantity': item['quantity'],
                    'uqc_code': item['uqc_code'],
                    'unit_price': item['unit_price'],
                    'taxable_amount': item['taxable_amount'],
                    'gst_rate': item['gst_rate'],
                    'tax_amount': item['tax_amount'],
                    'cgst_amount': item['cgst_amount'],
                    'sgst_amount': item['sgst_amount'],
                    'igst_amount': item['igst_amount'],
                    'total_amount': item['total_amount'],
                  },
                )
                .toList(),
          );
      await Supabase.instance.client
          .from('quotations')
          .update({'status': 'accepted', 'converted_invoice_id': invoice['id']})
          .eq('id', quotation['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quotation accepted and converted to invoice $invoiceNumber',
          ),
        ),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              InvoiceBuilderPage(sourceInvoice: invoice, editExisting: true),
        ),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to convert quotation: $error')),
        );
      }
    }
  }

  double _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quotations')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _newQuotation,
      icon: const Icon(Icons.add),
      label: const Text('New quotation'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'Quotations are not ready yet.\n$_error',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : _quotations.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, size: 56),
                const SizedBox(height: 12),
                const Text('No quotations yet'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _newQuotation,
                  child: const Text('Create quotation'),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: _quotations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final quote = _quotations[index];
                final status = quote['status']?.toString() ?? 'draft';
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        quote['converted_invoice_id'] == null
                            ? Icons.description_outlined
                            : Icons.receipt_long_outlined,
                      ),
                    ),
                    title: Text(
                      quote['quotation_number']?.toString() ?? 'Quotation',
                    ),
                    subtitle: Text(
                      '${quote['customer_name'] ?? ''}\n${status.toUpperCase()} • Valid until ${quote['valid_until'] ?? '-'}',
                    ),
                    isThreeLine: true,
                    onTap: () => _openPreview(quote),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit quotation',
                          onPressed: () => _editQuotation(quote),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editQuotation(quote);
                            } else if (value == 'duplicate') {
                              _duplicateQuotation(quote);
                            } else if (value == 'convert') {
                              _convertToInvoice(quote);
                            } else {
                              _updateStatus(quote, value);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit quotation'),
                            ),
                            const PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate quotation'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'sent',
                              child: Text('Mark as sent'),
                            ),
                            const PopupMenuItem(
                              value: 'accepted',
                              child: Text('Mark as accepted'),
                            ),
                            const PopupMenuItem(
                              value: 'rejected',
                              child: Text('Mark as rejected'),
                            ),
                            const PopupMenuItem(
                              value: 'expired',
                              child: Text('Mark as expired'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'convert',
                              child: Text('Convert to invoice'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

class QuotationBuilderPage extends StatefulWidget {
  const QuotationBuilderPage({
    super.key,
    this.quotation,
    this.duplicate = false,
  });

  final Map<String, dynamic>? quotation;
  final bool duplicate;

  @override
  State<QuotationBuilderPage> createState() => _QuotationBuilderPageState();
}

class _QuotationBuilderPageState extends State<QuotationBuilderPage> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _placeOfSupplyController = TextEditingController(
    text: BusinessSettings.profile.value['placeOfSupply'] ?? '',
  );
  final _termsController = TextEditingController(
    text: BusinessSettings.quotationTerms.value,
  );
  final List<InvoiceLineItem> _items = [InvoiceLineItem()];
  late DateTime _quotationDate;
  late DateTime _validUntil;
  bool _saving = false;
  bool _loadingExisting = false;
  late final Future<List<Map<String, dynamic>>> _customerOptions;
  late final Future<List<Map<String, dynamic>>> _productOptions;

  bool get _isEditing => widget.quotation != null && !widget.duplicate;

  @override
  void initState() {
    super.initState();
    _customerOptions = _loadCustomerOptions();
    _productOptions = _loadProductOptions();
    _quotationDate = DateTime.now();
    _validUntil = DateTime.now().add(const Duration(days: 30));
    if (widget.quotation != null) _loadExistingQuotation();
  }

  Future<List<Map<String, dynamic>>> _loadCustomerOptions() async =>
      List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('customers')
            .select('name, phone, email, gstin, state')
            .order('name')
            .limit(500),
      );

  Future<List<Map<String, dynamic>>> _loadProductOptions() async =>
      List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('products')
            .select(
              'id, name, product_type, sku, selling_price, uqc_code, gst_rate',
            )
            .eq('is_active', true)
            .order('name')
            .limit(500),
      );

  void _selectQuotationCustomer(Map<String, dynamic> selected) {
    setState(() {
      _customerController.text = selected['name']?.toString() ?? '';
      final state = selected['state']?.toString() ?? '';
      if (_indianStatesAndUnionTerritories.contains(state)) {
        _placeOfSupplyController.text = state;
      }
    });
  }

  void _selectQuotationProduct(
    InvoiceLineItem item,
    Map<String, dynamic> selected,
  ) {
    setState(() {
      item.productId = selected['id']?.toString();
      item.uqcCode = selected['uqc_code']?.toString();
      item.productController.text = selected['name']?.toString() ?? '';
      item.rateController.text = selected['selling_price']?.toString() ?? '';
      item.gstRateController.text = selected['gst_rate']?.toString() ?? '0';
    });
  }

  @override
  void dispose() {
    _customerController.dispose();
    _placeOfSupplyController.dispose();
    _termsController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.taxableAmount);
  double get _tax => _items.fold(0, (sum, item) => sum + item.taxAmount);
  double get _total => _subtotal + _tax;
  bool get _isIntraState =>
      _normaliseState(_placeOfSupplyController.text) ==
      _normaliseState(BusinessSettings.profile.value['businessState'] ?? '');
  double get _cgst => _isIntraState ? _tax / 2 : 0;
  double get _sgst => _isIntraState ? _tax / 2 : 0;
  double get _igst => _isIntraState ? 0 : _tax;
  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  String _dbDate(DateTime value) => value.toIso8601String().substring(0, 10);

  Future<void> _loadExistingQuotation() async {
    setState(() => _loadingExisting = true);
    try {
      final quotation = widget.quotation!;
      _customerController.text = quotation['customer_name']?.toString() ?? '';
      _termsController.text = quotation['terms']?.toString() ?? '';
      _placeOfSupplyController.text =
          quotation['place_of_supply']?.toString() ??
          BusinessSettings.profile.value['placeOfSupply'] ??
          '';
      final originalDate =
          DateTime.tryParse(quotation['quotation_date']?.toString() ?? '') ??
          DateTime.now();
      final originalValidUntil =
          DateTime.tryParse(quotation['valid_until']?.toString() ?? '') ??
          originalDate.add(const Duration(days: 30));
      _quotationDate = widget.duplicate ? DateTime.now() : originalDate;
      _validUntil = widget.duplicate
          ? _quotationDate.add(originalValidUntil.difference(originalDate))
          : originalValidUntil;
      final rows = await Supabase.instance.client
          .from('quotation_items')
          .select(
            'product_id, item_name, quantity, uqc_code, unit_price, gst_rate',
          )
          .eq('quotation_id', quotation['id']);
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final item = InvoiceLineItem();
        item.productId = row['product_id']?.toString();
        item.uqcCode = row['uqc_code']?.toString();
        item.productController.text = row['item_name']?.toString() ?? '';
        item.quantityController.text = _asDouble(row['quantity']).toString();
        item.rateController.text = _asDouble(row['unit_price']).toString();
        item.gstRateController.text = _asDouble(row['gst_rate']).toString();
        _items.add(item);
      }
      if (_items.isEmpty) _items.add(InvoiceLineItem());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load quotation: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  double _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _pickDate(bool validUntil) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: validUntil ? _validUntil : _quotationDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (chosen != null && mounted) {
      setState(() {
        if (validUntil) {
          _validUntil = chosen;
        } else {
          _quotationDate = chosen;
        }
      });
    }
  }

  Future<void> _save({required bool openPreview}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'customer_name': _customerController.text.trim(),
        'quotation_date': _dbDate(_quotationDate),
        'valid_until': _dbDate(_validUntil),
        'subtotal': _subtotal,
        'tax_amount': _tax,
        'total_amount': _total,
        'terms': _termsController.text.trim(),
        'place_of_supply': _placeOfSupplyController.text.trim(),
        'tax_type': _tax == 0 ? 'none' : (_isIntraState ? 'cgst_sgst' : 'igst'),
        'cgst_amount': _cgst,
        'sgst_amount': _sgst,
        'igst_amount': _igst,
      };
      late final String number;
      late final Map<String, dynamic> quote;
      if (_isEditing) {
        number =
            widget.quotation!['quotation_number']?.toString() ?? 'Quotation';
        quote = await Supabase.instance.client
            .from('quotations')
            .update(data)
            .eq('id', widget.quotation!['id'])
            .select('*')
            .single();
        await Supabase.instance.client
            .from('quotation_items')
            .delete()
            .eq('quotation_id', quote['id']);
      } else {
        number =
            await Supabase.instance.client.rpc(
                  'next_quotation_number',
                  params: {
                    'p_prefix':
                        BusinessSettings.profile.value['quotationPrefix'] ??
                        'QTN',
                    'p_quotation_date': _dbDate(_quotationDate),
                    'p_financial_year':
                        BusinessSettings.profile.value['financialYear'] ?? '',
                  },
                )
                as String;
        quote = await Supabase.instance.client
            .from('quotations')
            .insert({...data, 'quotation_number': number, 'status': 'draft'})
            .select('*')
            .single();
      }
      await Supabase.instance.client
          .from('quotation_items')
          .insert(
            _items
                .map(
                  (item) => {
                    'quotation_id': quote['id'],
                    'product_id': item.productId,
                    'item_name': item.productController.text.trim(),
                    'quantity': item.quantity,
                    'uqc_code': item.uqcCode,
                    'unit_price': item.rate,
                    'taxable_amount': item.taxableAmount,
                    'gst_rate': item.gstRate,
                    'tax_amount': item.taxAmount,
                    'cgst_amount': _isIntraState ? item.taxAmount / 2 : 0,
                    'sgst_amount': _isIntraState ? item.taxAmount / 2 : 0,
                    'igst_amount': _isIntraState ? 0 : item.taxAmount,
                    'total_amount': item.total,
                  },
                )
                .toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Quotation $number ${_isEditing ? 'updated' : 'saved'} successfully',
          ),
        ),
      );
      if (openPreview) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => QuotationPreviewPage(quotation: quote),
          ),
        );
      } else {
        _returnToDashboard(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save quotation: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Kept as a fallback picker for narrow screens and accessibility tools.
  // ignore: unused_element
  Future<void> _chooseQuotationCustomer() async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('customers')
            .select('name, phone, email, gstin, state')
            .order('name')
            .limit(200),
      );
      if (!mounted) return;
      final selected = await _showSearchableRecordPicker(
        context,
        title: 'Select customer',
        hint: 'Search name, mobile, email, or GSTIN',
        records: rows,
        titleFor: (row) => row['name']?.toString() ?? 'Unnamed customer',
        subtitleFor: (row) => [
          row['phone'],
          row['email'],
          row['gstin'],
        ].whereType<String>().where((value) => value.isNotEmpty).join(' • '),
        searchableTextFor: (row) =>
            '${row['name'] ?? ''} ${row['phone'] ?? ''} ${row['email'] ?? ''} ${row['gstin'] ?? ''}',
      );
      if (selected != null && mounted) {
        setState(() {
          _customerController.text = selected['name']?.toString() ?? '';
          final state = selected['state']?.toString() ?? '';
          if (_indianStatesAndUnionTerritories.contains(state)) {
            _placeOfSupplyController.text = state;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load customers: $error')),
        );
      }
    }
  }

  // ignore: unused_element
  Future<void> _chooseQuotationProduct(InvoiceLineItem item) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('products')
            .select(
              'id, name, product_type, sku, selling_price, uqc_code, gst_rate',
            )
            .eq('is_active', true)
            .order('name')
            .limit(200),
      );
      if (!mounted) return;
      final selected = await _showSearchableRecordPicker(
        context,
        title: 'Select product or service',
        hint: 'Search name, SKU, type, or UQC',
        records: rows,
        titleFor: (row) => row['name']?.toString() ?? 'Unnamed item',
        subtitleFor: (row) => [
          row['product_type']?.toString(),
          row['sku']?.toString(),
          if (row['selling_price'] != null) '₹${row['selling_price']}',
        ].whereType<String>().where((value) => value.isNotEmpty).join(' • '),
        searchableTextFor: (row) =>
            '${row['name'] ?? ''} ${row['sku'] ?? ''} ${row['product_type'] ?? ''} ${row['uqc_code'] ?? ''}',
      );
      if (selected != null && mounted) {
        setState(() {
          item.productId = selected['id']?.toString();
          item.uqcCode = selected['uqc_code']?.toString();
          item.productController.text = selected['name']?.toString() ?? '';
          item.rateController.text =
              selected['selling_price']?.toString() ?? '';
          item.gstRateController.text = selected['gst_rate']?.toString() ?? '0';
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load products: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isEditing ? 'Edit Quotation' : 'New Quotation'),
    ),
    bottomNavigationBar: DesignSettings.modern.value && !_loadingExisting
        ? DocumentSaveBar(
            saving: _saving,
            onClose: () => _save(openPreview: false),
            onNext: () => _save(openPreview: true),
          )
        : null,
    body: _loadingExisting
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (DesignSettings.modern.value)
                  const EditorSection(
                    'Prepare your quotation',
                    'Choose a customer, add items and review your totals.',
                  ),
                _RecordAutocompleteField(
                  controller: _customerController,
                  loadOptions: () => _customerOptions,
                  displayStringForOption: (row) =>
                      row['name']?.toString() ?? 'Unnamed customer',
                  searchTextForOption: (row) =>
                      '${row['name'] ?? ''} • ${row['phone'] ?? ''} • ${row['email'] ?? ''} • ${row['gstin'] ?? ''}',
                  onSelected: _selectQuotationCustomer,
                  onAddRequested: (name) =>
                      _addCustomerFromDocumentBuilder(context, name),
                  addOptionDescription: 'Create a new customer',
                  label: 'Customer name',
                  helperText: 'Type to filter saved customers.',
                  emptyError: 'Customer name is required',
                  leadingIcon: Icons.person_search_outlined,
                ),
                const SizedBox(height: 12),
                SearchableStateField(
                  key: ValueKey(_placeOfSupplyController.text),
                  initialValue:
                      _indianStatesAndUnionTerritories.contains(
                        _placeOfSupplyController.text,
                      )
                      ? _placeOfSupplyController.text
                      : null,
                  isExpanded: true,
                  items: _indianStatesAndUnionTerritories
                      .map(
                        (state) =>
                            DropdownMenuItem(value: state, child: Text(state)),
                      )
                      .toList(),
                  onChanged: (state) => setState(
                    () => _placeOfSupplyController.text = state ?? '',
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Place of supply',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Place of supply is required'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(false),
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text('Quote: ${_date(_quotationDate)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(true),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text('Valid until: ${_date(_validUntil)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      'Items',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: () =>
                          setState(() => _items.add(InvoiceLineItem())),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_items.length, _itemRow),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _items.add(InvoiceLineItem())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add another item'),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _totalLine('Subtotal', _subtotal),
                        const SizedBox(height: 8),
                        if (_isIntraState) ...[
                          _totalLine('CGST', _cgst),
                          _totalLine('SGST', _sgst),
                        ] else
                          _totalLine('IGST', _igst),
                        const Divider(height: 24),
                        _totalLine('Quotation total', _total, emphasis: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DesignSettings.modern.value
                    ? EditableTerms(controller: _termsController)
                    : TextField(
                        controller: _termsController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Terms and conditions',
                          border: OutlineInputBorder(),
                        ),
                      ),
                const SizedBox(height: 24),
                if (!DesignSettings.modern.value)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(openPreview: false),
                          icon: const Icon(Icons.close_outlined),
                          label: const Text('Save & Close'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _save(openPreview: true),
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_outlined),
                          label: Text(_saving ? 'Saving...' : 'Save & Next'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
  );

  Widget _itemRow(int index) {
    final item = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_items.length > 1)
                  IconButton(
                    onPressed: () => setState(() {
                      final removed = _items.removeAt(index);
                      removed.dispose();
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
            _RecordAutocompleteField(
              controller: item.productController,
              loadOptions: () => _productOptions,
              displayStringForOption: (row) =>
                  row['name']?.toString() ?? 'Unnamed item',
              searchTextForOption: (row) =>
                  '${row['name'] ?? ''} • ${row['sku'] ?? ''} • ${row['product_type'] ?? ''} • ₹${row['selling_price'] ?? ''}',
              onSelected: (row) => _selectQuotationProduct(item, row),
              onAddRequested: (name) =>
                  _addProductFromDocumentBuilder(context, name),
              label: 'Product or service',
              helperText: 'Type to filter saved products or services.',
              emptyError: 'Enter an item name',
              leadingIcon: Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _number(item.quantityController, 'Qty')),
                const SizedBox(width: 8),
                Expanded(
                  child: _number(item.rateController, 'Rate', currency: true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: item.gstRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'GST rate (%)',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final rate = double.tryParse(value?.trim() ?? '');
                return rate == null || rate < 0 || rate > 100
                    ? 'Enter 0 to 100'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Row total: ₹${item.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _number(
    TextEditingController controller,
    String label, {
    bool currency = false,
  }) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: label,
      prefixText: currency ? '₹ ' : null,
      border: const OutlineInputBorder(),
    ),
    validator: (value) {
      final number = double.tryParse(value?.trim() ?? '');
      return number == null || number < 0 ? 'Enter valid $label' : null;
    },
  );
  Widget _totalLine(String label, double amount, {bool emphasis = false}) =>
      Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: emphasis ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: emphasis ? 18 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}

class QuotationPreviewPage extends StatefulWidget {
  const QuotationPreviewPage({super.key, required this.quotation});

  final Map<String, dynamic> quotation;

  @override
  State<QuotationPreviewPage> createState() => _QuotationPreviewPageState();
}

class _QuotationPreviewPageState extends State<QuotationPreviewPage> {
  List<Map<String, dynamic>> _items = [];
  String? _error;
  String _customerPhone = '';
  String _customerEmail = '';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from('quotation_items')
            .select('item_name, quantity, unit_price, gst_rate, total_amount')
            .eq('quotation_id', widget.quotation['id']),
        Supabase.instance.client
            .from('customers')
            .select('phone, email')
            .eq('name', widget.quotation['customer_name'])
            .limit(1),
      ]);
      final contacts = List<Map<String, dynamic>>.from(results[1] as List);
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(results[0] as List);
          if (contacts.isNotEmpty) {
            _customerPhone = contacts.first['phone']?.toString() ?? '';
            _customerEmail = contacts.first['email']?.toString() ?? '';
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  String _date(dynamic value) => value?.toString().isEmpty != false
      ? '-'
      : value.toString().split('T').first;

  Future<Uint8List> _pdf(PdfPageFormat format) async {
    final profile = BusinessSettings.profile.value;
    final paymentQr = await buildPaymentQr(profile);
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    profile['name']?.isNotEmpty == true
                        ? profile['name']!
                        : 'Your Business Name',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (profile['address']?.isNotEmpty == true)
                    pw.Text(profile['address']!),
                  if (profile['phone']?.isNotEmpty == true)
                    pw.Text('Phone: ${profile['phone']}'),
                  if (profile['gstin']?.isNotEmpty == true)
                    pw.Text('GSTIN: ${profile['gstin']}'),
                ],
              ),
              pw.Text(
                'QUOTATION',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            color: PdfColors.grey100,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Quote to\n${widget.quotation['customer_name'] ?? ''}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Quotation no.: ${widget.quotation['quotation_number'] ?? ''}\nDate: ${_date(widget.quotation['quotation_date'])}\nValid until: ${_date(widget.quotation['valid_until'])}',
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'Description', 'Qty', 'Rate', 'GST', 'Amount'],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            data: List.generate(_items.length, (index) {
              final item = _items[index];
              return [
                '${index + 1}',
                item['item_name']?.toString() ?? '',
                _amount(item['quantity']).toStringAsFixed(2),
                'Rs. ${_amount(item['unit_price']).toStringAsFixed(2)}',
                '${_amount(item['gst_rate']).toStringAsFixed(0)}%',
                'Rs. ${_amount(item['total_amount']).toStringAsFixed(2)}',
              ];
            }),
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Quotation total: Rs. ${_amount(widget.quotation['total_amount']).toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if ((widget.quotation['terms']?.toString() ?? '')
              .trim()
              .isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              'Terms and conditions',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(widget.quotation['terms'].toString()),
          ],
          if (paymentQr != null) ...[pw.SizedBox(height: 20), paymentQr],
          pw.SizedBox(height: 28),
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'This is a computer-generated quotation.',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> _share() async {
    final number =
        widget.quotation['quotation_number']?.toString() ?? 'quotation';
    await Printing.sharePdf(
      bytes: await _pdf(PdfPageFormat.a4),
      filename: 'quotation_${number.replaceAll('/', '_')}.pdf',
      subject: 'Quotation $number',
    );
  }

  String get _message =>
      'Hello ${widget.quotation['customer_name'] ?? ''}, please find our quotation ${widget.quotation['quotation_number'] ?? ''}.';

  Future<void> _openWhatsApp() async {
    final phone = _customerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A saved WhatsApp number is not available for this customer.',
          ),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://wa.me/$phone?text=${Uri.encodeComponent(_message)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open WhatsApp.')));
    }
  }

  Future<void> _openEmail() async {
    if (_customerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A saved email address is not available for this customer.',
          ),
        ),
      );
      return;
    }
    final uri = Uri(
      scheme: 'mailto',
      path: _customerEmail,
      queryParameters: {
        'subject': 'Quotation ${widget.quotation['quotation_number'] ?? ''}',
        'body': _message,
      },
    );
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open email.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Quotation Preview'),
      actions: [
        TextButton(
          onPressed: () => _returnToDashboard(context),
          child: const Text('Close'),
        ),
      ],
    ),
    body: _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load quotation: $_error',
                textAlign: TextAlign.center,
              ),
            ),
          )
        : _items.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : _SavedDocumentPreview(
            buildPdf: _pdf,
            addNewLabel: 'Save & Add New Quotation',
            onAddNew: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const QuotationBuilderPage(),
              ),
            ),
          ),
    bottomNavigationBar: DesignSettings.modern.value
        ? DocumentShareBar(
            onWhatsApp: _items.isEmpty ? null : _openWhatsApp,
            onEmail: _items.isEmpty ? null : _openEmail,
            onShare: _items.isEmpty ? null : _share,
          )
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _items.isEmpty ? null : _openWhatsApp,
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _items.isEmpty ? null : _openEmail,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _items.isEmpty ? null : _share,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share PDF'),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

class InvoiceHistoryPage extends StatefulWidget {
  const InvoiceHistoryPage({super.key});

  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  List<Map<String, dynamic>> _invoices = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final syncedDrafts = await OfflineStore.flushInvoiceDrafts();
      final rows = await Supabase.instance.client
          .from('invoices')
          .select(
            'id, invoice_number, customer_name, customer_gstin, invoice_date, due_date, status, total_amount, paid_amount, balance_amount, terms, place_of_supply',
          )
          .order('invoice_date', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() => _invoices = List<Map<String, dynamic>>.from(rows));
        if (syncedDrafts > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$syncedDrafts offline invoice(s) synced')),
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Unable to load invoices: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _newInvoice() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const InvoiceBuilderPage()));
    await _loadInvoices();
  }

  Future<void> _duplicateInvoice(Map<String, dynamic> invoice) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceBuilderPage(sourceInvoice: invoice),
      ),
    );
    await _loadInvoices();
  }

  Future<void> _editInvoice(Map<String, dynamic> invoice) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InvoiceBuilderPage(sourceInvoice: invoice, editExisting: true),
      ),
    );
    await _loadInvoices();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invoices')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _newInvoice,
      icon: const Icon(Icons.add),
      label: const Text('New invoice'),
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _loadInvoices,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          )
        : _invoices.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 56),
                const SizedBox(height: 12),
                const Text(
                  'No invoices yet',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _newInvoice,
                  child: const Text('Create invoice'),
                ),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _loadInvoices,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: _invoices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final invoice = _invoices[index];
                final status = invoice['status']?.toString() ?? 'draft';
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(
                        status == 'paid'
                            ? Icons.check
                            : Icons.receipt_long_outlined,
                      ),
                    ),
                    title: Text(
                      invoice['invoice_number']?.toString() ?? 'Invoice',
                    ),
                    subtitle: Text(
                      '${invoice['customer_name'] ?? ''}\n${invoice['invoice_date'] ?? ''} • ${status.toUpperCase()}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Invoice actions',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editInvoice(invoice);
                        } else if (value == 'duplicate') {
                          _duplicateInvoice(invoice);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit invoice'),
                        ),
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Duplicate invoice'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

class InvoiceLineItem {
  InvoiceLineItem()
    : productController = TextEditingController(),
      quantityController = TextEditingController(text: '1'),
      rateController = TextEditingController(),
      gstRateController = TextEditingController(text: '0');

  final TextEditingController productController;
  final TextEditingController quantityController;
  final TextEditingController rateController;
  final TextEditingController gstRateController;
  String? productId;
  String? uqcCode;

  double get quantity => double.tryParse(quantityController.text.trim()) ?? 0;
  double get rate => double.tryParse(rateController.text.trim()) ?? 0;
  double get gstRate => double.tryParse(gstRateController.text.trim()) ?? 0;
  double get taxableAmount => quantity * rate;
  double get taxAmount => taxableAmount * gstRate / 100;
  double get total => taxableAmount + taxAmount;

  void dispose() {
    productController.dispose();
    quantityController.dispose();
    rateController.dispose();
    gstRateController.dispose();
  }
}

class InvoiceBuilderPage extends StatefulWidget {
  const InvoiceBuilderPage({
    super.key,
    this.sourceInvoice,
    this.editExisting = false,
  });

  final Map<String, dynamic>? sourceInvoice;
  final bool editExisting;

  @override
  State<InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends State<InvoiceBuilderPage> {
  int _customerListVersion = 0;
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerGstinController = TextEditingController();
  final _placeOfSupplyController = TextEditingController(
    text: BusinessSettings.profile.value['placeOfSupply'] ?? '',
  );
  final _termsController = TextEditingController(
    text: BusinessSettings.invoiceTerms.value,
  );
  late DateTime _invoiceDate;
  DateTime? _dueDate;
  final List<InvoiceLineItem> _items = [InvoiceLineItem()];
  bool _isSavingDraft = false;
  bool _loadingSource = false;
  late final Future<List<Map<String, dynamic>>> _customerOptions;
  late final Future<List<Map<String, dynamic>>> _productOptions;

  bool get _isEditing => widget.sourceInvoice != null && widget.editExisting;

  @override
  void initState() {
    super.initState();
    _customerOptions = _loadCustomerOptions();
    _productOptions = _loadProductOptions();
    _invoiceDate = DateTime.now();
    _dueDate = _defaultDueDate(
      _invoiceDate,
      BusinessSettings.defaultDueDay.value,
    );
    if (widget.sourceInvoice != null) _loadSourceInvoice();
  }

  Future<List<Map<String, dynamic>>> _loadCustomerOptions() async =>
      List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('customers')
            .select('name, phone, email, gstin, state')
            .order('name')
            .limit(500),
      );

  Future<List<Map<String, dynamic>>> _loadProductOptions() async =>
      List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('products')
            .select(
              'id, name, product_type, sku, selling_price, uqc_code, gst_rate',
            )
            .eq('is_active', true)
            .order('name')
            .limit(500),
      );

  void _selectInvoiceCustomer(Map<String, dynamic> selected) {
    setState(() {
      _customerController.text = selected['name']?.toString() ?? '';
      _customerPhoneController.text = selected['phone']?.toString() ?? '';
      _customerEmailController.text = selected['email']?.toString() ?? '';
      _customerGstinController.text = selected['gstin']?.toString() ?? '';
      final state = selected['state']?.toString() ?? '';
      if (_indianStatesAndUnionTerritories.contains(state)) {
        _placeOfSupplyController.text = state;
      }
    });
  }

  Future<void> _selectInvoiceProduct(
    InvoiceLineItem item,
    Map<String, dynamic> selected,
  ) async {
    final catalogPrice = selected['selling_price'];
    num? lastSellingPrice;
    final productId = selected['id']?.toString();
    if (productId != null) {
      try {
        final history = await Supabase.instance.client
            .from('invoice_items')
            .select('unit_price, invoices!inner(invoice_date)')
            .eq('product_id', productId)
            .order(
              'invoice_date',
              referencedTable: 'invoices',
              ascending: false,
            )
            .limit(1)
            .maybeSingle();
        lastSellingPrice = history?['unit_price'] as num?;
      } catch (_) {
        // Use the catalogue price when invoice history is unavailable.
      }
    }
    if (!mounted) return;
    setState(() {
      item.productId = productId;
      item.uqcCode = selected['uqc_code']?.toString();
      item.productController.text = selected['name']?.toString() ?? '';
      final suggestedPrice = lastSellingPrice ?? catalogPrice;
      if (suggestedPrice != null) {
        item.rateController.text = suggestedPrice.toString();
      }
      if (selected['gst_rate'] != null) {
        item.gstRateController.text = selected['gst_rate'].toString();
      }
    });
  }

  Future<void> _loadSourceInvoice() async {
    setState(() => _loadingSource = true);
    try {
      final source = widget.sourceInvoice!;
      _customerController.text = source['customer_name']?.toString() ?? '';
      final contacts = await Supabase.instance.client
          .from('customers')
          .select('phone, email')
          .eq('name', _customerController.text)
          .limit(2);
      if (!mounted) return;
      if (contacts.length == 1) {
        _customerPhoneController.text =
            contacts.first['phone']?.toString() ?? '';
        _customerEmailController.text =
            contacts.first['email']?.toString() ?? '';
      }
      _customerGstinController.text =
          source['customer_gstin']?.toString() ?? '';
      _placeOfSupplyController.text =
          source['place_of_supply']?.toString() ??
          BusinessSettings.profile.value['placeOfSupply'] ??
          '';
      _termsController.text =
          source['terms']?.toString() ?? BusinessSettings.invoiceTerms.value;
      if (_isEditing) {
        _invoiceDate =
            DateTime.tryParse(source['invoice_date']?.toString() ?? '') ??
            _invoiceDate;
        _dueDate = DateTime.tryParse(source['due_date']?.toString() ?? '');
      }
      final rows = await Supabase.instance.client
          .from('invoice_items')
          .select(
            'product_id, item_name, quantity, uqc_code, unit_price, gst_rate',
          )
          .eq('invoice_id', source['id']);
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final item = InvoiceLineItem();
        item.productId = row['product_id']?.toString();
        item.uqcCode = row['uqc_code']?.toString();
        item.productController.text = row['item_name']?.toString() ?? '';
        item.quantityController.text = row['quantity']?.toString() ?? '1';
        item.rateController.text = row['unit_price']?.toString() ?? '';
        item.gstRateController.text = row['gst_rate']?.toString() ?? '0';
        _items.add(item);
      }
      if (_items.isEmpty) _items.add(InvoiceLineItem());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load invoice: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSource = false);
    }
  }

  DateTime? _defaultDueDate(DateTime invoiceDate, int? dueDay) {
    if (dueDay == null) return null;
    return DateUtils.dateOnly(invoiceDate).add(Duration(days: dueDay));
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _customerGstinController.dispose();
    _placeOfSupplyController.dispose();
    _termsController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.taxableAmount);
  double get _taxTotal => _items.fold(0, (sum, item) => sum + item.taxAmount);
  double get _grandTotal => _subtotal + _taxTotal;
  bool get _isIntraState =>
      _normaliseState(_placeOfSupplyController.text) ==
      _normaliseState(BusinessSettings.profile.value['businessState'] ?? '');
  double get _cgstTotal => _isIntraState ? _taxTotal / 2 : 0;
  double get _sgstTotal => _isIntraState ? _taxTotal / 2 : 0;
  double get _igstTotal => _isIntraState ? 0 : _taxTotal;

  String _dateLabel(DateTime? date) {
    if (date == null) return 'No due date';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _dateForDatabase(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _saveDraft({required bool openPreview}) async {
    if (!_formKey.currentState!.validate()) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session has expired. Please sign in again.'),
        ),
      );
      return;
    }
    setState(() => _isSavingDraft = true);
    var saved = false;
    String savedNumber = 'Pending sync';
    try {
      final invoiceNumber = _isEditing
          ? widget.sourceInvoice!['invoice_number']?.toString() ?? 'Invoice'
          : await Supabase.instance.client.rpc(
                  'next_invoice_number',
                  params: {
                    'p_prefix':
                        BusinessSettings.profile.value['invoicePrefix'] ??
                        'INV',
                    'p_invoice_date': _dateForDatabase(_invoiceDate),
                    'p_financial_year':
                        BusinessSettings.profile.value['financialYear'] ?? '',
                  },
                )
                as String;
      final invoiceData = <String, dynamic>{
        'user_id': user.id,
        'invoice_number': invoiceNumber,
        'customer_name': _customerController.text.trim(),
        'customer_gstin': _customerGstinController.text.trim().toUpperCase(),
        'invoice_date': _dateForDatabase(_invoiceDate),
        'due_date': _dueDate == null ? null : _dateForDatabase(_dueDate!),
        'status': 'draft',
        'subtotal': _subtotal,
        'tax_amount': _taxTotal,
        'total_amount': _grandTotal,
        'balance_amount': _isEditing
            ? (_grandTotal -
                      ((widget.sourceInvoice!['paid_amount'] as num?)
                              ?.toDouble() ??
                          0))
                  .clamp(0, double.infinity)
            : _grandTotal,
        'terms': _termsController.text.trim(),
        'place_of_supply': _placeOfSupplyController.text.trim(),
        'tax_type': _taxTotal == 0
            ? 'none'
            : (_isIntraState ? 'cgst_sgst' : 'igst'),
        'cgst_amount': _cgstTotal,
        'sgst_amount': _sgstTotal,
        'igst_amount': _igstTotal,
      };
      late final Map<String, dynamic> invoice;
      if (_isEditing) {
        invoice = await Supabase.instance.client
            .from('invoices')
            .update(invoiceData)
            .eq('id', widget.sourceInvoice!['id'])
            .select('id')
            .single();
        await Supabase.instance.client
            .from('invoice_items')
            .delete()
            .eq('invoice_id', invoice['id']);
      } else {
        invoice = await Supabase.instance.client
            .from('invoices')
            .insert(invoiceData)
            .select('id')
            .single();
      }
      final invoiceId = invoice['id'];
      await Supabase.instance.client
          .from('invoice_items')
          .insert(
            _items
                .map(
                  (item) => {
                    'invoice_id': invoiceId,
                    'product_id': item.productId,
                    // Older deployments require this legacy field; keep it in sync
                    // with the current item_name field for backward compatibility.
                    'product_name': item.productController.text.trim(),
                    'item_name': item.productController.text.trim(),
                    'quantity': item.quantity,
                    'uqc_code': item.uqcCode,
                    'unit_price': item.rate,
                    'taxable_amount': item.taxableAmount,
                    'gst_rate': item.gstRate,
                    'tax_amount': item.taxAmount,
                    'cgst_amount': _isIntraState ? item.taxAmount / 2 : 0,
                    'sgst_amount': _isIntraState ? item.taxAmount / 2 : 0,
                    'igst_amount': _isIntraState ? 0 : item.taxAmount,
                    'total_amount': item.total,
                  },
                )
                .toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Invoice $invoiceNumber updated successfully'
                : 'Draft $invoiceNumber saved successfully',
          ),
        ),
      );
      saved = true;
      savedNumber = invoiceNumber;
    } catch (e) {
      if (_isOfflineError(e) && !_isEditing) {
        final invoiceId = const Uuid().v4();
        final header = <String, dynamic>{
          'id': invoiceId,
          'user_id': user.id,
          'customer_name': _customerController.text.trim(),
          'customer_gstin': _customerGstinController.text.trim().toUpperCase(),
          'invoice_date': _dateForDatabase(_invoiceDate),
          'due_date': _dueDate == null ? null : _dateForDatabase(_dueDate!),
          'status': 'draft',
          'subtotal': _subtotal,
          'tax_amount': _taxTotal,
          'total_amount': _grandTotal,
          'balance_amount': _grandTotal,
          'terms': _termsController.text.trim(),
          'place_of_supply': _placeOfSupplyController.text.trim(),
          'tax_type': _taxTotal == 0
              ? 'none'
              : (_isIntraState ? 'cgst_sgst' : 'igst'),
          'cgst_amount': _cgstTotal,
          'sgst_amount': _sgstTotal,
          'igst_amount': _igstTotal,
        };
        final items = _items
            .map(
              (item) => <String, dynamic>{
                'id': const Uuid().v4(),
                'invoice_id': invoiceId,
                'product_id': item.productId,
                'product_name': item.productController.text.trim(),
                'item_name': item.productController.text.trim(),
                'quantity': item.quantity,
                'uqc_code': item.uqcCode,
                'unit_price': item.rate,
                'taxable_amount': item.taxableAmount,
                'gst_rate': item.gstRate,
                'tax_amount': item.taxAmount,
                'cgst_amount': _isIntraState ? item.taxAmount / 2 : 0,
                'sgst_amount': _isIntraState ? item.taxAmount / 2 : 0,
                'igst_amount': _isIntraState ? 0 : item.taxAmount,
                'total_amount': item.total,
              },
            )
            .toList();
        await OfflineStore.enqueue('invoice_drafts', {
          'header': header,
          'items': items,
          'number_params': {
            'p_prefix':
                BusinessSettings.profile.value['invoicePrefix'] ?? 'INV',
            'p_invoice_date': _dateForDatabase(_invoiceDate),
            'p_financial_year':
                BusinessSettings.profile.value['financialYear'] ?? '',
          },
        });
        saved = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Invoice draft saved offline and will sync automatically',
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to save draft: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
    if (!saved || !mounted) return;
    if (openPreview) {
      final addNew = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => InvoicePreviewPage(
            invoiceNumber: savedNumber,
            balanceDue:
                (_grandTotal -
                        ((_isEditing
                                ? widget.sourceInvoice!['paid_amount'] as num?
                                : null) ??
                            0))
                    .clamp(0, double.infinity)
                    .toDouble(),
            customerName: _customerController.text.trim(),
            customerPhone: _customerPhoneController.text.trim(),
            customerEmail: _customerEmailController.text.trim(),
            placeOfSupply: _placeOfSupplyController.text.trim(),
            invoiceDate: _invoiceDate,
            dueDate: _dueDate,
            terms: _termsController.text.trim(),
            items: _items,
          ),
        ),
      );
      if (!mounted) return;
      if (addNew == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const InvoiceBuilderPage()),
        );
        return;
      }
    }
    _returnToDashboard(context);
  }

  Future<void> _pickDate({required bool isDueDate}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: isDueDate ? (_dueDate ?? _invoiceDate) : _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (isDueDate) {
        _dueDate = selected;
      } else {
        _invoiceDate = selected;
      }
    });
  }

  Future<void> _addCustomer() async {
    final saved = await _showCustomerForm(context);
    if (saved != null && mounted) {
      _selectInvoiceCustomer(saved);
      try {
        final options = await _customerOptions;
        options.add(saved);
      } catch (_) {
        // Selection still works if the initial customer list failed to load.
      }
      if (mounted) setState(() => _customerListVersion++);
    }
  }

  // Legacy dialog picker retained as a fallback.
  // ignore: unused_element
  Future<void> _chooseCustomer() async {
    try {
      final rows = await Supabase.instance.client
          .from('customers')
          .select('name, phone, email, gstin, state')
          .order('name')
          .limit(100);
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Select customer'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, index) {
                final customer = Map<String, dynamic>.from(rows[index]);
                final phone = customer['phone']?.toString() ?? '';
                final email = customer['email']?.toString() ?? '';
                final contact = [
                  phone,
                  email,
                ].where((value) => value.isNotEmpty).join(' • ');
                return ListTile(
                  title: Text(
                    customer['name']?.toString() ?? 'Unnamed customer',
                  ),
                  subtitle: contact.isEmpty ? null : Text(contact),
                  onTap: () => Navigator.of(dialogContext).pop(customer),
                );
              },
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      setState(() {
        _customerController.text = selected['name']?.toString() ?? '';
        _customerPhoneController.text = selected['phone']?.toString() ?? '';
        _customerEmailController.text = selected['email']?.toString() ?? '';
        _customerGstinController.text = selected['gstin']?.toString() ?? '';
        final state = selected['state']?.toString() ?? '';
        if (_indianStatesAndUnionTerritories.contains(state)) {
          _placeOfSupplyController.text = state;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to load customers: $e')));
      }
    }
  }

  // ignore: unused_element
  Future<void> _chooseProduct(InvoiceLineItem item) async {
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id, name, product_type, selling_price, uqc_code, gst_rate')
          .eq('is_active', true)
          .order('name')
          .limit(100);
      if (!mounted) return;
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Select product or service'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, index) {
                final product = Map<String, dynamic>.from(rows[index]);
                final type = product['product_type']?.toString() ?? '';
                final price = product['selling_price'] == null
                    ? ''
                    : '₹${product['selling_price']}';
                final details = [
                  type,
                  price,
                ].where((value) => value.isNotEmpty).join(' • ');
                return ListTile(
                  title: Text(product['name']?.toString() ?? 'Unnamed item'),
                  subtitle: details.isEmpty ? null : Text(details),
                  onTap: () => Navigator.of(dialogContext).pop(product),
                );
              },
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final catalogPrice = selected['selling_price'];
      num? lastSellingPrice;
      final productId = selected['id']?.toString();
      if (productId != null) {
        try {
          final history = await Supabase.instance.client
              .from('invoice_items')
              .select('unit_price, invoices!inner(invoice_date)')
              .eq('product_id', productId)
              .order(
                'invoice_date',
                referencedTable: 'invoices',
                ascending: false,
              )
              .limit(1)
              .maybeSingle();
          lastSellingPrice = history?['unit_price'] as num?;
        } catch (_) {
          // Older databases or restricted invoice history still use the
          // catalog price, so product selection never becomes unavailable.
        }
      }
      setState(() {
        item.productId = productId;
        item.uqcCode = selected['uqc_code']?.toString();
        item.productController.text = selected['name']?.toString() ?? '';
        final suggestedPrice = lastSellingPrice ?? catalogPrice;
        if (suggestedPrice != null) {
          item.rateController.text = suggestedPrice.toString();
        }
        if (selected['gst_rate'] != null) {
          item.gstRateController.text = selected['gst_rate'].toString();
        }
      });
      if (lastSellingPrice != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Last invoiced price ₹$lastSellingPrice applied. You can edit it.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to load products: $e')));
      }
    }
  }

  void _addItem() => setState(() => _items.add(InvoiceLineItem()));

  void _removeItem(int index) {
    if (_items.length == 1) return;
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? 'Edit Invoice'
              : widget.sourceInvoice == null
              ? 'New Invoice'
              : 'Duplicate Invoice',
        ),
      ),
      bottomNavigationBar: DesignSettings.modern.value && !_loadingSource
          ? DocumentSaveBar(
              saving: _isSavingDraft,
              onClose: () => _saveDraft(openPreview: false),
              onNext: () => _saveDraft(openPreview: true),
            )
          : null,
      body: _loadingSource
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (DesignSettings.modern.value)
                    const EditorSection(
                      'Create your invoice',
                      'Add a customer and items. Review before saving.',
                    ),
                  _RecordAutocompleteField(
                    key: ValueKey(_customerListVersion),
                    controller: _customerController,
                    loadOptions: () => _customerOptions,
                    displayStringForOption: (row) =>
                        row['name']?.toString() ?? 'Unnamed customer',
                    searchTextForOption: (row) =>
                        '${row['name'] ?? ''} • ${row['phone'] ?? ''} • ${row['email'] ?? ''} • ${row['gstin'] ?? ''}',
                    onSelected: _selectInvoiceCustomer,
                    onAddRequested: (name) =>
                        _addCustomerFromDocumentBuilder(context, name),
                    addOptionDescription: 'Create a new customer',
                    label: 'Customer name',
                    helperText: 'Type to filter saved customers.',
                    emptyError: 'Customer name is required',
                    leadingIcon: Icons.person_search_outlined,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _addCustomer,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Add new customer'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customerGstinController,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (_, value) =>
                            value.copyWith(text: value.text.toUpperCase()),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Customer GSTIN (optional)',
                      helperText:
                          'Required for classification as a B2B supply.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final gstin = value?.trim().toUpperCase() ?? '';
                      return gstin.isEmpty ||
                              RegExp(
                                r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                              ).hasMatch(gstin)
                          ? null
                          : 'Enter a valid GSTIN';
                    },
                  ),
                  const SizedBox(height: 12),
                  SearchableStateField(
                    key: ValueKey(_placeOfSupplyController.text),
                    initialValue:
                        _indianStatesAndUnionTerritories.contains(
                          _placeOfSupplyController.text,
                        )
                        ? _placeOfSupplyController.text
                        : null,
                    isExpanded: true,
                    items: _indianStatesAndUnionTerritories
                        .map(
                          (state) => DropdownMenuItem(
                            value: state,
                            child: Text(state),
                          ),
                        )
                        .toList(),
                    onChanged: (state) => setState(
                      () => _placeOfSupplyController.text = state ?? '',
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Place of supply',
                      helperText:
                          'Compared with your business state to select CGST/SGST or IGST.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Place of supply is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _customerPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Customer WhatsApp number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _customerEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Customer email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isDueDate: false),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('Invoice: ${_dateLabel(_invoiceDate)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isDueDate: true),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text('Due: ${_dateLabel(_dueDate)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Text(
                        'Items',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        onPressed: _addItem,
                        tooltip: 'Add item row',
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_items.length, _buildItemRow),
                  OutlinedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add another item'),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _totalLine('Subtotal', _subtotal),
                          const SizedBox(height: 8),
                          if (_isIntraState) ...[
                            _totalLine('CGST', _cgstTotal),
                            _totalLine('SGST', _sgstTotal),
                          ] else
                            _totalLine('IGST', _igstTotal),
                          const Divider(height: 24),
                          _totalLine(
                            'Invoice total',
                            _grandTotal,
                            emphasis: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DesignSettings.modern.value
                      ? EditableTerms(controller: _termsController)
                      : TextField(
                          controller: _termsController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'Terms and conditions',
                            helperText:
                                'Prefilled from Business Settings. Editable for this invoice.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                  const SizedBox(height: 24),
                  if (!DesignSettings.modern.value)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSavingDraft
                                ? null
                                : () => _saveDraft(openPreview: false),
                            icon: const Icon(Icons.close_outlined),
                            label: const Text('Save & Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSavingDraft
                                ? null
                                : () => _saveDraft(openPreview: true),
                            icon: _isSavingDraft
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward_outlined),
                            label: Text(
                              _isSavingDraft ? 'Saving...' : 'Save & Next',
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_items.length > 1)
                  IconButton(
                    onPressed: () => _removeItem(index),
                    tooltip: 'Remove row',
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
            _RecordAutocompleteField(
              controller: item.productController,
              loadOptions: () => _productOptions,
              displayStringForOption: (row) =>
                  row['name']?.toString() ?? 'Unnamed item',
              searchTextForOption: (row) =>
                  '${row['name'] ?? ''} • ${row['sku'] ?? ''} • ${row['product_type'] ?? ''} • ₹${row['selling_price'] ?? ''}',
              onSelected: (row) => _selectInvoiceProduct(item, row),
              onAddRequested: (name) =>
                  _addProductFromDocumentBuilder(context, name),
              label: 'Product or service',
              helperText: 'Type to filter saved products or services.',
              emptyError: 'Enter an item name',
              leadingIcon: Icons.inventory_2_outlined,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numberField(item.quantityController, 'Qty')),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    item.rateController,
                    'Rate',
                    currency: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: item.gstRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'GST rate (%)',
                helperText: 'Enter the rate manually.',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final rate = double.tryParse(value?.trim() ?? '');
                return rate == null || rate < 0 || rate > 100
                    ? 'Enter a rate from 0 to 100'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Row total: ₹${item.total.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool currency = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        prefixText: currency ? '₹ ' : null,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final number = double.tryParse(value?.trim() ?? '');
        return number == null || number < 0 ? 'Enter valid $label' : null;
      },
    );
  }

  Widget _totalLine(String label, double amount, {bool emphasis = false}) =>
      Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: emphasis ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: emphasis ? 18 : 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}

class _SavedDocumentPreview extends StatelessWidget {
  const _SavedDocumentPreview({
    required this.buildPdf,
    required this.addNewLabel,
    required this.onAddNew,
  });
  final Future<Uint8List> Function(PdfPageFormat) buildPdf;
  final String addNewLabel;
  final VoidCallback onAddNew;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: PdfPreview(
          build: buildPdf,
          useActions: false,
          canDebug: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onAddNew,
            icon: const Icon(Icons.add),
            label: Text(addNewLabel),
          ),
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: TextButton.icon(
          onPressed: () async {
            try {
              await Printing.layoutPdf(onLayout: buildPdf);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Unable to print: $error')),
                );
              }
            }
          },
          icon: const Icon(Icons.print),
          label: const Text('Print'),
        ),
      ),
    ],
  );
}

class InvoicePreviewPage extends StatefulWidget {
  const InvoicePreviewPage({
    super.key,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.placeOfSupply,
    required this.invoiceDate,
    required this.dueDate,
    required this.terms,
    required this.items,
    required this.invoiceNumber,
    required this.balanceDue,
    this.previewProfile,
  });

  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String placeOfSupply;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String terms;
  final List<InvoiceLineItem> items;
  final String invoiceNumber;
  final double balanceDue;
  final Map<String, String>? previewProfile;

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class InvoicePdfRenderer {
  InvoicePdfRenderer(this.widget);
  final InvoicePreviewPage widget;
  Map<String, String> get _profile => widget.previewProfile ?? BusinessSettings.profile.value;
  double get _subtotal =>
      widget.items.fold(0, (sum, item) => sum + item.taxableAmount);
  double get _taxTotal =>
      widget.items.fold(0, (sum, item) => sum + item.taxAmount);
  double get _total => _subtotal + _taxTotal;
  bool get _isIntraState =>
      _normaliseState(widget.placeOfSupply) ==
      _normaliseState(_profile['businessState'] ?? '');
  double get _cgstTotal => _isIntraState ? _taxTotal / 2 : 0;
  double get _sgstTotal => _isIntraState ? _taxTotal / 2 : 0;
  double get _igstTotal => _isIntraState ? 0 : _taxTotal;

  String get _invoiceNumber => widget.invoiceNumber;
  String _date(DateTime? value) => value == null
      ? '-'
      : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  Future<pw.MemoryImage?> _image(String? path) async {
    if (path == null || path.isEmpty || !await File(path).exists()) return null;
    return pw.MemoryImage(await File(path).readAsBytes());
  }

  Future<Uint8List> build(PdfPageFormat format) async {
    final profile = _profile;
    final palette = InvoicePalette.resolve(profile['invoiceTheme']);
    final logo = await _image(profile['logoPath']);
    final signature = await _image(profile['signaturePath']);
    final qr = await buildPaymentQr(profile);
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: format, margin: const pw.EdgeInsets.all(28),
          theme: pw.ThemeData.withFont().copyWith(
            defaultTextStyle: pw.TextStyle(color: palette.pdfInk, fontSize: 10),
          ),
          buildBackground: (_) => pw.FullPage(ignoreMargins: true,
            child: pw.Container(color: palette.pdfPaper)),
        ),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.Container(
                  width: 58,
                  height: 58,
                  margin: const pw.EdgeInsets.only(right: 14),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      profile['name']?.isNotEmpty == true
                          ? profile['name']!
                          : 'Your Business Name',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (profile['address']?.isNotEmpty == true)
                      pw.Text(profile['address']!),
                    if (profile['phone']?.isNotEmpty == true)
                      pw.Text('Phone: ${profile['phone']}'),
                    if (profile['email']?.isNotEmpty == true)
                      pw.Text('Email: ${profile['email']}'),
                    if (profile['gstin']?.isNotEmpty == true)
                      pw.Text(
                        'GSTIN: ${profile['gstin']}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                  ],
                ),
              ),
              pw.Text(
                widget.previewProfile != null ? 'SAMPLE INVOICE' :
                    (BusinessSettings.isGstRegistered.value ? 'TAX INVOICE' : 'INVOICE'),
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            color: palette.pdfPaper,
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Bill to\n${widget.customerName}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    'Invoice no.: $_invoiceNumber\nInvoice date: ${_date(widget.invoiceDate)}\nDue date: ${_date(widget.dueDate)}\nPlace of supply: ${widget.placeOfSupply}',
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: palette.pdfPaper,
            ),
            headerDecoration: pw.BoxDecoration(color: palette.pdfInk),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const ['#', 'Description', 'Qty', 'Rate', 'GST', 'Amount'],
            data: List.generate(widget.items.length, (index) {
              final item = widget.items[index];
              return [
                '${index + 1}',
                item.productController.text.trim(),
                item.quantity.toStringAsFixed(2),
                'Rs. ${item.rate.toStringAsFixed(2)}',
                '${item.gstRate.toStringAsFixed(0)}%',
                'Rs. ${item.total.toStringAsFixed(2)}',
              ];
            }),
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 220,
              child: pw.Column(
                children: [
                  _pdfTotal('Subtotal', _subtotal),
                  if (_isIntraState) ...[
                    _pdfTotal('CGST', _cgstTotal),
                    _pdfTotal('SGST', _sgstTotal),
                  ] else
                    _pdfTotal('IGST', _igstTotal),
                  pw.Divider(),
                  _pdfTotal('Total payable', _total, bold: true),
                ],
              ),
            ),
          ),
          if ((profile['bankName'] ?? '').isNotEmpty ||
              (profile['bankAccount'] ?? '').isNotEmpty ||
              (profile['ifsc'] ?? '').isNotEmpty ||
              (profile['upiId'] ?? '').isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Bank details',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Bank: ${profile['bankName'] ?? '-'}\nBranch: ${profile['bankBranch'] ?? '-'}\nA/c No.: ${profile['bankAccount'] ?? '-'}\nIFSC: ${profile['ifsc'] ?? '-'}\nUPI ID: ${profile['upiId'] ?? '-'}',
            ),
          ],
          if (widget.terms.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Terms and conditions',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(widget.terms),
          ],
          pw.SizedBox(height: 26),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              qr ?? pw.SizedBox(),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (signature != null)
                    pw.Container(
                      width: 110,
                      height: 45,
                      child: pw.Image(signature, fit: pw.BoxFit.contain),
                    ),
                  pw.SizedBox(height: 4),
                  pw.Text('Authorised signatory'),
                ],
              ),
            ],
          ),
        ],
        footer: (_) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'This is a computer-generated invoice.',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfTotal(String label, double value, {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ),
            pw.Text(
              'Rs. ${value.toStringAsFixed(2)}',
              style: pw.TextStyle(
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ],
        ),
      );

}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  String get _invoiceNumber => widget.invoiceNumber;
  String get _message =>
      'Hello ${widget.customerName}, here is the invoice ($_invoiceNumber) from '
      '${BusinessSettings.profile.value['name'] ?? ''}. Please make the payment of '
      'rupees ${widget.balanceDue.toStringAsFixed(2)} to the payment details as mentioned '
      'in the invoice. If you need any further assistance, please contact us '
      '${BusinessSettings.profile.value['phone'] ?? ''} or '
      '${BusinessSettings.profile.value['email'] ?? ''}. Thank you';

  String get _emailMessage =>
      'Hello ${widget.customerName}. Please find attached invoice, $_invoiceNumber '
      'for your reference. Kindly make the payment to the bank details mentioned '
      'in the invoice. If you have any queries, please feel free to contact us.';

  Future<void> _sendAttachment(String target, String recipient) async {
    try {
      final bytes = await _generatePdf(PdfPageFormat.a4);
      if (Platform.isAndroid) {
        await const MethodChannel(
          'simplek/document_share',
        ).invokeMethod('share', {
          'bytes': bytes,
          'filename':
              'invoice_${_invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}.pdf',
          'target': target,
          'recipient': recipient,
          'subject': 'Invoice $_invoiceNumber',
          'body': target == 'email' ? _emailMessage : _message,
        });
      } else {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'invoice.pdf',
          subject: 'Invoice $_invoiceNumber',
          body: target == 'email' ? _emailMessage : _message,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to attach invoice: $error')),
        );
      }
    }
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) => InvoicePdfRenderer(widget).build(format);

  Future<void> _sharePdf() async {
    final bytes = await _generatePdf(PdfPageFormat.a4);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'invoice_$_invoiceNumber.pdf',
      subject: 'Invoice $_invoiceNumber',
      body: _message,
    );
  }

  Future<void> _openWhatsApp() async {
    final phone = whatsappNumber(widget.customerPhone);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid customer WhatsApp number, including country code for international numbers.'),
        ),
      );
      return;
    }
    final action = await showModalBottomSheet<String>(context: context,
      builder: (context) => SafeArea(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('WhatsApp: ${widget.customerName}', style: Theme.of(context).textTheme.titleLarge),
            Text('+$phone'), const SizedBox(height: 12),
            const Text('Open the client chat with the message filled in, or share the PDF and select the client. WhatsApp may omit the caption when sharing a document; use Copy message if needed.'),
            const SizedBox(height: 12), SelectableText(_message),
            ListTile(leading: const Icon(Icons.chat_outlined), title: const Text('Open client chat with message'),
              onTap: () => Navigator.pop(context, 'chat')),
            ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Share PDF to WhatsApp'),
              onTap: () => Navigator.pop(context, 'pdf')),
            ListTile(leading: const Icon(Icons.copy_outlined), title: const Text('Copy message'),
              onTap: () => Navigator.pop(context, 'copy')),
          ]),
      ))));
    if (!mounted || action == null) return;
    try {
      if (action == 'pdf') {
        await Clipboard.setData(ClipboardData(text: _message));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied. Select the client in WhatsApp and paste it if the caption is empty.')));
        await _sendAttachment('whatsapp', phone);
      } else if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: _message));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message copied')));
      } else {
        final uri = whatsappChatUri(phone, _message);
        if (Platform.isAndroid) {
          await const MethodChannel('simplek/document_share').invokeMethod('openChat', {'url': uri.toString()});
        } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('WhatsApp could not be opened.');
        }
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to open WhatsApp: $error')));
    }
  }

  Future<void> _openEmail() async {
    if (widget.customerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add the customer email first.')),
      );
      return;
    }
    await _sendAttachment('email', widget.customerEmail.trim());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.previewProfile != null ? 'Sample invoice format' : 'Invoice Preview'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ],
    ),
    body: widget.previewProfile != null
        ? PdfPreview(build: _generatePdf, canChangePageFormat: false,
            canChangeOrientation: false, allowPrinting: false, allowSharing: false)
        : _SavedDocumentPreview(
      buildPdf: _generatePdf,
      addNewLabel: 'Save & Add New Invoice',
      onAddNew: () => Navigator.of(context).pop(true),
    ),
    bottomNavigationBar: widget.previewProfile != null ? null : DesignSettings.modern.value
        ? DocumentShareBar(
            onWhatsApp: _openWhatsApp,
            onEmail: _openEmail,
            onShare: _sharePdf,
          )
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openWhatsApp,
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openEmail,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Email'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharePdf,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share PDF'),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _showingCached = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applySearch);
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await OfflineStore.flush('products', 'products');
      final rows = await Supabase.instance.client
          .from('products')
          .select(
            'id, name, product_type, sku, selling_price, uqc_code, hsn_sac_id, hsn_sac_code, hsn_sac_description, gst_rate, is_active',
          )
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      final products = List<Map<String, dynamic>>.from(rows);
      await OfflineStore.writeList('products', products);
      setState(() {
        _products = products;
        _showingCached = false;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = await OfflineStore.readList('products');
      setState(() {
        _products = cached;
        _showingCached = cached.isNotEmpty;
        _errorMessage = cached.isEmpty ? 'Unable to load products: $e' : null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applySearch() => setState(() {});

  Future<void> _addProduct() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AddProductPage()),
    );
    if (saved == true) await _loadProducts();
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => AddProductPage(product: product)),
    );
    if (saved == true) await _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visibleProducts = _products.where((product) {
      final searchable =
          '${product['name'] ?? ''} ${product['product_type'] ?? ''} '
                  '${product['uqc_code'] ?? ''} ${product['hsn_sac_code'] ?? ''}'
              .toLowerCase();
      return searchable.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showingCached
              ? 'Products & Services • Offline'
              : 'Products & Services',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search products and services',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _buildBody(visibleProducts)),
        ],
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> visibleProducts) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadProducts,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (visibleProducts.isEmpty) {
      final hasSearch = _searchController.text.trim().isNotEmpty;
      return RefreshIndicator(
        onRefresh: _loadProducts,
        child: ListView(
          children: [
            const SizedBox(height: 110),
            Icon(
              Icons.inventory_2_outlined,
              size: 54,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              hasSearch ? 'No matching items' : 'No products or services yet',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch
                  ? 'Try a different search term.'
                  : 'Add an item to use it in invoices.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        itemCount: visibleProducts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final product = visibleProducts[index];
          final type = product['product_type'] == 'service'
              ? 'Service'
              : 'Product';
          final price = product['selling_price'];
          final details = [
            type,
            if (product['uqc_code'] != null) product['uqc_code'].toString(),
            if (product['hsn_sac_code'] != null)
              'HSN/SAC ${product['hsn_sac_code']}',
            if (product['gst_rate'] != null) 'GST ${product['gst_rate']}%',
          ].join('  •  ');
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  product['product_type'] == 'service'
                      ? Icons.design_services_outlined
                      : Icons.inventory_2_outlined,
                ),
              ),
              title: Text(product['name']?.toString() ?? 'Unnamed item'),
              subtitle: Text(details),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (price != null)
                    Text(
                      '₹$price',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  IconButton(
                    tooltip: 'Edit item',
                    onPressed: () => _editProduct(product),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _gstRateController = TextEditingController();
  final _hsnSearchController = TextEditingController();
  String _itemType = 'product';
  String? _uqcCode;
  Map<String, dynamic>? _selectedHsnSac;
  List<Map<String, dynamic>> _hsnSacResults = [];
  bool _isSearchingHsnSac = false;
  bool _hsnSacMasterUnavailable = false;
  bool _isSaving = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product == null) {
      _nameController.text = widget.initialName?.trim() ?? '';
      return;
    }
    _nameController.text = product['name']?.toString() ?? '';
    _skuController.text = product['sku']?.toString() ?? '';
    _sellingPriceController.text = product['selling_price']?.toString() ?? '';
    _gstRateController.text = product['gst_rate']?.toString() ?? '';
    _itemType = product['product_type']?.toString() ?? 'product';
    _uqcCode = product['uqc_code']?.toString();
    final hsnSacId = product['hsn_sac_id'];
    if (hsnSacId != null) {
      _selectedHsnSac = {
        'id': hsnSacId,
        'code': product['hsn_sac_code'],
        'description': product['hsn_sac_description'] ?? '',
        'code_type': _itemType == 'product' ? 'HSN' : 'SAC',
      };
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _sellingPriceController.dispose();
    _gstRateController.dispose();
    _hsnSearchController.dispose();
    super.dispose();
  }

  bool get _isProduct => _itemType == 'product';

  double? _amountValue(String value) {
    final text = value.trim().replaceAll(',', '');
    return text.isEmpty ? null : double.tryParse(text);
  }

  String? _amountValidator(String? value, {required String label}) {
    if (value == null || value.trim().isEmpty) return null;
    final amount = _amountValue(value);
    if (amount == null || amount < 0) return 'Enter a valid $label';
    return null;
  }

  String? _taxRateValidator(String? value, {required bool required}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Enter the GST rate' : null;
    }
    final rate = _amountValue(value);
    if (rate == null || rate < 0 || rate > 100) {
      return 'Enter a rate from 0 to 100';
    }
    return null;
  }

  Future<void> _searchHsnSac(String value) async {
    final query = value.trim();
    if (query.length < 3) {
      setState(() => _hsnSacResults = []);
      return;
    }

    final safeQuery = query.replaceAll(RegExp(r'[,()]'), ' ');
    setState(() => _isSearchingHsnSac = true);
    try {
      final type = _isProduct ? 'HSN' : 'SAC';
      final rows = await Supabase.instance.client
          .from('hsn_sac_master')
          .select('id, code, code_type, description')
          .eq('is_active', true)
          .eq('code_type', type)
          .or(
            'code.ilike.%$safeQuery%,description.ilike.%$safeQuery%,search_keywords.ilike.%$safeQuery%',
          )
          .limit(20);
      if (!mounted || _hsnSearchController.text.trim() != query) return;
      setState(() {
        _hsnSacMasterUnavailable = false;
        _hsnSacResults = List<Map<String, dynamic>>.from(rows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hsnSacResults = [];
        _hsnSacMasterUnavailable = e.toString().contains('PGRST205');
      });
      if (!_hsnSacMasterUnavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to search HSN/SAC master: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingHsnSac = false);
    }
  }

  void _selectHsnSac(Map<String, dynamic> entry) {
    setState(() {
      _selectedHsnSac = entry;
      _hsnSacResults = [];
      _hsnSearchController.clear();
    });
  }

  Future<void> _saveProduct(bool isGstRegistered) async {
    if (!_formKey.currentState!.validate()) return;
    if (isGstRegistered && _selectedHsnSac == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select a valid ${_isProduct ? 'HSN' : 'SAC'} code from the master',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw const AuthException(
          'Your session has expired. Please sign in again.',
        );
      }
      final gstRate = isGstRegistered
          ? _amountValue(_gstRateController.text)!
          : null;
      final product = <String, dynamic>{
        if (!_isEditing) 'id': const Uuid().v4(),
        'user_id': user.id,
        'name': _nameController.text.trim(),
        'product_type': _itemType,
        if (_skuController.text.trim().isNotEmpty)
          'sku': _skuController.text.trim(),
        if (_sellingPriceController.text.trim().isNotEmpty)
          'selling_price': _amountValue(_sellingPriceController.text)!,
        if (_isProduct) 'uqc_code': _uqcCode,
        if (isGstRegistered) ...{
          'hsn_sac_id': _selectedHsnSac!['id'],
          'hsn_sac_code': _selectedHsnSac!['code'],
          'hsn_sac_description': _selectedHsnSac!['description'],
          // Rates are entered by the business, not inferred from the master.
          'gst_rate': gstRate,
          'cgst_rate': gstRate! / 2,
          'sgst_rate': gstRate / 2,
          'igst_rate': gstRate,
          'cess_rate': 0,
        } else ...{
          'hsn_sac_id': null,
          'hsn_sac_code': null,
          'hsn_sac_description': null,
          'gst_rate': null,
          'cgst_rate': null,
          'sgst_rate': null,
          'igst_rate': null,
          'cess_rate': null,
        },
      };
      var queuedOffline = false;
      try {
        if (_isEditing) {
          await Supabase.instance.client
              .from('products')
              .update(product)
              .eq('id', widget.product!['id']);
        } else {
          await Supabase.instance.client.from('products').insert(product);
        }
      } catch (error) {
        if (error is PostgrestException || error is AuthException) rethrow;
        if (_isEditing) rethrow;
        await OfflineStore.enqueue('products', product);
        await OfflineStore.addCached('products', {
          ...product,
          'is_active': true,
        });
        queuedOffline = true;
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        widget.returnRecord
            ? <String, dynamic>{...?widget.product, ...product}
            : true,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queuedOffline
                ? '${_isProduct ? 'Product' : 'Service'} saved offline and will sync automatically'
                : '${_isProduct ? 'Product' : 'Service'} saved successfully',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save product: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BusinessSettings.isGstRegistered,
      builder: (context, isGstRegistered, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _isEditing ? 'Edit Product / Service' : 'Add Product / Service',
            ),
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (DesignSettings.modern.value)
                  const EditorSection(
                    'Item details',
                    'Set up an item once and reuse it in your documents.',
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _itemType,
                  decoration: const InputDecoration(
                    labelText: 'Item Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'product', child: Text('Product')),
                    DropdownMenuItem(value: 'service', child: Text('Service')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _itemType = value;
                            _uqcCode = null;
                            _selectedHsnSac = null;
                            _hsnSacResults = [];
                            _hsnSearchController.clear();
                          });
                        },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  decoration: InputDecoration(
                    labelText: _isProduct ? 'Product Name' : 'Service Name',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '${_isProduct ? 'Product' : 'Service'} name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _skuController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'SKU / item code (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _sellingPriceController,
                  enabled: !_isSaving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Selling price',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _amountValidator(value, label: 'selling price'),
                ),
                if (_isProduct) ...[
                  const SizedBox(height: 16),
                  _UqcSelector(
                    value: _uqcCode,
                    enabled: !_isSaving,
                    onChanged: (value) => setState(() => _uqcCode = value),
                  ),
                ],
                if (isGstRegistered) ...[
                  const SizedBox(height: 24),
                  Text(
                    'GST classification',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hsnSearchController,
                    enabled: !_isSaving,
                    onChanged: _searchHsnSac,
                    decoration: InputDecoration(
                      labelText: 'Search ${_isProduct ? 'HSN' : 'SAC'} master',
                      helperText: 'Enter at least 3 characters to search',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearchingHsnSac
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_hsnSacMasterUnavailable) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'The HSN/SAC master has not been created in Supabase yet. Apply the project migration, then import the official GSTN master before using GST classification.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                  if (_selectedHsnSac != null) ...[
                    const SizedBox(height: 12),
                    _HsnSacSelection(entry: _selectedHsnSac!),
                  ],
                  if (_hsnSacResults.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _hsnSacResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final entry = _hsnSacResults[index];
                          return ListTile(
                            title: Text(
                              '${entry['code']} - ${entry['code_type']}',
                            ),
                            subtitle: Text(entry['description'].toString()),
                            onTap: () => _selectHsnSac(entry),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _gstRateController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'GST rate (%)',
                      helperText:
                          'Enter the rate manually; it is not taken from the HSN/SAC master.',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        _taxRateValidator(value, required: true),
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _isSaving
                      ? null
                      : () => _saveProduct(isGstRegistered),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Update' : 'Save'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UqcSelector extends StatefulWidget {
  const _UqcSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  State<_UqcSelector> createState() => _UqcSelectorState();
}

class _UqcSelectorState extends State<_UqcSelector> {
  List<Map<String, dynamic>> _units = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    try {
      final rows = await Supabase.instance.client
          .from('uqc_master')
          .select('code, description')
          .eq('is_active', true)
          .order('code');
      if (mounted) {
        setState(() => _units = List<Map<String, dynamic>>.from(rows));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _units
        .where((unit) => unit['code'] == widget.value)
        .firstOrNull;
    return FormField<String>(
      initialValue: widget.value,
      validator: (value) =>
          value == null ? 'Select a valid unit of measurement' : null,
      builder: (field) => InputDecorator(
        decoration: InputDecoration(
          labelText: 'Unit of Measurement',
          errorText: field.errorText,
          border: const OutlineInputBorder(),
        ),
        child: InkWell(
          onTap: widget.enabled && !_isLoading
              ? () async {
                  final unit = await _showPicker();
                  if (unit == null) return;
                  field.didChange(unit['code'] as String);
                  widget.onChanged(unit['code'] as String);
                }
              : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isLoading
                      ? 'Loading approved units...'
                      : selected == null
                      ? 'Select unit'
                      : '${selected['code']} - ${selected['description']}',
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _showPicker() {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final visibleUnits = _units.where((unit) {
              final searchable = '${unit['code']} ${unit['description']}'
                  .toLowerCase();
              return searchable.contains(query);
            }).toList();
            return AlertDialog(
              title: const Text('Select Unit of Measurement'),
              content: SizedBox(
                width: double.maxFinite,
                height: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (value) => setDialogState(
                        () => query = value.trim().toLowerCase(),
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Search code or description',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visibleUnits.length,
                        itemBuilder: (context, index) {
                          final unit = visibleUnits[index];
                          return ListTile(
                            title: Text(
                              '${unit['code']} - ${unit['description']}',
                            ),
                            onTap: () => Navigator.of(context).pop(unit),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HsnSacSelection extends StatelessWidget {
  const _HsnSacSelection({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry['code']} (${entry['code_type']})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(entry['description'] as String),
            const SizedBox(height: 4),
            const Text('The GST rate is entered manually below.'),
          ],
        ),
      ),
    );
  }
}

class _CustomerFormDialog extends StatefulWidget {
  const _CustomerFormDialog({this.customer, this.initialName});

  final Map<String, dynamic>? customer;
  final String? initialName;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _gstinController = TextEditingController();
  bool? _isGstRegistered;
  String? _state;
  bool _isSaving = false;
  bool _isLookingUpGstin = false;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    if (customer == null) {
      _nameController.text = widget.initialName?.trim() ?? '';
      return;
    }
    _nameController.text = customer['name']?.toString() ?? '';
    _phoneController.text = customer['phone']?.toString() ?? '';
    _emailController.text = customer['email']?.toString() ?? '';
    _addressController.text = customer['address']?.toString() ?? '';
    _gstinController.text = customer['gstin']?.toString() ?? '';
    _state = customer['state']?.toString();
    _isGstRegistered = _gstinController.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw const AuthException(
          'Your session has expired. Please sign in again.',
        );
      }
      final customer = <String, dynamic>{
        if (!_isEditing) 'id': const Uuid().v4(),
        'user_id': user.id,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'address': _addressController.text.trim(),
        'gstin': _isGstRegistered == true ? _gstinController.text.trim() : '',
        'state': _state,
      };
      try {
        if (_isEditing) {
          await Supabase.instance.client
              .from('customers')
              .update(customer)
              .eq('id', widget.customer!['id']);
        } else {
          await Supabase.instance.client.from('customers').insert(customer);
        }
      } catch (error) {
        if (error is PostgrestException || error is AuthException) rethrow;
        if (_isEditing) rethrow;
        await OfflineStore.enqueue('customers', customer);
        await OfflineStore.addCached('customers', customer);
      }

      if (mounted) {
        Navigator.of(
          context,
        ).pop(<String, dynamic>{...?widget.customer, ...customer});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save customer: $e')));
    }
  }

  Future<void> _lookupGstin() async {
    final gstin = _gstinController.text.trim().toUpperCase();
    final format = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
    if (!format.hasMatch(gstin)) {
      await showGstinResult(
        context,
        'Enter a valid GSTIN before verification.',
      );
      return;
    }
    setState(() => _isLookingUpGstin = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'gstin-lookup',
        body: {'gstin': gstin},
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) {
        throw Exception(
          body is Map
              ? body['error'] ?? 'GSTIN verification failed.'
              : 'GSTIN verification failed.',
        );
      }
      final data = Map<String, dynamic>.from(body['data'] as Map);
      if (!mounted) return;
      setState(() {
        _gstinController.text = data['gstin']?.toString() ?? gstin;
        _state = _stateFromGstin(gstin);
        final legalName = data['legal_name']?.toString().trim() ?? '';
        final tradeName = data['trade_name']?.toString().trim() ?? '';
        if (legalName.isNotEmpty || tradeName.isNotEmpty) {
          _nameController.text = _titleCase(
            tradeName.isNotEmpty ? tradeName : legalName,
          );
        }
        final address = data['address']?.toString().trim() ?? '';
        if (address.isNotEmpty) _addressController.text = _titleCase(address);
      });
      await showGstinResult(
        context,
        'GSTIN verified: ${data['status'] ?? 'status unavailable'}',
      );
    } catch (e) {
      if (mounted) {
        final message = e is FunctionException && e.details is Map
            ? (e.details['error']?.toString() ?? 'GSTIN verification failed.')
            : e.toString().replaceFirst('Exception: ', '');
        await showGstinResult(context, message);
      }
    } finally {
      if (mounted) setState(() => _isLookingUpGstin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      constraints: DesignSettings.modern.value
          ? const BoxConstraints(maxWidth: 600)
          : null,
      title: Text(_isEditing ? 'Edit Customer' : 'New Customer'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Is the customer registered for GST?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<bool>(
                initialValue: _isGstRegistered,
                decoration: const InputDecoration(
                  labelText: 'GST registration *',
                  hintText: 'Select Yes or No',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: true,
                    child: Text(
                      'Yes — GST registered',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text(
                      'No — enter details manually',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (registered) => setState(() {
                  _isGstRegistered = registered;
                  if (registered == false) _gstinController.clear();
                }),
                validator: (value) =>
                    value == null ? 'Please select Yes or No' : null,
              ),
              if (_isGstRegistered == true) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gstinController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (_, value) =>
                          value.copyWith(text: value.text.toUpperCase()),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'GSTIN *',
                    helperText:
                        'Enter GSTIN and tap Verify to auto-fill customer details.',
                    border: const OutlineInputBorder(),
                    suffixIcon: TextButton(
                      onPressed: _isLookingUpGstin ? null : _lookupGstin,
                      child: _isLookingUpGstin
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Verify'),
                    ),
                  ),
                  validator: (value) {
                    if (_isGstRegistered != true) return null;
                    final gstin = value?.trim().toUpperCase() ?? '';
                    if (gstin.isEmpty) return 'GSTIN is required';
                    return RegExp(
                          r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                        ).hasMatch(gstin)
                        ? null
                        : 'Enter a valid GSTIN';
                  },
                ),
              ],
              if (_isGstRegistered != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  inputFormatters: [_TitleCaseFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Customer Name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Customer name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  inputFormatters: [_TitleCaseFormatter()],
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SearchableStateField(
                  key: ValueKey(_state),
                  initialValue: _state,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'State / Union Territory *',
                    border: OutlineInputBorder(),
                  ),
                  items: _indianStatesAndUnionTerritories
                      .map(
                        (state) =>
                            DropdownMenuItem(value: state, child: Text(state)),
                      )
                      .toList(),
                  onChanged: (state) => setState(() => _state = state),
                  validator: (state) => state == null
                      ? 'State / Union Territory is required'
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveCustomer,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Update Customer' : 'Save Customer'),
        ),
      ],
    );
  }
}
