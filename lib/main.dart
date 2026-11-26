import 'dart:async';
import 'document_defaults.dart';
import 'document_text.dart';
import 'document_sharing.dart';
import 'invoice_palette.dart';
import 'whatsapp_contact.dart';
import 'modern_ui.dart';
import 'offline_queue.dart';
import 'document_pdf.dart';
import 'money.dart';
import 'live_sync.dart';
import 'app_lock.dart';
import 'business_access.dart';
import 'platform/local_files.dart';
import 'signature_pad.dart';
import 'image_editor.dart';

import 'app_version.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:excel_plus/excel_plus.dart' as xlsx;
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
part 'business_forms.dart';
part 'record_picker.dart';
part 'customer_form.dart';
part 'document_parts.dart';
part 'invoice_delete.dart';

final invoiceChanges = ValueNotifier<int>(0);

Future<void> _removeCatalogEntry(
  BuildContext context,
  String table,
  Map<String, dynamic> record,
  Future<void> Function() reload,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${record['name']}?'),
      content: const Text(
        'Remove this entry from your active list and new-document pickers. Existing invoices and quotations will stay unchanged.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Please sign in again.');
    }
    // Archive, never cascade-delete historical documents or their references.
    await Supabase.instance.client
        .from(table)
        .update({'is_active': false})
        .eq('id', record['id'])
        .eq('user_id', user.id)
        .select('id')
        .single();
    final cached = await OfflineStore.readList(table);
    cached.removeWhere((row) => row['id'] == record['id']);
    await OfflineStore.writeList(table, cached);
    invoiceChanges.value++;
    await reload();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to delete entry: $error')));
    }
  }
}

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

/// GST rules allow at most 16 characters in an invoice number. Numbers look
/// like PREFIX/2026-27/NN, so the prefix plus 11 characters (13 from the
/// 100th document) must fit. Returns a warning to show, or null.
String? prefixLengthWarning(String prefix) {
  final clean = prefix.trim();
  if (clean.isEmpty) return null;
  final length = clean.length + '/2026-27/01'.length;
  if (length > 16) {
    return 'Numbers like $clean/2026-27/01 have $length characters. GST allows 16. '
        'Use a prefix of 5 characters or fewer.';
  }
  if (length + 1 > 16) {
    return 'From the 100th document a year, numbers would pass the 16-character GST limit. '
        'A prefix of 4 characters or fewer avoids this.';
  }
  return null;
}

/// Shows [prefixLengthWarning] for the prefix fields as the user types.
class _PrefixLengthWarning extends StatelessWidget {
  const _PrefixLengthWarning(this.controllers);
  final List<TextEditingController> controllers;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(controllers),
    builder: (context, _) {
      final warnings = {
        for (final controller in controllers)
          ?prefixLengthWarning(controller.text),
      };
      if (warnings.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: SimplekColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                warnings.join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    },
  );
}

bool _isOfflineError(Object error) {
  if (isNetworkError(error)) return true;
  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('clientexception');
}

/// Tells the user about queued work the server refused, which will not retry.
Future<void> _showSyncRejections(
  BuildContext context,
  String name,
  String Function(Map<String, dynamic> item) describe,
) async {
  if (!context.mounted) return;
  final rejected = await OfflineStore.takeRejected(name);
  if (rejected.isEmpty || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Some offline changes were not saved'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in rejected)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${describe(Map<String, dynamic>.from(entry['item'] as Map))}\n'
                  '${entry['reason']}',
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
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

  static const _queueNames = [
    'customers',
    'products',
    'invoice_drafts',
    'payments',
  ];

  /// How many items per kind are waiting on this device for this account.
  static Future<Map<String, int>> pendingCounts() async => {
    for (final name in _queueNames)
      name: (await readList('${name}_queue')).length,
  };

  /// Items waiting on this device under accounts other than the current one.
  static Future<int> pendingOnOtherAccounts() async {
    final preferences = await SharedPreferences.getInstance();
    final own = _key('');
    var count = 0;
    for (final key in preferences.getKeys()) {
      if (!key.startsWith('offline_') || key.startsWith(own)) continue;
      if (!_queueNames.any((name) => key.endsWith('_${name}_queue'))) continue;
      try {
        count +=
            (jsonDecode(preferences.getString(key) ?? '[]') as List).length;
      } catch (_) {}
    }
    return count;
  }

  /// Uploads everything waiting for this account. Returns how many were sent.
  static Future<int> syncAll() async {
    if (Supabase.instance.client.auth.currentUser == null) return 0;
    var sent = 0;
    for (final step in <Future<int> Function()>[
      () => flush('customers', 'customers'),
      () => flush('products', 'products'),
      flushInvoiceDrafts,
      flushPayments,
    ]) {
      try {
        sent += await step();
      } catch (_) {}
    }
    return sent;
  }

  static Future<void> enqueue(String name, Map<String, dynamic> payload) =>
      OfflineQueue.add(_key('${name}_queue'), payload);

  /// Items the server refused during sync, cleared once returned.
  static Future<List<Map<String, dynamic>>> takeRejected(String name) =>
      OfflineQueue.takeRejected(_key('${name}_rejected'));

  static Future<int> _drain(
    String name,
    Future<void> Function(Map<String, dynamic> item) send,
  ) => OfflineQueue.drain(
    key: _key('${name}_queue'),
    rejectedKey: _key('${name}_rejected'),
    send: send,
  );

  static Future<int> flush(String table, String name) async {
    final synced = await _drain(name, (payload) async {
      try {
        await Supabase.instance.client.from(table).insert(payload);
      } on PostgrestException catch (error) {
        // Already saved by an earlier attempt.
        if (error.code != '23505') rethrow;
      }
    });
    if (synced > 0 && (name == 'customers' || name == 'products')) {
      invoiceChanges.value++;
    }
    return synced;
  }

  static Future<int> flushInvoiceDrafts() async {
    // A queued invoice may use a product that was also created offline.
    await flush('products', 'products');
    final synced = await _drain('invoice_drafts', (queued) async {
      final header = Map<String, dynamic>.from(queued['header'] as Map);
      final numberParams = queued['number_params'] as Map? ?? const {};
      await Supabase.instance.client.rpc(
        'save_invoice',
        params: {
          'p_invoice_id': header['id'],
          'p_header': header,
          'p_items': queued['items'],
          'p_number_prefix': numberParams['p_prefix'] ?? 'INV',
        },
      );
    });
    if (synced > 0) invoiceChanges.value++;
    return synced;
  }

  static Future<int> flushPayments() => _drain('payments', (queued) async {
    final params = Map<String, dynamic>.from(queued)
      ..removeWhere((key, _) => key.startsWith('_'));
    // Payments queued by earlier versions have no request id of their own.
    params['p_client_request_id'] ??= queued['_queue_id'];
    await Supabase.instance.client.rpc(
      'record_invoice_payment',
      params: params,
    );
  });
}

BusinessImageKind _imageKindFor(String type) => switch (type) {
  'signature' => BusinessImageKind.signature,
  'qr' || 'payment QR' => BusinessImageKind.qr,
  _ => BusinessImageKind.logo,
};

/// Picks an image from the gallery and opens it in the crop editor.
Future<String?> _pickAndEditImage(
  BuildContext context, {
  required String label,
}) async {
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  if (image == null) return null;
  final bytes = await image.readAsBytes();
  if (!context.mounted) return null;
  return editBusinessImage(
    context,
    bytes: bytes,
    kind: _imageKindFor(label),
    businessName: BusinessSettings.profile.value['name'] ?? '',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vvzaoxhygzhentywnlwr.supabase.co',
    publishableKey: 'sb_publishable_E3AJ4JWTv4yL656X9P5JuQ_H6Iwm1aY',
  );

  await BusinessSettings.load();
  await AppLock.load();
  LiveSync.changes.addListener(() => invoiceChanges.value++);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: BusinessSettings.themeMode,
      builder: (context, mode, _) => MaterialApp(
        themeMode: mode,
        theme: simplekTheme(Brightness.light),
        darkTheme: simplekTheme(Brightness.dark),
        debugShowCheckedModeBanner: false,
        title: 'Simplek',
        home: home ?? const AppLaunchSplash(),
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
    Future<void>.delayed(const Duration(milliseconds: kIsWeb ? 500 : 2600), () {
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

/// Where the email sign-up link returns to: the app on phones, this page on
/// the web.
String get _authRedirectUrl =>
    kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : 'simplek://login-callback/';

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
    LiveSync.sync();
    if (Supabase.instance.client.auth.currentSession != null) {
      unawaited(OfflineStore.syncAll());
      await BusinessAccess.restore();
      await BusinessSettings.syncFromCloud();
    } else {
      BusinessAccess.viewing.value = null;
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
    return AppLockGate(
      onUsePassword: () => Supabase.instance.client.auth.signOut(),
      child: const _ModernHome(),
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

/// The signed-in app frame (UI-25): a white sidebar from 1024 px, a ☰ button
/// with a full-width slide-in panel below that, and the bottom bar on phones.
class _ModernHome extends StatelessWidget {
  const _ModernHome();

  static const _sidebarBreakpoint = 1024.0;
  static const _phoneBreakpoint = 600.0;
  static const _moreIndex = 4;

  /// Sidebar order: (destination index, icon, label).
  static const _sidebar = <(int, IconData, String)>[
    (0, Icons.home_outlined, 'Home'),
    (1, Icons.receipt_long_outlined, 'Invoices'),
    (5, Icons.description_outlined, 'Quotations'),
    (6, Icons.account_balance_wallet_outlined, 'Payments'),
    (2, Icons.people_alt_outlined, 'Customers'),
    (3, Icons.inventory_2_outlined, 'Products and services'),
    (7, Icons.bar_chart_outlined, 'Reports'),
  ];

  static Widget _page(int index) => switch (index) {
    1 => const InvoiceHistoryPage(),
    2 => const CustomersPage(),
    3 => const ProductsPage(),
    4 => const _MorePage(),
    5 => const QuotationsPage(),
    6 => const PaymentsPage(),
    7 => const ReportsPage(),
    8 => const BusinessSettingsPage(),
    _ => const DashboardPage(),
  };

  Future<void> _create(BuildContext context) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Create',
                  style: Theme.of(sheet).textTheme.headlineSmall,
                ),
              ),
              RowGroup(
                children: [
                  for (final entry in const [
                    (
                      Icons.receipt_long_outlined,
                      'New invoice',
                      'Bill a customer and share the PDF',
                      TileTone.orange,
                    ),
                    (
                      Icons.description_outlined,
                      'New quotation',
                      'Send a price estimate first',
                      TileTone.sky,
                    ),
                    (
                      Icons.account_balance_wallet_outlined,
                      'Record payment',
                      'Mark money received on an invoice',
                      TileTone.navy,
                    ),
                  ].indexed)
                    ListRowTile(
                      leading: IconTile(
                        entry.$2.$1,
                        tone: entry.$2.$4,
                        size: 40,
                      ),
                      title: entry.$2.$2,
                      subtitle: entry.$2.$3,
                      showChevron: true,
                      onTap: () => Navigator.of(sheet).pop(entry.$1),
                    ),
                ],
              ),
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
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: BusinessAccess.viewing,
    builder: (context, viewing, _) => viewing == null
        ? _frame(context)
        : Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Column(
              children: [
                _ViewingBanner(name: viewing.name),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: _frame(context),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _frame(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: DesignSettings.destination,
    builder: (context, index, _) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final sidebar = width >= _sidebarBreakpoint;
        final phone = width < _phoneBreakpoint;
        // "More" only exists with the bottom bar; its tools are in the menu.
        final shown = !phone && index == _moreIndex ? 0 : index;
        final page = KeyedSubtree(key: ValueKey(shown), child: _page(shown));
        final Widget frame;
        if (sidebar) {
          frame = Scaffold(
            body: Row(
              children: [
                _Sidebar(selected: shown, onCreate: () => _create(context)),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: page,
                    ),
                  ),
                ),
              ],
            ),
          );
        } else if (!phone) {
          frame = _MenuFrame(
            page: page,
            selected: shown,
            onCreate: () => _create(context),
          );
        } else {
          frame = Scaffold(
            body: page,
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: index > _moreIndex ? _moreIndex : index,
                onDestinationSelected: (value) {
                  HapticFeedback.selectionClick();
                  DesignSettings.destination.value = value;
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'Invoices',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_alt_outlined),
                    selectedIcon: Icon(Icons.people_alt),
                    label: 'Customers',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: 'Items',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'More',
                  ),
                ],
              ),
            ),
          );
        }
        return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) DesignSettings.destination.value = 0;
          },
          child: frame,
        );
      },
    ),
  );
}

/// 600-1023 px: a slim top bar with ☰, which opens the sidebar as a
/// full-width panel that closes with ✕, a link or Escape.
class _MenuFrame extends StatelessWidget {
  const _MenuFrame({
    required this.page,
    required this.selected,
    required this.onCreate,
  });
  final Widget page;
  final int selected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: Drawer(
      width: MediaQuery.sizeOf(context).width,
      child: Builder(
        builder: (drawerContext) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(drawerContext).maybePop(),
          },
          child: Focus(
            autofocus: true,
            child: _Sidebar(
              selected: selected,
              onCreate: () {
                Navigator.of(drawerContext).pop();
                onCreate();
              },
              onClose: () => Navigator.of(drawerContext).pop(),
            ),
          ),
        ),
      ),
    ),
    body: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Builder(
                  builder: (context) => SquareIconButton(
                    icon: Icons.menu,
                    tooltip: 'Open menu',
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                const SizedBox(width: 12),
                const _Wordmark(),
              ],
            ),
          ),
        ),
        Expanded(child: page),
      ],
    ),
  );
}

/// The navy square with the receipt mark, and "Simplek" in Fraunces.
class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SimplekColors.navy,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.receipt_long,
          color: SimplekColors.orange,
          size: 22,
        ),
      ),
      const SizedBox(width: 10),
      Text(
        'Simplek',
        style: fraunces(24, Theme.of(context).colorScheme.onSurface),
      ),
    ],
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.onCreate,
    this.onClose,
  });
  final int selected;
  final VoidCallback onCreate;

  /// Set when shown as the slide-in panel: adds a ✕ button.
  final VoidCallback? onClose;

  void _go(BuildContext context, VoidCallback action) {
    onClose?.call();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final profile = BusinessSettings.profile.value;
    final business = (profile['name'] ?? '').trim();
    final initials = business.isEmpty
        ? 'S'
        : business
              .split(RegExp(r'\s+'))
              .where((word) => word.isNotEmpty)
              .take(2)
              .map((word) => word[0].toUpperCase())
              .join();
    Widget item(
      IconData icon,
      String label,
      bool isSelected,
      VoidCallback onTap,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Pressable(
        onTap: () => _go(context, onTap),
        borderRadius: BorderRadius.circular(12),
        color: isSelected
            ? (dark ? SimplekColors.navyDeep : SimplekColors.orangeTint)
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected
                      ? (dark ? SimplekColors.orange : SimplekColors.orangeText)
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: inter(
                      15,
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                      isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Container(
      width: onClose == null ? 248 : null,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: _Wordmark()),
                  if (onClose != null)
                    SquareIconButton(
                      icon: Icons.close,
                      tooltip: 'Close menu',
                      onPressed: onClose,
                    ),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: BusinessAccess.readOnly ? null : onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    for (final entry in _ModernHome._sidebar)
                      item(
                        entry.$2,
                        entry.$3,
                        entry.$1 == selected,
                        () => DesignSettings.destination.value = entry.$1,
                      ),
                    const Divider(height: 20),
                    item(
                      Icons.search,
                      'Search everything',
                      false,
                      () => _openPage(context, const GlobalSearchPage()),
                    ),
                    item(
                      Icons.supervisor_account_outlined,
                      'Accountant access',
                      false,
                      () => _openPage(context, const AccountantAccessPage()),
                    ),
                    item(
                      Icons.cloud_done_outlined,
                      'Sync and backup',
                      false,
                      () => _openPage(context, const SyncCenterPage()),
                    ),
                    if (!BusinessAccess.readOnly)
                      item(
                        Icons.settings_outlined,
                        'Settings',
                        selected == 8,
                        () => DesignSettings.destination.value = 8,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                decoration: BoxDecoration(
                  color: dark ? SimplekColors.navyDeep : SimplekColors.page,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: SimplekColors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        initials,
                        style: inter(15, FontWeight.w700, SimplekColors.navy),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            business.isEmpty ? 'Your business' : business,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: inter(14, FontWeight.w700, scheme.onSurface),
                          ),
                          Text(
                            'Version $appVersion',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Log out',
                      onPressed: () => _confirmLogout(context),
                      icon: Icon(
                        Icons.logout,
                        color: dark
                            ? SimplekColors.orange
                            : SimplekColors.orangeText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Log out of Simplek?'),
      content: const Text('You will need your password to log in again.'),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Stay'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (confirmed == true) await Supabase.instance.client.auth.signOut();
}

class _MorePage extends StatelessWidget {
  const _MorePage();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = BusinessSettings.profile.value;
    final business = (profile['name'] ?? '').trim();
    final gstin = (profile['gstin'] ?? '').trim();
    final initials = business.isEmpty
        ? 'S'
        : business
              .split(RegExp(r'\s+'))
              .where((word) => word.isNotEmpty)
              .take(2)
              .map((word) => word[0].toUpperCase())
              .join();
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? SimplekColors.navyDeep
                  : SimplekColors.navy,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: SimplekColors.orange,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    initials,
                    style: inter(19, FontWeight.w700, SimplekColors.navy),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.isEmpty ? 'Your business' : business,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: inter(17, FontWeight.w700, Colors.white),
                      ),
                      if (BusinessSettings.isGstRegistered.value &&
                          gstin.isNotEmpty)
                        Text(
                          'GSTIN $gstin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: inter(
                            13,
                            FontWeight.w500,
                            const Color(0xCCFFFFFF),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!BusinessAccess.readOnly)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SimplekColors.navy2,
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () =>
                        _openPage(context, const BusinessSettingsPage()),
                    child: const Text('Edit'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          RowGroup(
            children: [
              for (final entry
                  in <(IconData, String, String, TileTone, Widget)>[
                    (
                      Icons.description_outlined,
                      'Quotations',
                      'Send prices before you bill',
                      TileTone.sky,
                      const QuotationsPage(),
                    ),
                    (
                      Icons.account_balance_wallet_outlined,
                      'Payments',
                      'Record money you received',
                      TileTone.orange,
                      const PaymentsPage(),
                    ),
                    (
                      Icons.bar_chart_outlined,
                      'Reports',
                      BusinessSettings.isGstRegistered.value
                          ? 'Sales, dues, GSTR-1, Tally'
                          : 'Sales, dues, Tally',
                      TileTone.navy,
                      const ReportsPage(),
                    ),
                    (
                      Icons.search,
                      'Search everything',
                      'Customers, items, invoices',
                      TileTone.sky,
                      const GlobalSearchPage(),
                    ),
                    (
                      Icons.supervisor_account_outlined,
                      'Accountant access',
                      'Give a view-only login',
                      TileTone.orange,
                      const AccountantAccessPage(),
                    ),
                    (
                      Icons.cloud_done_outlined,
                      'Sync and backup',
                      'Everything is on the server',
                      TileTone.navy,
                      const SyncCenterPage(),
                    ),
                    if (!BusinessAccess.readOnly)
                      (
                        Icons.settings_outlined,
                        'Business settings',
                        'Profile, branding, app preferences',
                        TileTone.sky,
                        const BusinessSettingsPage(),
                      ),
                  ])
                ListRowTile(
                  leading: IconTile(entry.$1, tone: entry.$4, size: 40),
                  title: entry.$2,
                  subtitle: entry.$3,
                  showChevron: true,
                  onTap: () => _openPage(context, entry.$5),
                ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.brightness == Brightness.dark
                  ? SimplekColors.orange
                  : SimplekColors.orangeText,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

/// Shown when a save cannot reach the server. Nothing is kept on the device.
class _NotSavedOffline implements Exception {
  const _NotSavedOffline();
  static const message =
      'No internet connection. Nothing was saved. Connect and try again.';
  @override
  String toString() => message;
}

/// Uploads anything an earlier version of the app left waiting on this device.
class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key});

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  Map<String, int> _pending = const {};
  int _otherAccounts = 0;
  bool _loading = true;
  bool _syncing = false;
  String? _result;

  static const _labels = {
    'customers': 'Customers',
    'products': 'Products and services',
    'invoice_drafts': 'Invoices',
    'payments': 'Payments',
  };

  int get _total => _pending.values.fold(0, (sum, count) => sum + count);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final pending = await OfflineStore.pendingCounts();
    final others = await OfflineStore.pendingOnOtherAccounts();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _otherAccounts = others;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _result = null;
    });
    final uploaded = await OfflineStore.syncAll();
    await _refresh();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _result = _total == 0
          ? (uploaded == 0
                ? 'Nothing was waiting. Everything is already on the server.'
                : 'Uploaded $uploaded item${uploaded == 1 ? '' : 's'}. Everything is now on the server.')
          : 'Uploaded $uploaded. $_total still waiting. Check your internet connection and try again.';
    });
    for (final entry in <(String, String Function(Map<String, dynamic>))>[
      ('customers', (item) => 'Customer "${item['name'] ?? ''}"'),
      ('products', (item) => 'Product or service "${item['name'] ?? ''}"'),
      (
        'invoice_drafts',
        (item) =>
            'Invoice for ${(item['header'] as Map?)?['customer_name'] ?? 'a customer'}',
      ),
      ('payments', (item) => 'Payment of ₹${item['p_amount']}'),
    ]) {
      if (!mounted) return;
      await _showSyncRejections(context, entry.$1, entry.$2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final clear = _total == 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync & backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TintedIcon(
                          clear
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_upload_outlined,
                          color: clear
                              ? SimplekColors.success
                              : SimplekColors.warning,
                          size: 56,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          clear
                              ? 'Everything is on the server'
                              : '$_total item${_total == 1 ? '' : 's'} on this device not uploaded yet',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          clear
                              ? 'Nothing from this account is waiting on this device.'
                              : 'These were saved while offline. Upload them so they are safe and visible on the web.',
                          style: TextStyle(color: muted),
                        ),
                        if (!clear) ...[
                          const SizedBox(height: 14),
                          for (final entry in _pending.entries)
                            if (entry.value > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(_labels[entry.key]!)),
                                    Text(
                                      '${entry.value}',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _syncing ? null : _sync,
                          icon: _syncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(
                            _syncing
                                ? 'Uploading...'
                                : clear
                                ? 'Check again'
                                : 'Upload to server now',
                          ),
                        ),
                        if (_result != null) ...[
                          const SizedBox(height: 12),
                          Text(_result!),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_otherAccounts > 0) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const TintedIcon(
                        Icons.switch_account_outlined,
                        color: SimplekColors.warning,
                      ),
                      title: Text(
                        '$_otherAccounts item${_otherAccounts == 1 ? '' : 's'} waiting under another account',
                      ),
                      subtitle: const Text(
                        'Log out, log in to that account on this device, and open Sync & backup there.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Text('How saving works', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Invoices, quotations, payments, customers and products are '
                  'saved straight to the server, so they appear on the web and '
                  'on your other devices. If there is no internet, the app '
                  'tells you and saves nothing.',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
    );
  }
}

/// Switches the whole app to a shared business, or back to your own (null).
Future<void> _switchBusiness(
  BuildContext context,
  String? ownerId, {
  String name = 'Business',
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await BusinessAccess.view(ownerId, name: name);
    await BusinessSettings.syncFromCloud(clearIfMissing: true);
    invoiceChanges.value++;
    if (context.mounted) _returnToDashboard(context);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _connectionMessage(
            error,
            fallback: 'Could not switch business. Please try again.',
          ),
        ),
      ),
    );
  }
}

/// Shown above the app while an accountant is looking at a client's business.
class _ViewingBanner extends StatelessWidget {
  const _ViewingBanner({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => Material(
    color: SimplekColors.warning,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(
          children: [
            const Icon(
              Icons.visibility_outlined,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Viewing $name  •  view only',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _switchBusiness(context, null),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Exit'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Owners choose who may view their business; accountants open what has been
/// shared with them.
class AccountantAccessPage extends StatefulWidget {
  const AccountantAccessPage({super.key});

  @override
  State<AccountantAccessPage> createState() => _AccountantAccessPageState();
}

class _AccountantAccessPageState extends State<AccountantAccessPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _shared = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        BusinessAccess.readOnly
            ? Future.value(<Map<String, dynamic>>[])
            : BusinessAccess.invites(),
        BusinessAccess.sharedWithMe(),
      ]);
      if (!mounted) return;
      setState(() {
        _invites = results[0];
        _shared = results[1];
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _connectionMessage(
          error,
          fallback: 'Could not load accountant access. Please try again.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _invite() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim().toLowerCase();
    try {
      await BusinessAccess.invite(email);
      _emailController.clear();
      messenger.showSnackBar(
        SnackBar(content: Text('$email can now view your business')),
      );
      await _load();
    } on PostgrestException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (error.code) {
            '23505' => '$email already has access.',
            '42501' => 'You cannot give access to your own email.',
            _ => 'Could not give access: ${error.message}',
          }),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _connectionMessage(error, fallback: 'Could not give access.'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> invite) async {
    final email = invite['accountant_email']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Remove access?'),
        content: Text('$email will no longer be able to view your business.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BusinessAccess.remove(invite['id'].toString());
      await _load();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _connectionMessage(error, fallback: 'Could not remove access.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final viewing = BusinessAccess.viewing.value;
    return Scaffold(
      appBar: AppBar(title: const Text('Accountant access')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (_error != null)
                  Card(
                    child: ListTile(
                      leading: const TintedIcon(
                        Icons.cloud_off_outlined,
                        color: SimplekColors.warning,
                      ),
                      title: Text(_error!),
                      trailing: TextButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                if (viewing == null) ...[
                  Text(
                    'Who can view your business',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Give your accountant view-only access to your invoices, '
                    'quotations, customers and GST reports. They log in with '
                    'their own Simplek account and cannot change anything.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 14),
                  Form(
                    key: _formKey,
                    child: LabeledField(
                      label: "Accountant's email",
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          helperText:
                              'Use the email they sign up to Simplek with.',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: _emailValidator,
                        onFieldSubmitted: (_) => _invite(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving ? null : _invite,
                    icon: const Icon(Icons.person_add_alt_outlined),
                    label: Text(_saving ? 'Giving access...' : 'Give access'),
                  ),
                  const SizedBox(height: 16),
                  if (_invites.isEmpty)
                    Text(
                      'No one else can view your business.',
                      style: TextStyle(color: muted),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (index, invite) in _invites.indexed) ...[
                            if (index > 0) const Divider(indent: 72),
                            ListTile(
                              leading: const TintedIcon(
                                Icons.visibility_outlined,
                              ),
                              title: Text(
                                invite['accountant_email']?.toString() ?? '',
                              ),
                              subtitle: const Text('Can view, cannot edit'),
                              trailing: IconButton(
                                tooltip: 'Remove access',
                                onPressed: () => _remove(invite),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),
                ],
                if (viewing != null) ...[
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: const TintedIcon(
                        Icons.visibility_outlined,
                        color: SimplekColors.warning,
                      ),
                      title: Text('You are viewing ${viewing.name}'),
                      subtitle: const Text(BusinessAccess.readOnlyMessage),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _switchBusiness(context, null),
                    icon: const Icon(Icons.logout),
                    label: const Text('Return to my business'),
                  ),
                  const SizedBox(height: 28),
                ],
                if (_shared.isNotEmpty) ...[
                  Text('Shared with you', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (index, business) in _shared.indexed) ...[
                          if (index > 0) const Divider(indent: 72),
                          ListTile(
                            leading: const TintedIcon(
                              Icons.storefront_outlined,
                              color: SimplekColors.violet,
                            ),
                            title: Text(
                              business['business_name']?.toString() ??
                                  'Business',
                            ),
                            subtitle: Text(
                              business['viewing'] == true
                                  ? 'Viewing now'
                                  : 'View only',
                            ),
                            trailing: business['viewing'] == true
                                ? null
                                : FilledButton.tonal(
                                    onPressed: () => _switchBusiness(
                                      context,
                                      business['owner_id'].toString(),
                                      name:
                                          business['business_name']
                                              ?.toString() ??
                                          'Business',
                                    ),
                                    child: const Text('View'),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
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
    // The website's "Sign up" button opens the web app with ?signup=1.
    if (kIsWeb && Uri.base.queryParameters['signup'] == '1') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPage(context, const SignupPage());
      });
    }
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
      AppLock.markSignedInWithPassword();
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final card = AutofillGroup(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120B1A33),
              blurRadius: 16,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Welcome back', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Log in to send your next invoice.',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 14.5),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Email',
                child: TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'you@business.in',
                  ),
                  validator: _emailValidator,
                ),
              ),
              const SizedBox(height: 14),
              LabeledField(
                label: 'Password',
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.password],
                  style: const TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Password is required'
                      : null,
                  onFieldSubmitted: (_) => _login(),
                ),
              ),
              const SizedBox(height: 6),
              Pressable(
                onTap: () => setState(() => _rememberEmail = !_rememberEmail),
                borderRadius: BorderRadius.circular(10),
                child: Row(
                  children: [
                    Checkbox(
                      value: _rememberEmail,
                      onChanged: (value) =>
                          setState(() => _rememberEmail = value ?? true),
                    ),
                    const Flexible(child: Text('Remember my email')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _loading ? null : _login,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
                child: _loading
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: SimplekColors.navy,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Logging in…'),
                        ],
                      )
                    : const Text('Log in'),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('New to Simplek?', style: theme.textTheme.bodyMedium),
                  TextButton(
                    onPressed: () => _openPage(context, const SignupPage()),
                    style: TextButton.styleFrom(
                      textStyle: inter(
                        15,
                        FontWeight.w700,
                        SimplekColors.orangeText,
                      ).copyWith(decoration: TextDecoration.underline),
                    ),
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = constraints.maxHeight < 700 ? 230.0 : 300.0;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Stack(
                children: [
                  // Navy top panel with the logo and tagline (Login.png).
                  Container(
                    height: panelHeight,
                    width: double.infinity,
                    color: dark ? SimplekColors.navyDeep : SimplekColors.navy,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          right: -70,
                          top: -80,
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: const BoxDecoration(
                              color: SimplekColors.navy2,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          left: -50,
                          bottom: -60,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: const BoxDecoration(
                              color: SimplekColors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: SimplekColors.orange,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_long,
                                    color: SimplekColors.navy,
                                    size: 28,
                                    semanticLabel: 'Simplek',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Simplek',
                                style: fraunces(34, Colors.white),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Simple lekka for your business.',
                                style: inter(
                                  15,
                                  FontWeight.w500,
                                  const Color(0xFFBFE6FF),
                                ),
                              ),
                              SizedBox(height: panelHeight < 300 ? 22 : 40),
                              card,
                              const SizedBox(height: 28),
                              const VersionLine(),
                            ],
                          ),
                        ),
                      ),
                    ),
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
            LabeledField(
              label: 'Name',
              child: TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [_TitleCaseFormatter()],
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Name is required'
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Business name (optional)',
              child: TextFormField(
                controller: _businessController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [_TitleCaseFormatter()],
                autofillHints: const [AutofillHints.organizationName],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Mobile number',
              child: TextFormField(
                controller: _mobileController,
                keyboardType: TextInputType.phone,
                inputFormatters: [_IndianMobileFormatter()],
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.phone_outlined),
                  helperText: 'India: enter 10 digits',
                ),
                validator: (value) =>
                    RegExp(r'^[6-9]\d{9}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Enter a valid 10-digit mobile number',
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'Email',
              child: TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: _emailValidator,
              ),
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
                  LabeledField(
                    label: 'Password',
                    child: TextFormField(
                      controller: _passwordController,
                      obscureText: !_showPasswords,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
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
                  ),
                  const SizedBox(height: 14),
                  LabeledField(
                    label: 'Confirm password',
                    child: TextFormField(
                      controller: _confirmController,
                      obscureText: !_showPasswords,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(),
                      validator: (value) => value == _passwordController.text
                          ? null
                          : 'Passwords do not match',
                      onFieldSubmitted: (_) => _setPassword(),
                    ),
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

/// The signed-in user's email, or '' before Supabase is ready.
String _signedInEmail() {
  try {
    return Supabase.instance.client.auth.currentUser?.email ?? '';
  } catch (_) {
    return '';
  }
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
  final _address = _AddressDraft.fromProfile(const {});
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _panController;
  late final TextEditingController _invoicePrefixController;
  late final TextEditingController _quotationPrefixController;
  late final TextEditingController _quotationTermsController;
  late final TextEditingController _invoiceTermsController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _branchController;
  late final TextEditingController _accountController;
  late final TextEditingController _ifscController;
  final _upiController = TextEditingController();

  /// No default: the owner must answer (CR-25 change 1).
  bool? _gstRegistered;
  String _gstRegistrationType = 'Regular';
  bool _verifying = false;
  bool _gstVerified = false;
  String? _gstStatusText;
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
    _phoneController = TextEditingController(text: widget.mobile);
    _emailController = TextEditingController(text: _signedInEmail());
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
    _invoicePrefixController = TextEditingController(text: 'INV');
    _quotationPrefixController = TextEditingController(text: 'QTN');
  }

  @override
  void dispose() {
    for (final controller in [
      _ownerController,
      _businessController,
      _gstinController,
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
      _invoicePrefixController,
      _quotationPrefixController,
    ]) {
      controller.dispose();
    }
    _address.dispose();
    super.dispose();
  }

  Future<void> _verifyGstin() async {
    final gstin = _gstinController.text.trim().toUpperCase();
    final problem = gstinError(gstin, required: true);
    if (problem != null) {
      await showGstinResult(context, problem);
      return;
    }
    setState(() => _verifying = true);
    try {
      final data = await _lookupGstin(gstin);
      if (!mounted) return;
      final status = gstinStatusMessage(data['status']);
      setState(() {
        _gstinController.text = data['gstin']?.toString() ?? gstin;
        final legalName = data['legal_name']?.toString().trim() ?? '';
        final tradeName = data['trade_name']?.toString().trim() ?? '';
        if (tradeName.isNotEmpty || legalName.isNotEmpty) {
          _businessController.text = _titleCase(
            tradeName.isNotEmpty ? tradeName : legalName,
          );
        }
        _fillAddressFromGst(_address, data['address']?.toString() ?? '');
        _gstVerified = true;
        _gstStatusText = status;
      });
      await showGstinResult(context, status);
    } catch (error) {
      if (mounted) {
        await showGstinResult(
          context,
          error is StateError ? error.message : 'GSTIN lookup failed.',
        );
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

  Future<void> _editImage(String type) async {
    final current = switch (type) {
      'logo' => _logoPath,
      'signature' => _signaturePath,
      _ => _qrPath,
    };
    final bytes = await readLocalFile(current);
    if (bytes == null || !mounted) return;
    final path = await editBusinessImage(
      context,
      bytes: bytes,
      kind: _imageKindFor(type),
      businessName: BusinessSettings.profile.value['name'] ?? '',
    );
    if (path == null || !mounted) return;
    setState(() {
      if (type == 'logo') _logoPath = path;
      if (type == 'signature') _signaturePath = path;
      if (type == 'qr') _qrPath = path;
    });
  }

  void _removeImage(String type) => setState(() {
    if (type == 'logo') _logoPath = '';
    if (type == 'signature') _signaturePath = '';
    if (type == 'qr') _qrPath = '';
  });

  Widget _brandingTiles() => Row(
    children: [
      for (final (type, label) in const [
        ('logo', 'Logo'),
        ('signature', 'Signature'),
        ('qr', 'Payment QR'),
      ]) ...[
        if (type != 'logo') const SizedBox(width: 10),
        Expanded(
          child: BusinessImageTile(
            label: label,
            path: switch (type) {
              'logo' => _logoPath,
              'signature' => _signaturePath,
              _ => _qrPath,
            },
            onUpload: () => _pickImage(type),
            onEdit: () => _editImage(type),
            onDraw: type == 'signature' ? _drawSignature : null,
            onRemove: () => _removeImage(type),
          ),
        ),
      ],
    ],
  );

  Future<void> _drawSignature() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => const SignaturePadDialog(),
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
    try {
      final response = await http.get(
        Uri.parse('https://ifsc.razorpay.com/$ifsc'),
      );
      if (response.statusCode != 200) throw StateError('Not found');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
      if (mounted) setState(() => _lookingUpIfsc = false);
    }
  }

  void _continue() {
    if (_step == 0) {
      if (!_detailsKey.currentState!.validate()) return;
      if (_gstRegistered == true && !_gstVerified) {
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
      await BusinessSettings.setGstRegistered(_gstRegistered == true);
      await BusinessSettings.setDocumentTerms(
        quotation: _quotationTermsController.text.trim(),
        invoice: _invoiceTermsController.text.trim(),
      );
      await BusinessSettings.saveProfile({
        'ownerName': _ownerController.text.trim(),
        'name': _businessController.text.trim(),
        ..._address.toProfile(),
        'gstin': _gstRegistered == true
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

  static const _stepNames = ['Business', 'Terms', 'Branding'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = switch (_step) {
      0 => _detailsStep(),
      1 => _termsStep(),
      _ => _brandingStep(),
    };
    return Scaffold(
      body: SafeArea(
        child: FormWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      SquareIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        onPressed: () => setState(() => _step--),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Set up your business',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            'Step ${_step + 1} of 3 · takes about a minute',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Step bar: orange for done and current steps.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: i <= _step
                                    ? SimplekColors.orange
                                    : theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${i + 1}. ${_stepNames[i]}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: inter(
                                12,
                                i == _step ? FontWeight.w700 : FontWeight.w500,
                                i == _step
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: KeyedSubtree(key: ValueKey(_step), child: content),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          child: FormWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: _step == 2
                          ? (_saving ? null : _finish)
                          : _continue,
                      child: _saving
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: SimplekColors.navy,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Saving…'),
                              ],
                            )
                          : Text(_step == 2 ? 'Finish setup' : 'Continue'),
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

  Widget _detailsStep() => Form(
    key: _detailsKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeledText(
          _ownerController,
          'Your name',
          required: true,
          autofillHints: const [AutofillHints.name],
          textCapitalization: TextCapitalization.words,
          maxLength: 100,
          validator: (value) =>
              value.trim().length < 2 ? 'Enter your name' : null,
        ),
        const SizedBox(height: 14),
        _labeledText(
          _businessController,
          'Business name',
          required: true,
          autofillHints: const [AutofillHints.organizationName],
          textCapitalization: TextCapitalization.words,
          maxLength: 100,
          validator: (value) =>
              value.trim().length < 2 ? 'Enter the business name' : null,
        ),
        const SizedBox(height: 18),
        const FieldLabel(
          'Is your business registered under GST?',
          required: true,
        ),
        YesNoFormField(
          initialValue: _gstRegistered,
          yesLabel: 'Yes, registered',
          noLabel: 'No, not registered',
          onChanged: (value) => setState(() {
            _gstRegistered = value;
            _gstVerified = false;
            if (!value) _gstinController.clear();
          }),
        ),
        if (_gstRegistered == true) ...[
          const SizedBox(height: 14),
          LabeledField(
            label: 'GST registration type',
            required: true,
            child: DropdownButtonFormField<String>(
              initialValue: _gstRegistrationType,
              isExpanded: true,
              items: const ['Regular', 'Composition', 'Casual', 'Non-resident']
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _gstRegistrationType = value!),
            ),
          ),
          const SizedBox(height: 14),
          _labeledText(
            _gstinController,
            'Business GSTIN',
            required: true,
            hint: '15 characters, e.g. 29ABCDE1234F1Z5',
            inputFormatters: upperCaseCodeFormatters(15),
            helper: _gstVerified
                ? _gstStatusText
                : 'Verify to fill your registered business name.',
            onChanged: (_) => setState(() {
              _gstVerified = false;
              _gstStatusText = null;
            }),
            validator: (value) => gstinError(value, required: true),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _verifying ? null : _verifyGstin,
              icon: _verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _gstVerified ? Icons.verified : Icons.verified_outlined,
                    ),
              label: Text(_verifying ? 'Verifying…' : 'Verify GSTIN'),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _labeledText(
          _panController,
          'PAN',
          optional: true,
          hint: 'e.g. ABCDE1234F',
          inputFormatters: upperCaseCodeFormatters(10),
          validator: (value) =>
              value.trim().isEmpty ||
                  RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(value.trim())
              ? null
              : 'Enter a valid PAN, e.g. ABCDE1234F',
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _labeledText(
                _invoicePrefixController,
                'Invoice prefix',
                required: true,
                inputFormatters: upperCaseCodeFormatters(20),
                validator: (value) => _prefixValidator(value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _labeledText(
                _quotationPrefixController,
                'Quotation prefix',
                required: true,
                inputFormatters: upperCaseCodeFormatters(20),
                validator: (value) => _prefixValidator(value),
              ),
            ),
          ],
        ),
        _PrefixLengthWarning([
          _invoicePrefixController,
          _quotationPrefixController,
        ]),
        const SizedBox(height: 20),
        Text(
          'Business address',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        _BusinessAddressFields(
          draft: _address,
          lockedState: _gstRegistered == true
              ? _gstinState(_gstinController.text)
              : null,
        ),
        const SizedBox(height: 14),
        _labeledText(
          _phoneController,
          'Mobile number',
          optional: true,
          hint: '10 digits',
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [_IndianMobileFormatter()],
          validator: _mobileError,
        ),
        const SizedBox(height: 14),
        _labeledText(
          _emailController,
          'Business email',
          required: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          maxLength: 254,
          validator: (value) => _emailValidator(value),
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
        LabeledField(
          label: 'Default quotation terms',
          child: TextFormField(
            controller: _quotationTermsController,
            minLines: 5,
            maxLines: 9,
            decoration: const InputDecoration(),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Add quotation terms'
                : null,
          ),
        ),
        const SizedBox(height: 14),
        LabeledField(
          label: 'Default invoice terms',
          child: TextFormField(
            controller: _invoiceTermsController,
            minLines: 5,
            maxLines: 9,
            decoration: const InputDecoration(),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Add invoice terms'
                : null,
          ),
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
        _brandingTiles(),
        const SizedBox(height: 6),
        Text(
          'Tap a tile to upload, crop, draw or remove.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),
        LabeledField(
          label: 'UPI ID (optional)',
          child: TextFormField(
            controller: _upiController,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'business@bank',
              helperText:
                  'A scannable UPI payment QR code will be generated automatically.',
            ),
            validator: (value) {
              final upi = value?.trim() ?? '';
              return upi.isEmpty || _isValidUpiId(upi)
                  ? null
                  : 'Enter a valid UPI ID';
            },
          ),
        ),
        if (_isValidUpiId(_upiController.text)) ...[
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                QrImageView(
                  backgroundColor: Colors.white,
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
        LabeledField(
          label: 'IFSC code',
          child: TextFormField(
            controller: _ifscController,
            inputFormatters: upperCaseCodeFormatters(11),
            onChanged: _lookupOnboardingIfsc,
            decoration: const InputDecoration(
              helperText:
                  'Enter the IFSC Code to prefill bank and branch details',
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
        ),
        if (_lookingUpIfsc || _ifscMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _lookingUpIfsc ? 'Looking up bank and branch...' : _ifscMessage!,
          ),
        ],
        const SizedBox(height: 12),
        LabeledField(
          label: 'Bank name',
          child: TextFormField(
            controller: _bankNameController,
            decoration: const InputDecoration(),
          ),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Branch',
          child: TextFormField(
            controller: _branchController,
            decoration: const InputDecoration(),
          ),
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Account number',
          child: TextFormField(
            controller: _accountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(),
          ),
        ),
      ],
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
        Supabase.instance.client
            .from('customers')
            .select()
            .eq('is_active', true)
            .limit(100),
        Supabase.instance.client
            .from('products')
            .select('id, name, product_type, hsn_sac_code, selling_price')
            .eq('is_active', true)
            .limit(100),
        Supabase.instance.client
            .from('invoices')
            .select(
              'id, invoice_number, customer_name, invoice_date, status, total_amount, description',
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

      addMatches(data[0], 'customer', [
        'name',
        'phone',
        'email',
        if (BusinessSettings.isGstRegistered.value) 'gstin',
      ]);
      addMatches(data[1], 'product', ['name', 'product_type', 'hsn_sac_code']);
      addMatches(data[2], 'invoice', [
        'invoice_number',
        'customer_name',
        'status',
        'description',
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
        if ('${row['name']} ${row['product_type']} ${row['hsn_sac_code']}'
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
              hintText: 'Customers, items, invoices, quotations',
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
  int _productCount = 0;
  double _totalSales = 0;
  double _outstanding = 0;
  double _collected = 0;
  int _unpaidCount = 0;
  int _partlyPaidCount = 0;
  List<Map<String, dynamic>> _recentInvoices = [];
  bool _isLoadingSummary = true;
  String? _summaryError;
  int _summaryRequest = 0;

  @override
  void initState() {
    super.initState();
    invoiceChanges.addListener(_loadSummary);
    _loadSummary();
  }

  @override
  void dispose() {
    invoiceChanges.removeListener(_loadSummary);
    super.dispose();
  }

  Future<void> _loadSummary() async {
    final request = ++_summaryRequest;
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
              'id, invoice_number, customer_name, invoice_date, status, total_amount, balance_amount, paid_amount',
            )
            .neq('status', 'draft')
            .neq('status', 'cancelled')
            .order('invoice_date', ascending: false)
            .order('created_at', ascending: false)
            .limit(100),
        Supabase.instance.client
            .from('customers')
            .select('id')
            .eq('is_active', true),
        Supabase.instance.client
            .from('products')
            .select('id')
            .eq('is_active', true),
      ]).timeout(const Duration(seconds: 15));
      final invoices = List<Map<String, dynamic>>.from(results[0] as List);
      final customers = List<Map<String, dynamic>>.from(results[1] as List);
      var totalSales = 0.0;
      var outstanding = 0.0;
      var collected = 0.0;
      var unpaid = 0;
      var partlyPaid = 0;
      for (final invoice in invoices) {
        if (invoice['status']?.toString() != 'cancelled') {
          totalSales += _asDouble(invoice['total_amount']);
          outstanding += _asDouble(invoice['balance_amount']);
          collected += _asDouble(invoice['paid_amount']);
          if (_asDouble(invoice['balance_amount']) > 0) unpaid++;
          if (invoice['status']?.toString() == 'partial') partlyPaid++;
        }
      }
      if (!mounted || request != _summaryRequest) return;
      setState(() {
        _invoiceCount = invoices.length;
        _customerCount = customers.length;
        _productCount = (results[2] as List).length;
        _totalSales = totalSales;
        _outstanding = outstanding;
        _collected = collected;
        _unpaidCount = unpaid;
        _partlyPaidCount = partlyPaid;
        _recentInvoices = invoices.take(5).toList();
      });
    } catch (error) {
      if (mounted && request == _summaryRequest) {
        setState(() => _summaryError = error.toString());
      }
    } finally {
      if (mounted && request == _summaryRequest) {
        setState(() => _isLoadingSummary = false);
      }
    }
  }

  String _money(double amount) => rupees(amount);

  double _asDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ModernOverview(
          businessName: BusinessSettings.profile.value['name'] ?? '',
          readOnly: BusinessAccess.readOnly,
          sales: _money(_totalSales),
          outstanding: _money(_outstanding),
          invoiceCount: '$_invoiceCount',
          customerCount: '$_customerCount',
          productCount: '$_productCount',
          loading: _isLoadingSummary,
          error: _summaryError,
          recent: _recentInvoices
              .map(
                (row) => <String, String>{
                  'id': row['id']?.toString() ?? '',
                  'number': row['invoice_number']?.toString() ?? 'Invoice',
                  'customer': row['customer_name']?.toString() ?? '',
                  'amount': _money(_asDouble(row['total_amount'])),
                  'status': row['status']?.toString() ?? 'draft',
                  'date': screenDate(parseStoredDate(row['invoice_date'])),
                },
              )
              .toList(),
          onNewInvoice: () => _openPage(context, const InvoiceBuilderPage()),
          onNewQuotation: () =>
              _openPage(context, const QuotationBuilderPage()),
          onCustomer: () async {
            await _showCustomerForm(context);
            if (mounted) await _loadSummary();
          },
          onProduct: () => _openPage(context, const AddProductPage()),
          onInvoices: () => DesignSettings.destination.value = 1,
          onOpenInvoice: (id) =>
              _openPage(context, InvoiceViewPage(invoiceId: id)),
          onRefresh: _loadSummary,
          onPayment: () => _openPage(context, const PaymentsPage()),
          onSearch: () => _openPage(context, const GlobalSearchPage()),
          onReports: () => _openPage(context, const ReportsPage()),
          unpaidCount: _isLoadingSummary && _recentInvoices.isEmpty
              ? null
              : _unpaidCount,
          collected: _money(_collected),
          partlyPaidCount: _partlyPaidCount,
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
  // A bottom sheet on phones, a dialog on wider screens (NewCustomer.png).
  final saved = MediaQuery.sizeOf(context).width < 600
      ? await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => CustomerFormDialog(
            customer: customer,
            initialName: initialName,
            asSheet: true,
          ),
        )
      : await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (_) =>
              CustomerFormDialog(customer: customer, initialName: initialName),
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
    _loadDues();
    LiveSync.changes.addListener(_loadCustomers);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    LiveSync.changes.removeListener(_loadCustomers);
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await OfflineStore.flush('customers', 'customers');
      if (mounted) {
        unawaited(
          _showSyncRejections(
            context,
            'customers',
            (item) => 'Customer "${item['name'] ?? ''}"',
          ),
        );
      }
      final rows = await Supabase.instance.client
          .from('customers')
          .select()
          .eq('is_active', true)
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

  /// What each customer still owes, by name (invoices store the name).
  Map<String, double> _dues = const {};

  Future<void> _loadDues() async {
    try {
      final rows = await Supabase.instance.client
          .from('invoices')
          .select('customer_name, balance_amount, status')
          .gt('balance_amount', 0);
      final dues = <String, double>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (row['status']?.toString() == 'cancelled') continue;
        final name =
            row['customer_name']?.toString().trim().toLowerCase() ?? '';
        dues[name] =
            (dues[name] ?? 0) +
            ((row['balance_amount'] as num?)?.toDouble() ?? 0);
      }
      if (mounted) setState(() => _dues = dues);
    } catch (_) {
      // The list still works without the amounts.
    }
  }

  @override
  Widget build(BuildContext context) {
    final owed = _dues.values.fold<double>(0, (sum, value) => sum + value);
    return Scaffold(
      floatingActionButton: BusinessAccess.readOnly
          ? null
          : CreateButton(label: 'New customer', onPressed: _addCustomer),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(
              title: _showingCached ? 'Customers (offline)' : 'Customers',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _ListSearch(
                controller: _searchController,
                hint: BusinessSettings.isGstRegistered.value
                    ? 'Search name, mobile or GSTIN'
                    : 'Search name or mobile',
                onChanged: (_) {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Customers',
                      value: '${_customers.length}',
                      tone: TileTone.navy,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Owe you',
                      value: rupees(owed),
                      tone: TileTone.orange,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _customers.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: const [SkeletonRows()],
      );
    }
    if (_errorMessage != null) {
      return _loadError(_errorMessage!, _loadCustomers);
    }

    final customers = _visibleCustomers;
    final hasSearch = _searchController.text.trim().isNotEmpty;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadCustomers(), _loadDues()]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          if (customers.isEmpty)
            EmptyState(
              icon: Icons.people_outline,
              message: hasSearch
                  ? 'No customers match this search.'
                  : 'No customers yet. Add your first customer.',
              actionLabel: hasSearch || BusinessAccess.readOnly
                  ? null
                  : 'New customer',
              onAction: _addCustomer,
            )
          else
            RowGroup(
              children: [
                for (final customer in customers)
                  Builder(
                    builder: (context) {
                      final name =
                          customer['name'] as String? ?? 'Unnamed customer';
                      final due = _dues[name.trim().toLowerCase()] ?? 0;
                      final gstin = BusinessSettings.isGstRegistered.value
                          ? (customer['gstin'] as String? ?? '')
                          : '';
                      final contact = [
                        (customer['phone'] as String?) ?? '',
                        if (gstin.isNotEmpty) 'GSTIN $gstin',
                      ].where((part) => part.isNotEmpty).join(' · ');
                      return ListRowTile(
                        leading: InitialTile(name),
                        title: name,
                        subtitle: contact.isEmpty
                            ? (customer['email'] as String? ?? '')
                            : contact,
                        onTap: () => _openPage(
                          context,
                          CustomerHistoryPage(customer: customer),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              due > 0 ? '${rupees(due)} due' : 'All paid',
                              maxLines: 1,
                              style: inter(
                                13.5,
                                FontWeight.w700,
                                due > 0
                                    ? (dark
                                          ? SimplekColors.orange
                                          : SimplekColors.orangeText)
                                    : (dark
                                          ? SimplekColors.sky
                                          : SimplekColors.skyText),
                              ),
                            ),
                            if (!BusinessAccess.readOnly)
                              PopupMenuButton<String>(
                                tooltip: 'Customer actions',
                                onSelected: (value) => value == 'edit'
                                    ? _editCustomer(customer)
                                    : _removeCatalogEntry(
                                        context,
                                        'customers',
                                        customer,
                                        _loadCustomers,
                                      ),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit customer'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete customer'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
        ],
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
  String _money(double amount) => rupees(amount);

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
                                  '${screenDate(parseStoredDate(invoice['invoice_date']))} · ${(invoice['status'] ?? 'draft').toString().toUpperCase()}',
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
                                  '${screenDate(parseStoredDate(quote['quotation_date']))} · ${(quote['status'] ?? 'draft').toString().toUpperCase()}',
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

  static final themeMode = ValueNotifier(ThemeMode.light);

  static Future<void> setThemeMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('app_theme_mode', mode.name);
    themeMode.value = mode;
  }

  static const _secureStorage = FlutterSecureStorage();
  static const _gstRegisteredKey = 'business_gst_registered';
  static const _lightDefaultAppliedKey = 'app_theme_light_default_20261126';
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
  static const _invoicePrefixKey = 'business_invoice_prefix';
  static const _quotationPrefixKey = 'business_quotation_prefix';

  /// The address split into fields (CR-25 change 11). 'address' keeps the
  /// whole address as one line for older app versions.
  static const _addressFieldKeys = {
    'addressLine1': 'business_address_line1',
    'addressLine2': 'business_address_line2',
    'landmark': 'business_landmark',
    'city': 'business_city',
    'district': 'business_district',
    'pincode': 'business_pincode',
  };
  static const _addressColumns = {
    'addressLine1': 'address_line1',
    'addressLine2': 'address_line2',
    'landmark': 'landmark',
    'city': 'city',
    'district': 'district',
    'pincode': 'pincode',
  };
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

  static Future<String?> _uploadBusinessMedia(
    String localPath,
    String type,
    String userId,
  ) async {
    // '' clears the stored image; null leaves it unchanged, so a missing local
    // copy or a failed upload never erases the cloud reference.
    if (localPath.isEmpty) return '';
    final bytes = await readLocalFile(localPath);
    if (bytes == null) return null;
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
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return objectPath;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _downloadBusinessMedia(
    String objectPath,
    String type,
    String fallback,
  ) async {
    // An empty path in the cloud means the image was removed.
    if (objectPath.isEmpty) return '';
    try {
      final bytes = await Supabase.instance.client.storage
          .from('business-media')
          .download(objectPath);
      final extension = objectPath.split('.').last.toLowerCase();
      return await writeAppFile('business_$type.$extension', bytes);
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    // UI-25: light is the default, once, for new installs and for anyone on
    // Auto or Dark before the redesign. A theme chosen after that is kept.
    if (preferences.getBool(_lightDefaultAppliedKey) != true) {
      await preferences.setString('app_theme_mode', ThemeMode.light.name);
      await preferences.setBool(_lightDefaultAppliedKey, true);
    }
    themeMode.value = ThemeMode.values.firstWhere(
      (mode) => mode.name == preferences.getString('app_theme_mode'),
      orElse: () => ThemeMode.light,
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
      'invoicePrefix': preferences.getString(_invoicePrefixKey) ?? 'INV',
      'invoiceTheme':
          preferences.getString(_invoiceThemeCacheKey) ?? 'white-blue',
      'quotationPrefix': preferences.getString(_quotationPrefixKey) ?? 'QTN',
      for (final entry in _addressFieldKeys.entries)
        entry.key: preferences.getString(entry.value) ?? '',
    };
  }

  /// Loads the profile of the business on screen: your own, or the shared
  /// business being viewed. [clearIfMissing] empties the local copy when that
  /// business has no saved profile, so another business's details never linger.
  static Future<void> syncFromCloud({bool clearIfMissing = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final viewing = BusinessAccess.viewing.value;
    try {
      final row = await Supabase.instance.client
          .from('business_profiles')
          .select()
          .eq('user_id', viewing?.ownerId ?? user.id)
          .maybeSingle();
      if (row == null) {
        if (clearIfMissing || viewing != null) {
          await _saveLocalProfile({if (viewing != null) 'name': viewing.name});
        }
        return;
      }
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
        'invoicePrefix': row['invoice_prefix']?.toString() ?? 'INV',
        'invoiceTheme': InvoicePalette.resolve(
          user.userMetadata?['invoice_theme']?.toString(),
        ).id,
        'quotationPrefix': row['quotation_prefix']?.toString() ?? 'QTN',
        for (final entry in _addressColumns.entries)
          entry.key: row[entry.value]?.toString() ?? '',
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
    if (BusinessAccess.readOnly) {
      throw StateError(BusinessAccess.readOnlyMessage);
    }
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
      'invoice_prefix': value['invoicePrefix'] ?? 'INV',
      'quotation_prefix': value['quotationPrefix'] ?? 'QTN',
      for (final entry in _addressColumns.entries)
        entry.value: value[entry.key] ?? '',
      if (mediaPaths[0] != null) 'logo_object_path': mediaPaths[0],
      if (mediaPaths[1] != null) 'signature_object_path': mediaPaths[1],
      if (mediaPaths[2] != null) 'qr_object_path': mediaPaths[2],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(
        data: {
          'invoice_theme': InvoicePalette.resolve(value['invoiceTheme']).id,
        },
      ),
    );
  }

  static Future<void> _saveLocalProfile(Map<String, String> value) async {
    profile.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _invoiceThemeCacheKey,
      InvoicePalette.resolve(value['invoiceTheme']).id,
    );
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
    for (final entry in _addressFieldKeys.entries) {
      await preferences.setString(entry.value, value[entry.key] ?? '');
    }
    await preferences.remove('business_place_of_supply');
    await preferences.remove('business_financial_year');
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
    final sample = InvoiceLineItem(gstApplies: _gstRegistered == true);
    sample.productController.text = 'Sample product';
    sample.quantityController.text = '2';
    sample.rateController.text = '500';
    sample.gstRateController.text = '18';
    final previewProfile = <String, String>{
      ...BusinessSettings.profile.value,
      'name': _nameController.text.trim(),
      ..._address.toProfile(),
      'phone': _phoneController.text.trim(),
      'email': _emailController.text.trim(),
      'gstin': _gstinController.text.trim(),
      'bankName': _bankNameController.text.trim(),
      'bankBranch': _branchController.text.trim(),
      'bankAccount': _accountController.text.trim(),
      'ifsc': _ifscController.text.trim(),
      'upiId': _upiController.text.trim(),
      'logoPath': _logoPath,
      'signaturePath': _signaturePath,
      'qrPath': _qrPath,
      'invoiceTheme': _invoiceTheme,
    };
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => InvoicePreviewPage(
            customerName: 'Sample Customer',
            customerPhone: '',
            customerEmail: '',
            placeOfSupply: _address.state ?? '',
            invoiceDate: DateTime.now(),
            dueDate: DateTime.now().add(const Duration(days: 7)),
            terms: _invoiceTermsController.text,
            items: [sample],
            invoiceNumber: 'SAMPLE/2026-27/01',
            balanceDue: roundToRupee(sample.total),
            gstDocument: _gstRegistered == true,
            previewProfile: previewProfile,
          ),
        ),
      );
    } finally {
      sample.dispose();
    }
  }

  final _formKey = GlobalKey<FormState>();
  late String _invoiceTheme;
  late final TextEditingController _quotationTermsController;
  late final TextEditingController _invoiceTermsController;
  late final TextEditingController _ownerController;
  late final TextEditingController _nameController;
  late final _AddressDraft _address;
  late final bool _addressNeedsCompleting;
  bool? _gstRegistered;
  late final TextEditingController _gstinController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _bankNameController;
  late final TextEditingController _branchController;
  late final TextEditingController _accountController;
  late final TextEditingController _ifscController;
  late final TextEditingController _upiController;
  late final TextEditingController _panController;
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
    _address = _AddressDraft.fromProfile(profile);
    _addressNeedsCompleting = _address.incomplete;
    _gstRegistered = BusinessSettings.isGstRegistered.value;
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
    _address.dispose();
    _gstinController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bankNameController.dispose();
    _branchController.dispose();
    _accountController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    _panController.dispose();
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

  Future<void> _editImage(String type) async {
    final current = switch (type) {
      'logo' => _logoPath,
      'signature' => _signaturePath,
      _ => _qrPath,
    };
    final bytes = await readLocalFile(current);
    if (bytes == null || !mounted) return;
    final path = await editBusinessImage(
      context,
      bytes: bytes,
      kind: _imageKindFor(type),
      businessName: BusinessSettings.profile.value['name'] ?? '',
    );
    if (path == null || !mounted) return;
    setState(() {
      if (type == 'logo') _logoPath = path;
      if (type == 'signature') _signaturePath = path;
      if (type == 'qr') _qrPath = path;
    });
  }

  void _removeImage(String type) => setState(() {
    if (type == 'logo') _logoPath = '';
    if (type == 'signature') _signaturePath = '';
    if (type == 'qr') _qrPath = '';
  });

  Widget _brandingTiles() => Row(
    children: [
      for (final (type, label) in const [
        ('logo', 'Logo'),
        ('signature', 'Signature'),
        ('qr', 'Payment QR'),
      ]) ...[
        if (type != 'logo') const SizedBox(width: 10),
        Expanded(
          child: BusinessImageTile(
            label: label,
            path: switch (type) {
              'logo' => _logoPath,
              'signature' => _signaturePath,
              _ => _qrPath,
            },
            onUpload: () => _pickImage(type),
            onEdit: () => _editImage(type),
            onDraw: type == 'signature' ? _drawSignature : null,
            onRemove: () => _removeImage(type),
          ),
        ),
      ],
    ],
  );

  Future<void> _drawSignature() async {
    final path = await showDialog<String>(
      context: context,
      builder: (_) => const SignaturePadDialog(),
    );
    if (path != null && mounted) setState(() => _signaturePath = path);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check the fields marked in red.')),
      );
      return;
    }
    final registered = _gstRegistered == true;
    await BusinessSettings.setGstRegistered(registered);
    final phone = _normaliseIndianMobile(_phoneController.text);
    _phoneController.value = TextEditingValue(
      text: phone,
      selection: TextSelection.collapsed(offset: phone.length),
    );
    final before = Map<String, String>.from(BusinessSettings.profile.value);
    final after = <String, String>{
      'ownerName': _ownerController.text.trim(),
      'name': _nameController.text.trim(),
      ..._address.toProfile(),
      'gstin': registered ? _gstinController.text.trim().toUpperCase() : '',
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
      'invoicePrefix': _invoicePrefixController.text.trim().toUpperCase(),
      'quotationPrefix': _quotationPrefixController.text.trim().toUpperCase(),
      'invoiceTheme': _invoiceTheme,
    };
    await BusinessSettings.saveProfile(after);
    if (!mounted) return;
    final note = profileChangeShowsOnOldInvoices(before, after)
        ? ' ${oldInvoicesNote(gst: registered)}'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Business profile saved.$note'),
        duration: Duration(seconds: note.isEmpty ? 4 : 8),
      ),
    );
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
    try {
      final response = await http.get(
        Uri.parse('https://ifsc.razorpay.com/$ifsc'),
      );
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
      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
      if (mounted) setState(() => _isLookingUpIfsc = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _simplekAppBar(context, 'Settings'),
      body: ValueListenableBuilder<bool>(
        valueListenable: BusinessSettings.isGstRegistered,
        builder: (context, isGstRegistered, _) {
          return Form(
            key: _formKey,
            child: FormWidth(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const SectionLabel('Invoice colour'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final palette in InvoicePalette.options)
                        _ColourSwatch(
                          palette: palette,
                          selected: _invoiceTheme == palette.id,
                          onTap: () =>
                              setState(() => _invoiceTheme = palette.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${InvoicePalette.resolve(_invoiceTheme).label}. Save the profile to use it on your invoices.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _previewInvoiceTheme,
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('Preview a sample invoice'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SectionLabel('Business details'),
                  const SizedBox(height: 12),
                  _labeledText(
                    _ownerController,
                    'Owner name',
                    required: true,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 100,
                    validator: (value) =>
                        value.trim().isEmpty ? 'Enter the owner name' : null,
                  ),
                  const SizedBox(height: 14),
                  _labeledText(
                    _nameController,
                    'Business name',
                    required: true,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 100,
                    validator: (value) => value.trim().length < 2
                        ? 'Enter the business name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  _labeledText(
                    _phoneController,
                    'Phone',
                    optional: true,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    inputFormatters: [_IndianMobileFormatter()],
                    validator: _mobileError,
                  ),
                  const SizedBox(height: 14),
                  _labeledText(
                    _emailController,
                    'Email',
                    optional: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    maxLength: 254,
                    validator: (value) {
                      final email = value.trim();
                      if (email.isEmpty) return null;
                      return RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(email)
                          ? null
                          : 'Enter a valid email address';
                    },
                  ),
                  const SizedBox(height: 20),
                  SectionLabel('Tax and numbering'),
                  const SizedBox(height: 12),
                  const FieldLabel(
                    'Is your business registered under GST?',
                    required: true,
                  ),
                  YesNoFormField(
                    key: ValueKey('gst-$_gstRegistered'),
                    initialValue: _gstRegistered,
                    yesLabel: 'Yes, registered',
                    noLabel: 'No, not registered',
                    onChanged: (value) =>
                        setState(() => _gstRegistered = value),
                  ),
                  if (_gstRegistered == true) ...[
                    const SizedBox(height: 14),
                    _labeledText(
                      _gstinController,
                      'GSTIN',
                      required: true,
                      hint: '15 characters, e.g. 29ABCDE1234F1Z5',
                      inputFormatters: upperCaseCodeFormatters(15),
                      helper: _gstinState(_gstinController.text) == null
                          ? null
                          : 'State: ${_gstinState(_gstinController.text)}',
                      onChanged: (_) => setState(() {}),
                      validator: (value) => gstinError(value, required: true),
                    ),
                    const SizedBox(height: 14),
                    LabeledField(
                      label: 'GST registration type',
                      required: true,
                      child: DropdownButtonFormField<String>(
                        initialValue: _gstRegistrationType,
                        isExpanded: true,
                        items:
                            const [
                                  'Regular',
                                  'Composition',
                                  'Casual',
                                  'Non-resident',
                                ]
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
                    ),
                  ],
                  const SizedBox(height: 14),
                  _labeledText(
                    _panController,
                    'PAN',
                    optional: true,
                    hint: 'e.g. ABCDE1234F',
                    inputFormatters: upperCaseCodeFormatters(10),
                    validator: (value) =>
                        value.trim().isEmpty ||
                            RegExp(
                              r'^[A-Z]{5}[0-9]{4}[A-Z]$',
                            ).hasMatch(value.trim())
                        ? null
                        : 'Enter a valid PAN, e.g. ABCDE1234F',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _labeledText(
                          _invoicePrefixController,
                          'Invoice prefix',
                          required: true,
                          inputFormatters: upperCaseCodeFormatters(20),
                          validator: (value) => _prefixValidator(value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _labeledText(
                          _quotationPrefixController,
                          'Quotation prefix',
                          required: true,
                          inputFormatters: upperCaseCodeFormatters(20),
                          validator: (value) => _prefixValidator(value),
                        ),
                      ),
                    ],
                  ),
                  _PrefixLengthWarning([
                    _invoicePrefixController,
                    _quotationPrefixController,
                  ]),
                  const SizedBox(height: 20),
                  SectionLabel('Business address'),
                  const SizedBox(height: 8),
                  if (_addressNeedsCompleting)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: SimplekColors.orangeTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: SimplekColors.orangeText,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Choose your district and PIN code to complete your address.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  _BusinessAddressFields(
                    draft: _address,
                    lockedState: _gstRegistered == true
                        ? _gstinState(_gstinController.text)
                        : null,
                  ),
                  const SizedBox(height: 20),
                  SectionLabel('Invoice branding'),
                  const SizedBox(height: 8),
                  _brandingTiles(),
                  const SizedBox(height: 6),
                  Text(
                    'Tap a tile to upload, crop, draw or remove.',
                    style: Theme.of(context).textTheme.bodySmall,
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
                            backgroundColor: Colors.white,
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
                  SectionLabel('Bank details'),
                  const SizedBox(height: 12),
                  _profileField(
                    _ifscController,
                    'IFSC code',
                    inputFormatters: upperCaseCodeFormatters(11),
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ValueListenableBuilder<int?>(
                        valueListenable: BusinessSettings.defaultDueDay,
                        builder: (context, dueDay, _) => LabeledField(
                          label: 'Invoices due after (days)',
                          child: TextFormField(
                            initialValue: (dueDay ?? 7).toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              helperText:
                                  'Prefilled with 7 days. Each invoice can change it.',
                              suffixText: 'days',
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
                          LabeledField(
                            label: 'Quotation terms',
                            child: TextField(
                              controller: _quotationTermsController,
                              minLines: 3,
                              maxLines: 6,
                              decoration: const InputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          LabeledField(
                            label: 'Invoice terms',
                            child: TextField(
                              controller: _invoiceTermsController,
                              minLines: 3,
                              maxLines: 6,
                              decoration: const InputDecoration(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () async {
                              await BusinessSettings.setDocumentTerms(
                                quotation: _quotationTermsController.text
                                    .trim(),
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
                  const SizedBox(height: 28),
                  const SectionLabel('App preferences'),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.palette_outlined,
                              size: 20,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Theme',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<ThemeMode>(
                          valueListenable: BusinessSettings.themeMode,
                          builder: (context, mode, _) => ThemeModeToggle(
                            mode: mode,
                            onChanged: BusinessSettings.setThemeMode,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'These apply to this device only.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        const AppLockSetting(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const VersionLine(),
                  const SizedBox(height: 16),
                ],
              ),
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
  }) => LabeledField(
    label: label,
    child: TextFormField(
      controller: controller,
      minLines: lines,
      maxLines: lines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      validator: validator == null ? null : (value) => validator(value ?? ''),
      decoration: const InputDecoration(),
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
  const PaymentsPage({super.key, this.initialInvoiceId});

  /// Pre-selects this invoice, e.g. from the Invoice view.
  final String? initialInvoiceId;

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
      if (mounted) {
        unawaited(
          _showSyncRejections(
            context,
            'payments',
            (item) =>
                'Payment of ₹${item['p_amount']}'
                '${item['_label'] == null ? '' : ' on invoice ${item['_label']}'}',
          ),
        );
      }
      final rows = await Supabase.instance.client
          .from('invoices')
          .select(
            'id, invoice_number, customer_name, invoice_date, balance_amount',
          )
          .gt('balance_amount', 0)
          .order('invoice_date', ascending: false);
      if (mounted) {
        setState(() {
          _invoices = List<Map<String, dynamic>>.from(rows);
          final initial = widget.initialInvoiceId;
          if (_invoiceId == null &&
              initial != null &&
              _invoices.any(
                (invoice) => invoice['id']?.toString() == initial,
              )) {
            _invoiceId = initial;
          }
        });
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
    // The same request id is used for the online attempt and any offline retry,
    // so a payment whose response was lost cannot be recorded twice.
    final params = <String, dynamic>{
      'p_invoice_id': _invoiceId,
      'p_amount': double.tryParse(_amountController.text.trim()) ?? 0,
      'p_payment_method': _method,
      'p_payment_date': _paymentDate.toIso8601String().substring(0, 10),
      'p_client_request_id': const Uuid().v4(),
    };
    try {
      await Supabase.instance.client.rpc(
        'record_invoice_payment',
        params: params,
      );
      if (!mounted) return;
      _amountController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded successfully')),
      );
      await _load();
    } catch (e) {
      if (_isOfflineError(e)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(_NotSavedOffline.message)),
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

  DateTime _paymentDate = DateTime.now();

  static const _methods = <(String, String, IconData)>[
    ('upi', 'UPI', Icons.qr_code_2),
    ('cash', 'Cash', Icons.currency_rupee),
    ('bank_transfer', 'Bank transfer', Icons.account_balance_outlined),
    ('card', 'Card', Icons.credit_card),
    ('cheque', 'Cheque', Icons.edit_note),
  ];

  Map<String, dynamic>? get _selectedInvoice {
    for (final invoice in _invoices) {
      if (invoice['id']?.toString() == _invoiceId) return invoice;
    }
    return null;
  }

  double get _balance =>
      (_selectedInvoice?['balance_amount'] as num?)?.toDouble() ?? 0;

  void _setAmount(double value) {
    final text = value.toStringAsFixed(2);
    setState(
      () => _amountController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  Future<void> _pickPaymentDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (chosen != null && mounted) setState(() => _paymentDate = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final invoice = _selectedInvoice;
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final after = (_balance - amount).clamp(0, double.infinity).toDouble();
    return Scaffold(
      body: SafeArea(
        child: FormWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PageHeader(title: 'Record payment'),
              Expanded(
                child: _loading
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [SkeletonRows(count: 3)],
                      )
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            if (_invoices.isEmpty)
                              const EmptyState(
                                icon: Icons.check_circle_outline,
                                message:
                                    'Every invoice is paid. Nothing to record.',
                              )
                            else ...[
                              // Navy card for the chosen invoice; tap to change.
                              Pressable(
                                onTap: () => _chooseInvoice(context),
                                color: dark
                                    ? SimplekColors.navyDeep
                                    : SimplekColors.navy,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: SimplekColors.navy2,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.receipt_long,
                                          color: SimplekColors.sky,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              invoice == null
                                                  ? 'Choose an invoice'
                                                  : '${invoice['invoice_number']}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: inter(
                                                16,
                                                FontWeight.w700,
                                                Colors.white,
                                              ),
                                            ),
                                            Text(
                                              invoice == null
                                                  ? '${_invoices.length} unpaid invoice${_invoices.length == 1 ? '' : 's'}'
                                                  : '${invoice['customer_name']} · ${screenDate(parseStoredDate(invoice['invoice_date']))}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: inter(
                                                13,
                                                FontWeight.w500,
                                                SimplekColors.sky,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (invoice != null)
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Balance due',
                                              style: inter(
                                                12,
                                                FontWeight.w500,
                                                const Color(0xCCFFFFFF),
                                              ),
                                            ),
                                            Text(
                                              rupees(_balance),
                                              style: inter(
                                                15,
                                                FontWeight.w700,
                                                Colors.white,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        const Icon(
                                          Icons.expand_more,
                                          color: Colors.white,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              FormField<String>(
                                key: ValueKey(_invoiceId),
                                initialValue: _invoiceId,
                                validator: (_) => _invoiceId == null
                                    ? 'Choose the invoice this payment is for'
                                    : null,
                                builder: (field) => field.hasError
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          field.errorText!,
                                          style: TextStyle(
                                            color: theme.colorScheme.error,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              const SizedBox(height: 16),
                              const FieldLabel(
                                'Amount received',
                                required: true,
                              ),
                              TextFormField(
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() {}),
                                style: inter(
                                  30,
                                  FontWeight.w700,
                                  theme.colorScheme.onSurface,
                                ),
                                decoration: InputDecoration(
                                  prefixText: '₹ ',
                                  prefixStyle: inter(
                                    24,
                                    FontWeight.w600,
                                    theme.colorScheme.onSurfaceVariant,
                                  ),
                                  hintText: '0.00',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                validator: (value) {
                                  final paid = double.tryParse(value ?? '');
                                  if (paid == null || paid <= 0) {
                                    return 'Enter the amount received';
                                  }
                                  return null;
                                },
                              ),
                              if (invoice != null) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ActionChip(
                                      label: const Text('Full amount'),
                                      onPressed: () => _setAmount(_balance),
                                    ),
                                    ActionChip(
                                      label: const Text('Half'),
                                      onPressed: () => _setAmount(
                                        (_balance * 50).round() / 100,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              const FieldLabel('Paid by', required: true),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = (constraints.maxWidth - 16) / 3;
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final method in _methods)
                                        SizedBox(
                                          width: width,
                                          child: _MethodTile(
                                            icon: method.$3,
                                            label: method.$2,
                                            selected: _method == method.$1,
                                            onTap: () => setState(
                                              () => _method = method.$1,
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              const FieldLabel('Payment date', required: true),
                              Pressable(
                                onTap: _pickPaymentDate,
                                borderRadius: BorderRadius.circular(12),
                                color: theme.inputDecorationTheme.fillColor,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    suffixIcon: Icon(Icons.expand_more),
                                  ),
                                  child: Text(
                                    screenDate(_paymentDate),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              if (invoice != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: dark
                                        ? SimplekColors.navyDeep
                                        : SimplekColors.skyTint,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Balance after this payment',
                                          style: inter(
                                            14,
                                            FontWeight.w600,
                                            dark
                                                ? SimplekColors.sky
                                                : SimplekColors.skyText,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        rupees(after),
                                        style: inter(
                                          15,
                                          FontWeight.w700,
                                          theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (amount > _balance)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'This is more than the balance due.',
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _invoices.isEmpty
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: SafeArea(
                top: false,
                child: FormWidth(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SimplekColors.navy,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Saving…' : 'Record payment'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _chooseInvoice(BuildContext context) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Choose an invoice',
                style: Theme.of(sheet).textTheme.headlineSmall,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  RowGroup(
                    children: [
                      for (final invoice in _invoices)
                        ListRowTile(
                          leading: InitialTile(
                            invoice['customer_name']?.toString() ?? '',
                          ),
                          title: invoice['customer_name']?.toString() ?? '',
                          subtitle:
                              '${invoice['invoice_number']} · ${screenDate(parseStoredDate(invoice['invoice_date']))}',
                          trailingTop: Text(
                            rupees(
                              (invoice['balance_amount'] as num?)?.toDouble() ??
                                  0,
                            ),
                            style: inter(
                              14.5,
                              FontWeight.w700,
                              Theme.of(sheet).colorScheme.onSurface,
                            ),
                          ),
                          onTap: () => Navigator.of(
                            sheet,
                          ).pop(invoice['id']?.toString()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) setState(() => _invoiceId = chosen);
  }
}

/// One payment-method tile; the chosen one is orange-tinted.
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        color: selected
            ? (theme.brightness == Brightness.dark
                  ? SimplekColors.navyDeep
                  : SimplekColors.orangeTint)
            : theme.colorScheme.surface,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? SimplekColors.orange
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected
                    ? SimplekColors.orangeText
                    : theme.colorScheme.onSurface,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: inter(
                    13.5,
                    FontWeight.w600,
                    theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  String _money(double amount) => rupees(amount);

  /// GST reports and tax columns only for a GST-registered business
  /// (CR-25 change 6).
  bool get _gst => BusinessSettings.isGstRegistered.value;
  String get _exportName => _gst ? 'gstr1' : 'sales';

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
    if (_gst) invoice['customer_gstin'],
    if (_gst) invoice['place_of_supply'],
    invoice['status'],
    if (_gst) _amount(invoice['subtotal']),
    if (_gst) _amount(invoice['cgst_amount']),
    if (_gst) _amount(invoice['sgst_amount']),
    if (_gst) _amount(invoice['igst_amount']),
    if (_gst) _amount(invoice['tax_amount']),
    _amount(invoice['total_amount']),
    _amount(invoice['paid_amount']),
    _amount(invoice['balance_amount']),
  ];

  List<String> get _exportHeaders => [
    'Invoice Number',
    'Invoice Date',
    'Customer',
    if (_gst) 'Customer GSTIN',
    if (_gst) 'Place of Supply',
    'Status',
    if (_gst) 'Taxable Value',
    if (_gst) 'CGST',
    if (_gst) 'SGST',
    if (_gst) 'IGST',
    if (_gst) 'Total Tax',
    'Invoice Total',
    'Paid',
    'Outstanding',
  ];

  Future<void> _shareExport(
    List<int> bytes, {
    required String filename,
    required String mimeType,
  }) async {
    final file = kIsWeb
        ? XFile.fromData(
            Uint8List.fromList(bytes),
            name: filename,
            mimeType: mimeType,
          )
        : XFile(await writeTempFile(filename, bytes), mimeType: mimeType);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Simplek report export',
        text: 'Simplek report for the selected period.',
        files: [file],
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
      filename: 'simplek_${_exportName}_$_periodSlug.csv',
      mimeType: 'text/csv',
    );
  }

  Future<void> _exportExcel() async {
    final workbook = xlsx.Excel.createExcel();
    final sheet = workbook[_gst ? 'GSTR-1' : 'Sales'];
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
      filename: 'simplek_${_exportName}_$_periodSlug.xlsx',
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
${_gst ? '<PARTYGSTIN>${_xml(invoice['customer_gstin'])}</PARTYGSTIN>\n<PLACEOFSUPPLY>${_xml(invoice['place_of_supply'])}</PLACEOFSUPPLY>\n' : ''}<AMOUNT>${_amount(invoice['total_amount']).toStringAsFixed(2)}</AMOUNT>
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
            _gst ? 'Simplek GSTR-1 Report' : 'Simplek Sales Report',
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
            headers: _exportHeaders.take(_exportHeaders.length - 2).toList(),
            data: _exportInvoices
                .map(
                  (invoice) => _exportRow(
                    invoice,
                  ).take(_exportHeaders.length - 2).toList(),
                )
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
      filename: 'simplek_${_exportName}_$_periodSlug.pdf',
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
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget exportButton(String format, String label, {bool strong = false}) {
      final child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download_outlined, size: 20),
          const SizedBox(width: 6),
          Flexible(child: Text(label, maxLines: 1)),
        ],
      );
      return Expanded(
        child: strong
            ? ElevatedButton(onPressed: () => _export(format), child: child)
            : OutlinedButton(onPressed: () => _export(format), child: child),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(
              title: 'Reports',
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Export report',
                  onSelected: _export,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                    PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
                    PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                    PopupMenuItem(
                      value: 'xml',
                      child: Text('Export TallyPrime XML'),
                    ),
                  ],
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: const Icon(Icons.download_outlined),
                  ),
                ),
              ],
            ),
            Expanded(
              child: _loading && _invoices.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [SkeletonRows(count: 4)],
                    )
                  : _error != null
                  ? _loadError('Unable to load reports:\n$_error', _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Pressable(
                                  onTap: _selectReportPeriod,
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    height: 48,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: dark
                                            ? SimplekColors.darkLine
                                            : SimplekColors.skyLine,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_month_outlined,
                                          color: dark
                                              ? SimplekColors.sky
                                              : SimplekColors.skyText,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _reportPeriod == null
                                                ? 'All invoice dates'
                                                : '${screenDate(_reportPeriod!.start)} – ${screenDate(_reportPeriod!.end)}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: inter(
                                              15,
                                              FontWeight.w600,
                                              theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        const Icon(Icons.expand_more),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (_reportPeriod != null) ...[
                                const SizedBox(width: 8),
                                SquareIconButton(
                                  icon: Icons.close,
                                  tooltip: 'Show all dates',
                                  onPressed: () =>
                                      setState(() => _reportPeriod = null),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Sales',
                                  value: _money(sales),
                                  filled: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatTile(
                                  label: 'Collected',
                                  value: _money(collected),
                                  tone: TileTone.sky,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'Outstanding',
                                  value: _money(outstanding),
                                  tone: TileTone.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatTile(
                                  label: 'Invoices',
                                  value: '${active.length}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _WeeklySalesChart(invoices: active),
                          if (_gst) ...[
                            const SizedBox(height: 12),
                            SectionCard(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  IconTile(
                                    invalidInvoices.isEmpty
                                        ? Icons.check
                                        : Icons.warning_amber_rounded,
                                    tone: invalidInvoices.isEmpty
                                        ? TileTone.sky
                                        : TileTone.orange,
                                    size: 42,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          invalidInvoices.isEmpty
                                              ? 'GSTR-1 is ready'
                                              : 'GSTR-1 needs attention',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        Text(
                                          'B2B ${b2bInvoices.length} invoices · B2C ${b2cInvoices.length} invoices · '
                                          '${invalidInvoices.isEmpty ? 'no errors' : '${invalidInvoices.length} to fix'}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              exportButton('pdf', 'PDF'),
                              const SizedBox(width: 8),
                              exportButton('xlsx', 'Excel'),
                              const SizedBox(width: 8),
                              exportButton('xml', 'Tally', strong: true),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Payment status',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _statusMetric(
                                      'Paid',
                                      paid,
                                      Colors.green,
                                    ),
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
                          if (_gst) ...[
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
                                      entry.invoice['invoice_number']
                                              ?.toString() ??
                                          'Invoice',
                                    ),
                                    subtitle: Text(entry.issues.join(' • ')),
                                  ),
                                ),
                              ),
                            ],
                            Card(
                              child: ExpansionTile(
                                title: Text(
                                  'B2B supplies (${b2bInvoices.length})',
                                ),
                                subtitle: const Text(
                                  'Registered customers with GSTIN',
                                ),
                                children: b2bInvoices.isEmpty
                                    ? const [
                                        ListTile(
                                          title: Text(
                                            'No B2B invoices in this period.',
                                          ),
                                        ),
                                      ]
                                    : b2bInvoices
                                          .map(
                                            (invoice) => ListTile(
                                              title: Text(
                                                invoice['invoice_number']
                                                        ?.toString() ??
                                                    'Invoice',
                                              ),
                                              subtitle: Text(
                                                '${invoice['customer_gstin']} • ${invoice['customer_name']}',
                                              ),
                                              trailing: Text(
                                                _money(
                                                  _amount(
                                                    invoice['total_amount'],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                              ),
                            ),
                            Card(
                              child: ExpansionTile(
                                title: Text(
                                  'B2C supplies (${b2cInvoices.length})',
                                ),
                                subtitle: const Text('Consumers without GSTIN'),
                                children: b2cInvoices.isEmpty
                                    ? const [
                                        ListTile(
                                          title: Text(
                                            'No B2C invoices in this period.',
                                          ),
                                        ),
                                      ]
                                    : b2cInvoices
                                          .map(
                                            (invoice) => ListTile(
                                              title: Text(
                                                invoice['invoice_number']
                                                        ?.toString() ??
                                                    'Invoice',
                                              ),
                                              subtitle: Text(
                                                invoice['customer_name']
                                                        ?.toString() ??
                                                    'Customer',
                                              ),
                                              trailing: Text(
                                                _money(
                                                  _amount(
                                                    invoice['total_amount'],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                              ),
                            ),
                          ],
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
                                child: Text(
                                  'No invoice data is available yet.',
                                ),
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
                                          invoice['invoice_number']
                                                  ?.toString() ??
                                              'Invoice',
                                        ),
                                        subtitle: Text(
                                          '${invoice['customer_name'] ?? ''} • ${(invoice['status'] ?? 'draft').toString().toUpperCase()}',
                                        ),
                                        trailing: Text(
                                          _money(
                                            _amount(invoice['total_amount']),
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          if (_gst) ...[
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
                          ],
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
                                  [
                                    '${entry.value['count']!.toInt()} invoices',
                                    if (_gst)
                                      'Tax ${_money(entry.value['tax']!)}',
                                    'Due ${_money(entry.value['outstanding']!)}',
                                  ].join(' • '),
                                ),
                                trailing: Text(
                                  _money(entry.value['sales']!),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
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
                                  [
                                    'Qty ${plainQuantity(entry.value['quantity']!)}',
                                    if (_gst)
                                      'Taxable ${_money(entry.value['taxable']!)}',
                                    if (_gst)
                                      'Tax ${_money(entry.value['tax']!)}',
                                  ].join(' • '),
                                ),
                                trailing: Text(
                                  _money(entry.value['sales']!),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      StatTile(label: label, value: value, tone: TileTone.sky);
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
    LiveSync.changes.addListener(_load);
  }

  @override
  void dispose() {
    LiveSync.changes.removeListener(_load);
    super.dispose();
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
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session has expired. Please sign in again.'),
        ),
      );
      return;
    }
    try {
      final invoice = Map<String, dynamic>.from(
        await Supabase.instance.client.rpc(
              'convert_quotation_to_invoice',
              params: {
                'p_quotation_id': quotation['id'],
                'p_invoice_date': DateTime.now().toIso8601String().substring(
                  0,
                  10,
                ),
                'p_number_prefix':
                    BusinessSettings.profile.value['invoicePrefix'] ?? 'INV',
              },
            )
            as Map,
      );
      final invoiceNumber = invoice['invoice_number'];
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

  String _filter = 'All';
  bool _searching = false;
  final _search = TextEditingController();

  String _statusOf(Map<String, dynamic> quote) =>
      quote['converted_invoice_id'] == null
      ? quote['status']?.toString() ?? 'draft'
      : 'converted';

  Widget _quoteRow(Map<String, dynamic> quote) {
    final readOnly = BusinessAccess.readOnly;
    final validUntil = parseStoredDate(quote['valid_until']);
    return _DocumentRow(
      title: quote['customer_name']?.toString() ?? '',
      number: [
        quote['quotation_number']?.toString() ?? 'Quotation',
        if (validUntil != null) 'till ${screenDate(validUntil)}',
      ].join(' · '),
      date: null,
      amount: (quote['total_amount'] as num?)?.toDouble() ?? 0,
      status: _statusOf(quote),
      onTap: () => _openPreview(quote),
      menu: PopupMenuButton<String>(
        tooltip: 'Quotation actions',
        onSelected: (value) {
          if (value == 'preview') {
            _openPreview(quote);
          } else if (value == 'edit') {
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
          const PopupMenuItem(value: 'preview', child: Text('Preview')),
          if (!readOnly) ...const [
            PopupMenuItem(value: 'edit', child: Text('Edit quotation')),
            PopupMenuItem(
              value: 'duplicate',
              child: Text('Duplicate quotation'),
            ),
            PopupMenuDivider(),
            PopupMenuItem(value: 'sent', child: Text('Mark as sent')),
            PopupMenuItem(value: 'accepted', child: Text('Mark as accepted')),
            PopupMenuItem(value: 'rejected', child: Text('Mark as rejected')),
            PopupMenuItem(value: 'expired', child: Text('Mark as expired')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'convert', child: Text('Convert to invoice')),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final shown = _quotations.where((quote) {
      final status = _statusOf(quote);
      if (_filter != 'All' && status != _filter.toLowerCase()) return false;
      return query.isEmpty ||
          '${quote['quotation_number'] ?? ''} ${quote['customer_name'] ?? ''}'
              .toLowerCase()
              .contains(query);
    }).toList();
    final accepted = _quotations
        .where((quote) => _statusOf(quote) == 'accepted')
        .toList();
    return Scaffold(
      floatingActionButton: BusinessAccess.readOnly
          ? null
          : CreateButton(label: 'New quotation', onPressed: _newQuotation),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(
              title: 'Quotations',
              actions: [
                SquareIconButton(
                  icon: _searching ? Icons.close : Icons.search,
                  tooltip: _searching ? 'Close search' : 'Search quotations',
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _search.clear();
                  }),
                ),
              ],
            ),
            Expanded(
              child: _loading && _quotations.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [SkeletonRows()],
                    )
                  : _error != null
                  ? _loadError('Quotations are not ready yet.\n$_error', _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        children: [
                          if (_searching) ...[
                            _ListSearch(
                              controller: _search,
                              hint: 'Search quotations, customers',
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 10),
                          ],
                          _FilterChips(
                            options: const [
                              'All',
                              'Draft',
                              'Sent',
                              'Accepted',
                              'Expired',
                            ],
                            selected: _filter,
                            onSelected: (value) =>
                                setState(() => _filter = value),
                          ),
                          const SizedBox(height: 12),
                          if (accepted.isNotEmpty &&
                              !BusinessAccess.readOnly) ...[
                            Pressable(
                              onTap: () => setState(() => _filter = 'Accepted'),
                              color: SimplekColors.skyTint,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: SimplekColors.skyLine,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.check,
                                        color: SimplekColors.skyText,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${accepted.length} accepted quotation${accepted.length == 1 ? '' : 's'}',
                                            style: inter(
                                              15,
                                              FontWeight.w700,
                                              SimplekColors.navy,
                                            ),
                                          ),
                                          Text(
                                            'Turn them into invoices in one tap',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: inter(
                                              13,
                                              FontWeight.w500,
                                              SimplekColors.skyText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: SimplekColors.skyText,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_quotations.isEmpty)
                            EmptyState(
                              icon: Icons.description_outlined,
                              message:
                                  'No quotations yet. Send prices before you bill.',
                              actionLabel: BusinessAccess.readOnly
                                  ? null
                                  : 'Create quotation',
                              onAction: _newQuotation,
                            )
                          else if (shown.isEmpty)
                            const EmptyState(
                              icon: Icons.search_off,
                              message: 'No quotations match this filter.',
                            )
                          else
                            RowGroup(
                              children: [for (final q in shown) _quoteRow(q)],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
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
  final _numberController = TextEditingController();
  String? _numberError;
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _placeOfSupplyController = TextEditingController(
    text: BusinessSettings.profile.value['businessState'] ?? '',
  );
  final _termsController = TextEditingController(
    text: BusinessSettings.quotationTerms.value,
  );
  final _descriptionController = TextEditingController();
  final List<InvoiceLineItem> _items = [
    InvoiceLineItem(gstApplies: BusinessSettings.isGstRegistered.value),
  ];

  /// GST applies to this document: always for a registered business, and for
  /// an existing document saved with tax, so that tax is kept on edit.
  bool _usesGst = BusinessSettings.isGstRegistered.value;
  InvoiceLineItem _newItem() => InvoiceLineItem(gstApplies: _usesGst);
  late DateTime _quotationDate;
  late DateTime _validUntil;
  bool _saving = false;
  bool _loadingExisting = false;
  String _customerSubtitle = '';

  bool get _isEditing => widget.quotation != null && !widget.duplicate;

  @override
  void initState() {
    super.initState();
    _quotationDate = DateTime.now();
    if (_isEditing) {
      _numberController.text =
          widget.quotation!['quotation_number']?.toString() ?? '';
    }
    _validUntil = DateTime.now().add(const Duration(days: 30));
    if (widget.quotation != null) _loadExistingQuotation();
  }

  Future<void> _pickCustomer() async {
    final result = await _showRecordPicker(context, _customerPickerSource());
    if (result == null || !mounted) return;
    if (result.record != null) {
      _selectQuotationCustomer(result.record!);
    } else {
      setState(() {
        _customerController.text = result.freeText!;
        _customerSubtitle = 'Not saved in Customers';
      });
    }
  }

  void _selectQuotationCustomer(Map<String, dynamic> selected) {
    setState(() {
      _customerController.text = selected['name']?.toString() ?? '';
      _customerSubtitle = _customerDetails(selected);
      if (_usesGst) {
        _placeOfSupplyController.text = placeOfSupplyFor(
          customerGstin: selected['gstin']?.toString() ?? '',
          customerState: selected['state']?.toString() ?? '',
          businessState: BusinessSettings.profile.value['businessState'] ?? '',
        );
      }
    });
  }

  Future<void> _pickProduct(InvoiceLineItem item) async {
    final result = await _showRecordPicker(
      context,
      _productPickerSource(),
      initialQuery: item.productId == null ? item.productController.text : '',
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.record != null) {
        final selected = result.record!;
        item.selectProduct(selected);
        item.rateController.text = selected['selling_price']?.toString() ?? '';
        item.gstRateController.text = selected['gst_rate']?.toString() ?? '0';
      } else {
        item.useFreeText(result.freeText!);
      }
    });
    item.quantityFocus.requestFocus();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _customerController.dispose();
    _placeOfSupplyController.dispose();
    _termsController.dispose();
    _descriptionController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.taxableAmount);
  double get _tax => _items.fold(0, (sum, item) => sum + item.taxAmount);
  double get _exactTotal => _subtotal + _tax;

  /// Rounded to the nearest rupee; the difference shows as Round off.
  double get _total => roundToRupee(_exactTotal);
  bool get _isIntraState =>
      _placeOfSupplyController.text.trim().isEmpty ||
      sameGstState(
        _placeOfSupplyController.text,
        BusinessSettings.profile.value['businessState'] ?? '',
      );
  double get _cgst => _isIntraState ? _tax / 2 : 0;
  double get _sgst => _isIntraState ? _tax / 2 : 0;
  double get _igst => _isIntraState ? 0 : _tax;
  String _dbDate(DateTime value) => value.toIso8601String().substring(0, 10);

  Future<void> _loadExistingQuotation() async {
    setState(() => _loadingExisting = true);
    try {
      final quotation = widget.quotation!;
      _customerController.text = quotation['customer_name']?.toString() ?? '';
      _termsController.text = quotation['terms']?.toString() ?? '';
      _descriptionController.text = quotation['description']?.toString() ?? '';
      _placeOfSupplyController.text =
          quotation['place_of_supply']?.toString() ??
          BusinessSettings.profile.value['businessState'] ??
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
            'product_id, item_name, quantity, uqc_code, unit_price, gst_rate, products(hsn_sac_code)',
          )
          .eq('quotation_id', quotation['id']);
      if (!widget.duplicate) {
        _usesGst =
            BusinessSettings.isGstRegistered.value ||
            List<Map<String, dynamic>>.from(
              rows,
            ).any((row) => _asDouble(row['gst_rate']) > 0);
      }
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final item = _newItem();
        item.productId = row['product_id']?.toString();
        item.readProduct(row['products'] as Map<String, dynamic>?);
        item.uqcCode = row['uqc_code']?.toString();
        item.productController.text = row['item_name']?.toString() ?? '';
        item.quantityController.text = _asDouble(row['quantity']).toString();
        item.rateController.text = _asDouble(row['unit_price']).toString();
        item.gstRateController.text = _asDouble(row['gst_rate']).toString();
        _items.add(item);
      }
      if (_items.isEmpty) _items.add(_newItem());
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
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _numberError = null;
    });
    try {
      final data = {
        'customer_name': _customerController.text.trim(),
        'quotation_date': _dbDate(_quotationDate),
        'valid_until': _dbDate(_validUntil),
        'subtotal': _subtotal,
        'tax_amount': _tax,
        'total_amount': _total,
        'terms': _termsController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'place_of_supply': _usesGst ? _placeOfSupplyController.text.trim() : '',
        'tax_type': _tax == 0 ? 'none' : (_isIntraState ? 'cgst_sgst' : 'igst'),
        'cgst_amount': _cgst,
        'sgst_amount': _sgst,
        'igst_amount': _igst,
      };
      late final String number;
      late final Map<String, dynamic> quote;
      if (_isEditing) {
        number = _numberController.text.trim().isNotEmpty
            ? _numberController.text.trim().toUpperCase()
            : widget.quotation!['quotation_number'].toString();
        quote = await Supabase.instance.client
            .from('quotations')
            .update({...data, 'quotation_number': number})
            .eq('id', widget.quotation!['id'])
            .select('*')
            .single();
        await Supabase.instance.client
            .from('quotation_items')
            .delete()
            .eq('quotation_id', quote['id']);
      } else {
        number = _numberController.text.trim().isNotEmpty
            ? _numberController.text.trim().toUpperCase()
            : await Supabase.instance.client.rpc(
                    'next_quotation_number',
                    params: {
                      'p_prefix':
                          BusinessSettings.profile.value['quotationPrefix'] ??
                          'QTN',
                      'p_quotation_date': _dbDate(_quotationDate),
                      'p_financial_year': '',
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
          SnackBar(
            content: Text(
              error is PostgrestException && error.code == '23505'
                  ? 'This quotation number is already used. Please use a different number.'
                  : 'Unable to save quotation: $error',
            ),
            backgroundColor:
                error is PostgrestException && error.code == '23505'
                ? Colors.red.shade800
                : null,
          ),
        );
        if (error is PostgrestException && error.code == '23505') {
          setState(
            () => _numberError =
                'This quotation number is already used. Please use a different number.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _simplekAppBar(
      context,
      _isEditing ? 'Edit quotation' : 'New quotation',
      subtitle: _isEditing
          ? _numberController.text
          : 'Number set automatically unless you type one',
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
              padding: _formPadding(context),
              children: [
                LabeledField(
                  label: 'Quotation number',
                  optional: true,
                  child: TextFormField(
                    controller: _numberController,
                    enabled: !_saving,
                    validator: validateDocumentNumber,
                    decoration: InputDecoration(
                      helperText:
                          'Leave blank for automatic numbering for your business.',
                      errorText: _numberError,
                    ),
                    onChanged: (_) => setState(() => _numberError = null),
                  ),
                ),
                const SizedBox(height: 12),
                _PickedRecordField(
                  label: 'Customer',
                  placeholder: 'Choose a customer',
                  title: _customerController.text,
                  subtitle: _customerSubtitle,
                  icon: Icons.person_outline,
                  emptyError: 'Choose a customer',
                  onPick: _pickCustomer,
                ),
                if (_usesGst) ...[
                  const SizedBox(height: 12),
                  SearchableStateField(
                    label: 'Place of supply',
                    required: true,
                    value: _placeOfSupplyController.text,
                    onChanged: (state) => setState(
                      () => _placeOfSupplyController.text = state ?? '',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Place of supply is required'
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Quotation date',
                        date: _quotationDate,
                        onTap: () => _pickDate(false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Valid until',
                        date: _validUntil,
                        onTap: () => _pickDate(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Items',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _items.add(_newItem())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...List.generate(_items.length, _itemRow),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _items.add(_newItem())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add another item'),
                ),
                const SizedBox(height: 16),
                _DescriptionField(controller: _descriptionController),
                const SizedBox(height: 16),
                _TotalsCard(
                  taxable: _subtotal,
                  cgst: _cgst,
                  sgst: _sgst,
                  igst: _igst,
                  usesGst: _usesGst,
                  intraState: _isIntraState,
                  exactTotal: _exactTotal,
                  total: _total,
                  totalLabel: 'Quotation total',
                ),
                const SizedBox(height: 16),
                DesignSettings.modern.value
                    ? EditableTerms(controller: _termsController)
                    : LabeledField(
                        label: 'Terms and conditions',
                        child: TextField(
                          controller: _termsController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(),
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
    return _LineItemCard(
      item: item,
      usesGst: _usesGst,
      onPick: () => _pickProduct(item),
      onChanged: () => setState(() {}),
      onRemove: _items.length > 1
          ? () => setState(() {
              final removed = _items.removeAt(index);
              removed.dispose();
            })
          : null,
    );
  }
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
  String _customerAddress = '';
  String _customerGstin = '';

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
            .select(
              'item_name, quantity, uqc_code, unit_price, gst_rate, '
              'taxable_amount, tax_amount, total_amount, '
              'products(hsn_sac_code)',
            )
            .eq('quotation_id', widget.quotation['id']),
        Supabase.instance.client
            .from('customers')
            .select('phone, email, address, gstin')
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
            _customerAddress = contacts.first['address']?.toString() ?? '';
            _customerGstin = contacts.first['gstin']?.toString() ?? '';
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

  Future<Uint8List> _pdf(PdfPageFormat format) {
    final quotation = widget.quotation;
    final items = [
      for (final row in _items)
        PdfLineItem(
          description: row['item_name']?.toString() ?? '',
          hsn: (row['products'] as Map?)?['hsn_sac_code']?.toString() ?? '',
          quantity: _amount(row['quantity']),
          unit: row['uqc_code']?.toString() ?? '',
          rate: _amount(row['unit_price']),
          gstRate: _amount(row['gst_rate']),
          taxable: row['taxable_amount'] == null
              ? _amount(row['quantity']) * _amount(row['unit_price'])
              : _amount(row['taxable_amount']),
          tax: _amount(row['tax_amount']),
        ),
    ];
    final hasTax = items.any((item) => item.tax > 0);
    final gst = BusinessSettings.isGstRegistered.value || hasTax;
    return buildDocumentPdf(
      PdfDocumentData(
        kind: PdfDocumentKind.quotation,
        number: quotation['quotation_number']?.toString() ?? '',
        date: parseStoredDate(quotation['quotation_date']) ?? DateTime.now(),
        secondDate: parseStoredDate(quotation['valid_until']),
        placeOfSupply: quotation['place_of_supply']?.toString() ?? '',
        customerName: quotation['customer_name']?.toString() ?? '',
        customerAddress: _customerAddress,
        customerGstin: gst ? _customerGstin : '',
        customerPhone: _customerPhone,
        items: items,
        total: _amount(quotation['total_amount']),
        terms: quotation['terms']?.toString() ?? '',
        description: quotation['description']?.toString() ?? '',
        gstDocument: gst,
      ),
      BusinessSettings.profile.value,
      format: format,
    );
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
    LiveSync.changes.addListener(_loadInvoices);
  }

  @override
  void dispose() {
    LiveSync.changes.removeListener(_loadInvoices);
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final syncedDrafts = await OfflineStore.flushInvoiceDrafts();
      if (mounted) {
        unawaited(
          _showSyncRejections(
            context,
            'invoice_drafts',
            (item) =>
                'Invoice for ${(item['header'] as Map?)?['customer_name'] ?? 'a customer'}',
          ),
        );
      }
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

  Future<void> _openInvoice(Map<String, dynamic> invoice) async {
    final id = invoice['id']?.toString();
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InvoiceViewPage(invoiceId: id)),
    );
    if (mounted) await _loadInvoices();
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
    if (!await confirmEditInvoice(context, invoice) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InvoiceBuilderPage(sourceInvoice: invoice, editExisting: true),
      ),
    );
    await _loadInvoices();
  }

  Future<void> _deleteInvoice(Map<String, dynamic> invoice) async {
    final id = invoice['id']?.toString();
    if (id == null) return;
    await deleteInvoiceWithUndo(
      context,
      invoiceId: id,
      number: invoice['invoice_number']?.toString() ?? '',
      onChanged: () {
        if (mounted) _loadInvoices();
      },
    );
  }

  final _search = TextEditingController();
  String _filter = 'All';

  bool _matches(Map<String, dynamic> invoice) {
    final status = invoice['status']?.toString() ?? '';
    final balance = (invoice['balance_amount'] as num?)?.toDouble() ?? 0;
    final keep = switch (_filter) {
      'Unpaid' => balance > 0 && status != 'cancelled',
      'Partial' => status == 'partial',
      'Paid' => status == 'paid',
      _ => true,
    };
    if (!keep) return false;
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${invoice['invoice_number'] ?? ''} ${invoice['customer_name'] ?? ''} ${invoice['customer_gstin'] ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  Widget _row(Map<String, dynamic> invoice) {
    final status = invoice['status']?.toString() ?? 'draft';
    final readOnly = BusinessAccess.readOnly;
    return _DocumentRow(
      title: invoice['customer_name']?.toString() ?? '',
      number: invoice['invoice_number']?.toString() ?? 'Invoice',
      date: parseStoredDate(invoice['invoice_date']),
      amount: (invoice['total_amount'] as num?)?.toDouble() ?? 0,
      status: status,
      onTap: () => _openInvoice(invoice),
      menu: PopupMenuButton<String>(
        tooltip: 'Invoice actions',
        onSelected: (value) {
          if (value == 'preview') {
            _openInvoice(invoice);
          } else if (value == 'edit') {
            _editInvoice(invoice);
          } else if (value == 'duplicate') {
            _duplicateInvoice(invoice);
          } else if (value == 'delete') {
            _deleteInvoice(invoice);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'preview', child: Text('Preview')),
          if (!readOnly) ...const [
            PopupMenuItem(value: 'edit', child: Text('Edit invoice')),
            PopupMenuItem(value: 'duplicate', child: Text('Duplicate invoice')),
            PopupMenuItem(value: 'delete', child: Text('Delete invoice')),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final shown = _invoices.where(_matches).toList();
    final toCollect = _invoices
        .where((invoice) => invoice['status']?.toString() != 'cancelled')
        .fold<double>(
          0,
          (sum, invoice) =>
              sum + ((invoice['balance_amount'] as num?)?.toDouble() ?? 0),
        );
    final paidThisMonth = _invoices
        .where((invoice) {
          final date = parseStoredDate(invoice['invoice_date']);
          return date != null &&
              date.year == now.year &&
              date.month == now.month;
        })
        .fold<double>(
          0,
          (sum, invoice) =>
              sum + ((invoice['paid_amount'] as num?)?.toDouble() ?? 0),
        );
    return Scaffold(
      floatingActionButton: BusinessAccess.readOnly
          ? null
          : CreateButton(label: 'Create', onPressed: _newInvoice),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PageHeader(title: 'Invoices'),
            Expanded(
              child: _isLoading && _invoices.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [SkeletonRows()],
                    )
                  : _error != null
                  ? _loadError(_error!, _loadInvoices)
                  : RefreshIndicator(
                      onRefresh: _loadInvoices,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        children: [
                          _ListSearch(
                            controller: _search,
                            hint: 'Search invoices, customers',
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          _FilterChips(
                            options: const ['All', 'Unpaid', 'Partial', 'Paid'],
                            selected: _filter,
                            onSelected: (value) =>
                                setState(() => _filter = value),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: StatTile(
                                  label: 'To collect',
                                  value: rupees(toCollect),
                                  tone: TileTone.orange,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatTile(
                                  label: 'Paid this month',
                                  value: rupees(paidThisMonth),
                                  tone: TileTone.sky,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (_invoices.isEmpty)
                            EmptyState(
                              icon: Icons.receipt_long_outlined,
                              message:
                                  'No invoices yet. Create your first invoice.',
                              actionLabel: BusinessAccess.readOnly
                                  ? null
                                  : 'Create invoice',
                              onAction: _newInvoice,
                            )
                          else if (shown.isEmpty)
                            const EmptyState(
                              icon: Icons.search_off,
                              message:
                                  'No invoices match this search or filter.',
                            )
                          else
                            ..._monthGroups(shown, 'invoice_date', _row),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class InvoiceLineItem {
  InvoiceLineItem({this.gstApplies = true})
    : productController = TextEditingController(),
      quantityController = TextEditingController(text: '1'),
      rateController = TextEditingController(),
      gstRateController = TextEditingController(text: '0');

  final TextEditingController productController;
  final TextEditingController quantityController;
  final TextEditingController rateController;
  final TextEditingController gstRateController;
  final quantityFocus = FocusNode();
  String? productId;
  String? uqcCode;

  /// False for a business not registered under GST: no tax is charged.
  bool gstApplies;
  String hsn = '';

  double get quantity => double.tryParse(quantityController.text.trim()) ?? 0;
  double get rate => double.tryParse(rateController.text.trim()) ?? 0;
  double get gstRate =>
      gstApplies ? double.tryParse(gstRateController.text.trim()) ?? 0 : 0;
  double get taxableAmount => quantity * rate;
  double get taxAmount => taxableAmount * gstRate / 100;
  double get total => taxableAmount + taxAmount;

  /// Fills HSN/SAC from a product row, or a row that embeds one.
  void readProduct(Map<String, dynamic>? product) {
    if (product == null) return;
    hsn = product['hsn_sac_code']?.toString() ?? '';
  }

  /// Links this line to a saved product and fills its details.
  void selectProduct(Map<String, dynamic> product) {
    productId = product['id']?.toString();
    uqcCode = product['uqc_code']?.toString();
    readProduct(product);
    productController.text = product['name']?.toString() ?? '';
  }

  /// A name used on this document only: no saved product, no HSN/SAC.
  void useFreeText(String name) {
    productId = null;
    uqcCode = null;
    hsn = '';
    productController.text = name;
  }

  /// "SAC 998314 · GST 18% · ₹1,500.00" for the selected-item card.
  String get summary {
    if (productController.text.trim().isEmpty) return '';
    if (productId == null) return 'Not a saved item';
    return [
      if (gstApplies && hsn.isNotEmpty) 'HSN/SAC $hsn',
      if (gstApplies) 'GST ${percent(gstRate)}',
      rupees(rate),
    ].join(' · ');
  }

  PdfLineItem toPdf() => PdfLineItem(
    description: productController.text.trim(),
    hsn: hsn,
    quantity: quantity,
    unit: uqcCode ?? '',
    rate: rate,
    gstRate: gstRate,
    taxable: taxableAmount,
    tax: taxAmount,
  );

  void dispose() {
    quantityFocus.dispose();
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
  /// Lets a retry of this save find the invoice instead of creating another.
  final String _newInvoiceId = const Uuid().v4();

  final _numberController = TextEditingController();
  String? _numberError;
  String _customerAddress = '';
  String _customerSubtitle = '';
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _customerGstinController = TextEditingController();
  final _placeOfSupplyController = TextEditingController(
    text: BusinessSettings.profile.value['businessState'] ?? '',
  );
  final _termsController = TextEditingController(
    text: BusinessSettings.invoiceTerms.value,
  );
  final _descriptionController = TextEditingController();
  late DateTime _invoiceDate;
  DateTime? _dueDate;
  final List<InvoiceLineItem> _items = [
    InvoiceLineItem(gstApplies: BusinessSettings.isGstRegistered.value),
  ];

  /// GST applies to this document: always for a registered business, and for
  /// an existing document saved with tax, so that tax is kept on edit.
  bool _usesGst = BusinessSettings.isGstRegistered.value;
  InvoiceLineItem _newItem() => InvoiceLineItem(gstApplies: _usesGst);
  bool _isSavingDraft = false;
  bool _loadingSource = false;

  bool get _isEditing => widget.sourceInvoice != null && widget.editExisting;

  @override
  void initState() {
    super.initState();
    _invoiceDate = DateTime.now();
    if (_isEditing) {
      _numberController.text =
          widget.sourceInvoice!['invoice_number']?.toString() ?? '';
    }
    _dueDate = _defaultDueDate(
      _invoiceDate,
      BusinessSettings.defaultDueDay.value,
    );
    if (widget.sourceInvoice != null) _loadSourceInvoice();
  }

  Future<void> _pickCustomer() async {
    final result = await _showRecordPicker(context, _customerPickerSource());
    if (result == null || !mounted) return;
    if (result.record != null) {
      _selectInvoiceCustomer(result.record!);
    } else {
      setState(() {
        _customerController.text = result.freeText!;
        _customerSubtitle = 'Not saved in Customers';
        _customerAddress = '';
        _customerPhoneController.clear();
        _customerEmailController.clear();
        _customerGstinController.clear();
      });
    }
  }

  void _selectInvoiceCustomer(Map<String, dynamic> selected) {
    setState(() {
      _customerAddress = selected['address']?.toString() ?? '';
      _customerController.text = selected['name']?.toString() ?? '';
      _customerSubtitle = _customerDetails(selected);
      _customerPhoneController.text = selected['phone']?.toString() ?? '';
      _customerEmailController.text = selected['email']?.toString() ?? '';
      _customerGstinController.text = _usesGst
          ? selected['gstin']?.toString() ?? ''
          : '';
      if (_usesGst) {
        _placeOfSupplyController.text = placeOfSupplyFor(
          customerGstin: _customerGstinController.text,
          customerState: selected['state']?.toString() ?? '',
          businessState: BusinessSettings.profile.value['businessState'] ?? '',
        );
      }
    });
  }

  Future<void> _pickProduct(InvoiceLineItem item) async {
    final result = await _showRecordPicker(
      context,
      _productPickerSource(),
      initialQuery: item.productId == null ? item.productController.text : '',
    );
    if (result == null || !mounted) return;
    if (result.record != null) {
      await _selectInvoiceProduct(item, result.record!);
    } else {
      setState(() => item.useFreeText(result.freeText!));
    }
    if (mounted) item.quantityFocus.requestFocus();
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
      item.selectProduct(selected);
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
          .select('phone, email, address')
          .eq('name', _customerController.text)
          .limit(2);
      if (!mounted) return;
      if (contacts.length == 1) {
        _customerAddress = contacts.first['address']?.toString() ?? '';
        _customerPhoneController.text =
            contacts.first['phone']?.toString() ?? '';
        _customerEmailController.text =
            contacts.first['email']?.toString() ?? '';
      }
      _customerSubtitle = _customerPhoneController.text;
      _customerGstinController.text =
          source['customer_gstin']?.toString() ?? '';
      _placeOfSupplyController.text =
          source['place_of_supply']?.toString() ??
          BusinessSettings.profile.value['businessState'] ??
          '';
      _termsController.text =
          source['terms']?.toString() ?? BusinessSettings.invoiceTerms.value;
      _descriptionController.text = source['description']?.toString() ?? '';
      if (_isEditing) {
        _invoiceDate =
            DateTime.tryParse(source['invoice_date']?.toString() ?? '') ??
            _invoiceDate;
        _dueDate = DateTime.tryParse(source['due_date']?.toString() ?? '');
      }
      final rows = await Supabase.instance.client
          .from('invoice_items')
          .select(
            'product_id, item_name, quantity, uqc_code, unit_price, gst_rate, products(hsn_sac_code)',
          )
          .eq('invoice_id', source['id']);
      if (_isEditing) {
        _usesGst =
            BusinessSettings.isGstRegistered.value ||
            List<Map<String, dynamic>>.from(
              rows,
            ).any((row) => (num.tryParse('${row['gst_rate']}') ?? 0) > 0);
      }
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final item = _newItem();
        item.productId = row['product_id']?.toString();
        item.readProduct(row['products'] as Map<String, dynamic>?);
        item.uqcCode = row['uqc_code']?.toString();
        item.productController.text = row['item_name']?.toString() ?? '';
        item.quantityController.text = row['quantity']?.toString() ?? '1';
        item.rateController.text = row['unit_price']?.toString() ?? '';
        item.gstRateController.text = row['gst_rate']?.toString() ?? '0';
        _items.add(item);
      }
      if (_items.isEmpty) _items.add(_newItem());
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
    _numberController.dispose();
    _customerController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _customerGstinController.dispose();
    _placeOfSupplyController.dispose();
    _termsController.dispose();
    _descriptionController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.taxableAmount);
  double get _taxTotal => _items.fold(0, (sum, item) => sum + item.taxAmount);
  double get _exactTotal => _subtotal + _taxTotal;

  /// Rounded to the nearest rupee; the difference shows as Round off.
  double get _grandTotal => roundToRupee(_exactTotal);

  /// CGST + SGST when the place of supply is the business's state, compared
  /// by GST state code (BUILD-STANDARDS 8.1); IGST otherwise.
  bool get _isIntraState =>
      _placeOfSupplyController.text.trim().isEmpty ||
      sameGstState(
        _placeOfSupplyController.text,
        BusinessSettings.profile.value['businessState'] ?? '',
      );
  double get _cgstTotal => _isIntraState ? _taxTotal / 2 : 0;
  double get _sgstTotal => _isIntraState ? _taxTotal / 2 : 0;
  double get _igstTotal => _isIntraState ? 0 : _taxTotal;

  String _dateForDatabase(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// The fields of this invoice the server accepts. Status, balance and paid
  /// amount are always decided by the server.
  Map<String, dynamic> _invoiceHeaderPayload() => {
    'invoice_number': _numberController.text.trim().toUpperCase(),
    'customer_name': _customerController.text.trim(),
    'customer_gstin': _usesGst
        ? _customerGstinController.text.trim().toUpperCase()
        : '',
    'invoice_date': _dateForDatabase(_invoiceDate),
    'due_date': _dueDate == null ? null : _dateForDatabase(_dueDate!),
    'subtotal': _subtotal,
    'tax_amount': _taxTotal,
    'total_amount': _grandTotal,
    'terms': _termsController.text.trim(),
    'place_of_supply': _usesGst ? _placeOfSupplyController.text.trim() : '',
    'tax_type': _taxTotal == 0
        ? 'none'
        : (_isIntraState ? 'cgst_sgst' : 'igst'),
    'cgst_amount': _cgstTotal,
    'sgst_amount': _sgstTotal,
    'igst_amount': _igstTotal,
  };

  List<Map<String, dynamic>> _invoiceItemsPayload() => _items
      .map(
        (item) => <String, dynamic>{
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
      .toList();

  Future<void> _saveDraft({required bool openPreview}) async {
    if (_isSavingDraft) return;
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
    setState(() {
      _isSavingDraft = true;
      _numberError = null;
    });
    var saved = false;
    String savedNumber = 'Pending sync';
    try {
      final invoice = Map<String, dynamic>.from(
        await Supabase.instance.client.rpc(
              'save_invoice',
              params: {
                'p_invoice_id': _isEditing
                    ? widget.sourceInvoice!['id']
                    : _newInvoiceId,
                'p_header': _invoiceHeaderPayload(),
                'p_items': _invoiceItemsPayload(),
                'p_is_edit': _isEditing,
                'p_number_prefix':
                    BusinessSettings.profile.value['invoicePrefix'] ?? 'INV',
                'p_description': _descriptionController.text.trim(),
              },
            )
            as Map,
      );
      final invoiceNumber = invoice['invoice_number'] as String;
      invoiceChanges.value++;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Invoice $invoiceNumber updated successfully'
                : 'Invoice $invoiceNumber saved successfully',
          ),
        ),
      );
      saved = true;
      savedNumber = invoiceNumber;
    } catch (e) {
      if (_isOfflineError(e)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No internet connection. The invoice is not saved yet. '
                'Keep this screen open, connect, and save again.',
              ),
            ),
          );
        }
      } else if (mounted) {
        if (e is PostgrestException && e.code == '23505') {
          setState(
            () => _numberError =
                'This invoice number is already used. Please use a different number.',
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_numberError ?? 'Unable to save invoice: $e'),
            backgroundColor: _numberError == null ? null : Colors.red.shade800,
          ),
        );
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
            total: _grandTotal,
            gstDocument: _usesGst,
            customerName: _customerController.text.trim(),
            customerAddress: _customerAddress,
            customerGstin: _usesGst ? _customerGstinController.text.trim() : '',
            customerPhone: _customerPhoneController.text.trim(),
            customerEmail: _customerEmailController.text.trim(),
            placeOfSupply: _usesGst ? _placeOfSupplyController.text.trim() : '',
            invoiceDate: _invoiceDate,
            dueDate: _dueDate,
            terms: _termsController.text.trim(),
            description: _descriptionController.text.trim(),
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
    if (saved != null && mounted) _selectInvoiceCustomer(saved);
  }

  void _addItem() => setState(() => _items.add(_newItem()));

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
      appBar: _simplekAppBar(
        context,
        _isEditing
            ? 'Edit invoice'
            : widget.sourceInvoice == null
            ? 'New invoice'
            : 'Duplicate invoice',
        subtitle: _isEditing
            ? _numberController.text
            : 'Number set automatically unless you type one',
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
                padding: _formPadding(context),
                children: [
                  LabeledField(
                    label: 'Invoice number',
                    optional: true,
                    child: TextFormField(
                      controller: _numberController,
                      enabled: !_isSavingDraft,
                      validator: validateDocumentNumber,
                      decoration: InputDecoration(
                        helperText:
                            'Leave blank for automatic numbering for your business.',
                        errorText: _numberError,
                      ),
                      onChanged: (_) => setState(() => _numberError = null),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PickedRecordField(
                    label: 'Customer',
                    placeholder: 'Choose a customer',
                    title: _customerController.text,
                    subtitle: _customerSubtitle,
                    icon: Icons.person_outline,
                    emptyError: 'Choose a customer',
                    onPick: _pickCustomer,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _addCustomer,
                      icon: const Icon(Icons.person_add_outlined),
                      label: const Text('Add new customer'),
                    ),
                  ),
                  if (_usesGst) ...[
                    const SizedBox(height: 12),
                    _labeledText(
                      _customerGstinController,
                      'Customer GSTIN',
                      optional: true,
                      hint: '15 characters',
                      helper: 'Needed for a B2B sale.',
                      inputFormatters: upperCaseCodeFormatters(15),
                      validator: (value) => gstinError(value),
                      onChanged: (value) {
                        final state = _gstinState(value);
                        if (state != null) {
                          setState(() => _placeOfSupplyController.text = state);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SearchableStateField(
                      label: 'Place of supply',
                      required: true,
                      value: _placeOfSupplyController.text,
                      helperText:
                          'Compared with your business state to choose CGST + SGST or IGST.',
                      onChanged: (state) => setState(
                        () => _placeOfSupplyController.text = state ?? '',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Place of supply is required'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: LabeledField(
                          label: 'WhatsApp number',
                          child: TextFormField(
                            controller: _customerPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LabeledField(
                          label: 'Email',
                          child: TextFormField(
                            controller: _customerEmailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DateField(
                          label: 'Invoice date',
                          date: _invoiceDate,
                          onTap: () => _pickDate(isDueDate: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DateField(
                          label: 'Due date',
                          date: _dueDate,
                          emptyText: 'No due date',
                          onTap: () => _pickDate(isDueDate: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Items',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add),
                        label: const Text('Add item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...List.generate(_items.length, _buildItemRow),
                  OutlinedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add another item'),
                  ),
                  const SizedBox(height: 16),
                  _DescriptionField(controller: _descriptionController),
                  const SizedBox(height: 16),
                  _TotalsCard(
                    taxable: _subtotal,
                    cgst: _cgstTotal,
                    sgst: _sgstTotal,
                    igst: _igstTotal,
                    usesGst: _usesGst,
                    intraState: _isIntraState,
                    exactTotal: _exactTotal,
                    total: _grandTotal,
                    totalLabel: 'Total payable',
                  ),
                  const SizedBox(height: 16),
                  DesignSettings.modern.value
                      ? EditableTerms(controller: _termsController)
                      : LabeledField(
                          label: 'Terms and conditions',
                          child: TextField(
                            controller: _termsController,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              helperText:
                                  'Prefilled from Business Settings. Editable for this invoice.',
                            ),
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
    return _LineItemCard(
      item: item,
      usesGst: _usesGst,
      onPick: () => _pickProduct(item),
      onChanged: () => setState(() {}),
      onRemove: _items.length > 1 ? () => _removeItem(index) : null,
    );
  }
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

/// What the Invoice view screen shows and can do for a saved invoice.
class InvoiceViewActions {
  const InvoiceViewActions({
    required this.status,
    required this.total,
    required this.paid,
    this.dueDate,
    this.onEdit,
    this.onDuplicate,
    this.onRecordPayment,
    this.onDelete,
  });
  final String status;
  final double total;
  final double paid;
  final DateTime? dueDate;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDuplicate;
  final Future<void> Function()? onRecordPayment;
  final Future<void> Function()? onDelete;
  double get balance => total - paid < 0 ? 0 : total - paid;
}

/// Opens a saved invoice by id: its PDF, payment summary and every action.
class InvoiceViewPage extends StatefulWidget {
  const InvoiceViewPage({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  State<InvoiceViewPage> createState() => _InvoiceViewPageState();
}

class _InvoiceViewPageState extends State<InvoiceViewPage> {
  Map<String, dynamic>? _invoice;
  List<InvoiceLineItem> _items = [];
  Map<String, dynamic> _contact = const {};
  String? _error;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  static double _num(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  Future<void> _load() async {
    final client = Supabase.instance.client;
    try {
      final invoice = await client
          .from('invoices')
          .select()
          .eq('id', widget.invoiceId)
          .single();
      final results = await Future.wait([
        client
            .from('invoice_items')
            .select(
              'product_id, item_name, quantity, uqc_code, unit_price, '
              'gst_rate, products(hsn_sac_code)',
            )
            .eq('invoice_id', widget.invoiceId),
        client
            .from('customers')
            .select('phone, email, address')
            .eq('name', invoice['customer_name'] ?? '')
            .limit(1),
      ]);
      final items = [
        for (final row in List<Map<String, dynamic>>.from(results[0] as List))
          InvoiceLineItem()
            ..productId = row['product_id']?.toString()
            ..uqcCode = row['uqc_code']?.toString()
            ..readProduct(row['products'] as Map<String, dynamic>?)
            ..productController.text = row['item_name']?.toString() ?? ''
            ..quantityController.text = _num(row['quantity']).toString()
            ..rateController.text = _num(row['unit_price']).toString()
            ..gstRateController.text = _num(row['gst_rate']).toString(),
      ];
      final contacts = List<Map<String, dynamic>>.from(results[1] as List);
      if (!mounted) {
        for (final item in items) {
          item.dispose();
        }
        return;
      }
      final old = _items;
      setState(() {
        _invoice = invoice;
        _items = items;
        _contact = contacts.isEmpty ? const {} : contacts.first;
        _error = null;
        _version++;
      });
      for (final item in old) {
        item.dispose();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _connectionMessage(
            error,
            fallback: 'Unable to open this invoice.',
          ),
        );
      }
    }
  }

  Future<void> _then(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    invoiceChanges.value++;
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    if (invoice == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    final total = _num(invoice['total_amount']);
    final paid = _num(invoice['paid_amount']);
    final readOnly = BusinessAccess.readOnly;
    final gst =
        BusinessSettings.isGstRegistered.value ||
        (invoice['tax_type']?.toString() ?? 'none') != 'none' ||
        _num(invoice['tax_amount']) > 0;
    return InvoicePreviewPage(
      key: ValueKey(_version),
      invoiceNumber: invoice['invoice_number']?.toString() ?? 'Invoice',
      customerName: invoice['customer_name']?.toString() ?? '',
      customerAddress: _contact['address']?.toString() ?? '',
      customerGstin: invoice['customer_gstin']?.toString() ?? '',
      customerPhone: _contact['phone']?.toString() ?? '',
      customerEmail: _contact['email']?.toString() ?? '',
      placeOfSupply: invoice['place_of_supply']?.toString() ?? '',
      invoiceDate: parseStoredDate(invoice['invoice_date']) ?? DateTime.now(),
      dueDate: parseStoredDate(invoice['due_date']),
      terms: invoice['terms']?.toString() ?? '',
      description: invoice['description']?.toString() ?? '',
      items: _items,
      balanceDue: _num(invoice['balance_amount']),
      total: total,
      paid: paid,
      gstDocument: gst,
      view: InvoiceViewActions(
        status: invoice['status']?.toString() ?? 'sent',
        total: total,
        paid: paid,
        dueDate: parseStoredDate(invoice['due_date']),
        onEdit: readOnly
            ? null
            : () async {
                if (!await confirmEditInvoice(context, invoice) || !mounted) {
                  return;
                }
                await _then(
                  InvoiceBuilderPage(
                    sourceInvoice: invoice,
                    editExisting: true,
                  ),
                );
              },
        onDelete: readOnly
            ? null
            : () async {
                final deleted = await deleteInvoiceWithUndo(
                  context,
                  invoiceId: widget.invoiceId,
                  number: invoice['invoice_number']?.toString() ?? '',
                );
                if (deleted && context.mounted) Navigator.of(context).pop();
              },
        onDuplicate: readOnly
            ? null
            : () => _then(InvoiceBuilderPage(sourceInvoice: invoice)),
        onRecordPayment: readOnly || _num(invoice['balance_amount']) <= 0
            ? null
            : () => _then(PaymentsPage(initialInvoiceId: widget.invoiceId)),
      ),
    );
  }
}

/// One row in the invoice or quotation list, in the Home "Recent" style.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.number,
    required this.date,
    required this.amount,
    required this.status,
    required this.onTap,
    required this.menu,
  });
  final String title;
  final String number;
  final DateTime? date;
  final double amount;
  final String status;
  final VoidCallback onTap;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = title.trim();
    return ListRowTile(
      leading: InitialTile(name),
      title: name.isEmpty ? 'Customer' : name,
      subtitle: [number, if (date != null) screenDate(date)].join(' · '),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                rupees(amount),
                maxLines: 1,
                style: inter(
                  15.5,
                  FontWeight.w700,
                  theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              StatusChip(status),
            ],
          ),
          menu,
        ],
      ),
    );
  }
}

/// Rows grouped under month headings ("NOVEMBER 2026"), newest first.
List<Widget> _monthGroups(
  List<Map<String, dynamic>> rows,
  String dateField,
  Widget Function(Map<String, dynamic> row) build,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final date = parseStoredDate(row[dateField]);
    groups
        .putIfAbsent(date == null ? 'NO DATE' : monthHeading(date), () => [])
        .add(row);
  }
  return [
    for (final entry in groups.entries) ...[
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: SectionLabel(entry.key, muted: true),
      ),
      RowGroup(children: [for (final row in entry.value) build(row)]),
      const SizedBox(height: 8),
    ],
  ];
}

/// The "All / Unpaid / Partial / Paid" style filter chips.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final option in options) ...[
          ChoiceChip(
            label: Text(option),
            selected: option == selected,
            showCheckmark: false,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              onSelected(option);
            },
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

/// The search box at the top of a list.
class _ListSearch extends StatelessWidget {
  const _ListSearch({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    style: const TextStyle(fontSize: 16),
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.clear),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
    ),
  );
}

/// A list page's title row: Fraunces title and square action buttons.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, this.actions = const []});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
    child: Row(
      children: [
        if (Navigator.of(context).canPop()) ...[
          SquareIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        for (final action in actions) ...[const SizedBox(width: 8), action],
      ],
    ),
  );
}

/// The message shown when a list can't load, with Try again.
Widget _loadError(String message, VoidCallback retry) => Padding(
  padding: const EdgeInsets.all(16),
  child: SectionCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        const IconTile(Icons.cloud_off_outlined, size: 52),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: retry, child: const Text('Try again')),
      ],
    ),
  ),
);

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
    this.customerAddress = '',
    this.customerGstin = '',
    this.total,
    this.paid,
    this.gstDocument,
    this.view,
    this.description = '',
  });

  final String customerName;
  final String description;
  final String customerAddress;
  final String customerGstin;
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

  /// The saved total. Defaults to the items' total rounded to the rupee.
  final double? total;

  /// Amount already received. Defaults to total minus [balanceDue].
  final double? paid;

  /// Whether this is a GST document. Defaults to the business setting, or
  /// true when any item carries tax.
  final bool? gstDocument;

  /// Set for a saved invoice opened from a list: shows its status, payment
  /// summary and actions instead of the after-save buttons.
  final InvoiceViewActions? view;

  @override
  State<InvoicePreviewPage> createState() => _InvoicePreviewPageState();
}

class InvoicePdfRenderer {
  InvoicePdfRenderer(this.widget);
  final InvoicePreviewPage widget;
  Map<String, String> get _profile =>
      widget.previewProfile ?? BusinessSettings.profile.value;

  Future<Uint8List> build(PdfPageFormat format) {
    final items = [for (final item in widget.items) item.toPdf()];
    final exact = items.fold<double>(0, (sum, item) => sum + item.amount);
    final total = widget.total ?? roundToRupee(exact);
    final paid = widget.paid ?? (total - widget.balanceDue).clamp(0, total);
    final gst =
        widget.gstDocument ??
        (BusinessSettings.isGstRegistered.value ||
            items.any((item) => item.tax > 0));
    return buildDocumentPdf(
      PdfDocumentData(
        kind: PdfDocumentKind.invoice,
        number: widget.invoiceNumber,
        date: widget.invoiceDate,
        secondDate: widget.dueDate,
        placeOfSupply: widget.placeOfSupply,
        customerName: widget.customerName,
        customerAddress: widget.customerAddress,
        customerGstin: gst ? widget.customerGstin : '',
        customerPhone: widget.customerPhone,
        items: items,
        total: total,
        paid: paid.toDouble(),
        terms: widget.terms,
        description: widget.description,
        gstDocument: gst,
        sample: widget.previewProfile != null,
      ),
      _profile,
      format: format,
    );
  }
}

class _InvoicePreviewPageState extends State<InvoicePreviewPage> {
  bool _sharing = false;
  String get _invoiceNumber => widget.invoiceNumber;
  String get _message =>
      'Hello ${widget.customerName}, here is the invoice ($_invoiceNumber) from '
      '${BusinessSettings.profile.value['name'] ?? ''}. Please make the payment of '
      'rupees ${indianNumber(widget.balanceDue)} to the payment details as mentioned '
      'in the invoice. If you need any further assistance, please contact us '
      '${BusinessSettings.profile.value['phone'] ?? ''} or '
      '${BusinessSettings.profile.value['email'] ?? ''}. Thank you';

  String get _emailMessage =>
      'Hello ${widget.customerName}. Please find attached invoice, $_invoiceNumber '
      'for your reference. Kindly make the payment to the bank details mentioned '
      'in the invoice. If you have any queries, please feel free to contact us.';

  Future<void> _sendAttachment(String target, String recipient) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _generatePdf(PdfPageFormat.a4);
      await sharePdfAttachment(
        bytes: bytes,
        number: _invoiceNumber,
        subject: 'Invoice $_invoiceNumber',
        target: target,
        recipient: recipient,
        body: target == 'email' ? _emailMessage : _message,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to attach invoice: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) =>
      InvoicePdfRenderer(widget).build(format);

  Future<void> _sharePdf() async {
    await _sendAttachment('share', '');
  }

  Future<void> _openWhatsApp() async {
    final phone = whatsappNumber(widget.customerPhone);
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid customer WhatsApp number, including country code for international numbers.',
          ),
        ),
      );
      return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WhatsApp: ${widget.customerName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('+$phone'),
                const SizedBox(height: 12),
                const Text(
                  'Try opening the client with the PDF attached. Some WhatsApp versions instead ask you to select the client. The message is also copied so you can paste it if WhatsApp omits the caption. You still choose when to send.',
                ),
                const SizedBox(height: 12),
                SelectableText(_message),
                ListTile(
                  leading: const Icon(Icons.chat_outlined),
                  title: const Text('Open client chat with message'),
                  onTap: () => Navigator.pop(context, 'chat'),
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Open client with PDF'),
                  onTap: () => Navigator.pop(context, 'pdf'),
                ),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Choose WhatsApp contact for PDF'),
                  onTap: () => Navigator.pop(context, 'picker'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy message'),
                  onTap: () => Navigator.pop(context, 'copy'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'pdf' || action == 'picker') {
        await Clipboard.setData(ClipboardData(text: _message));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Message copied. Select the client in WhatsApp and paste it if the caption is empty.',
            ),
          ),
        );
        await _sendAttachment(
          action == 'pdf' ? 'whatsapp' : 'whatsapp_picker',
          phone,
        );
      } else if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: _message));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Message copied')));
        }
      } else {
        final uri = whatsappChatUri(phone, _message);
        if (isAndroidDevice) {
          await const MethodChannel(
            'simplek/document_share',
          ).invokeMethod('openChat', {'url': uri.toString()});
        } else if (!await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        )) {
          throw StateError('WhatsApp could not be opened.');
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open WhatsApp: $error')),
        );
      }
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

  Future<void> _print() async {
    try {
      await Printing.layoutPdf(onLayout: _generatePdf);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to print: $error')));
      }
    }
  }

  Future<void> _download() async {
    try {
      await Printing.sharePdf(
        bytes: await _generatePdf(PdfPageFormat.a4),
        filename: documentPdfFilename('invoice', _invoiceNumber),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to download: $error')));
      }
    }
  }

  Widget _summary(InvoiceViewActions view) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget cell(
      String label,
      String value, {
      Color? background,
      Color? color,
    }) => Expanded(
      child: Container(
        color: background,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: inter(
                13,
                FontWeight.w500,
                color ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: inter(
                  16.5,
                  FontWeight.w700,
                  theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            padding: EdgeInsets.zero,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cell('Total', rupees(view.total)),
                  VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  cell(
                    'Paid',
                    rupees(view.paid),
                    color: dark ? SimplekColors.sky : SimplekColors.skyText,
                  ),
                  cell(
                    'Balance due',
                    rupees(view.balance),
                    background: view.balance > 0
                        ? (dark
                              ? SimplekColors.navyDeep
                              : SimplekColors.orangeTint)
                        : null,
                    color: view.balance > 0
                        ? (dark
                              ? SimplekColors.orange
                              : SimplekColors.orangeText)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          if (widget.description.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.description.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewBody(InvoiceViewActions view) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _summary(view),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SectionCard(
            padding: EdgeInsets.zero,
            child: PdfPreview(
              build: _generatePdf,
              useActions: false,
              canDebug: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              scrollViewDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
              ),
              pdfPreviewPageDecoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Color(0x1A0B1A33), blurRadius: 6)],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Text(
          view.dueDate == null
              ? 'Tap the page to zoom'
              : 'Due on ${screenDate(view.dueDate)} · tap the page to zoom',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );

  /// WhatsApp, Share PDF, Print and Email, then Record payment.
  Widget _viewActions(InvoiceViewActions view) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget tile(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      Color? background,
      Color? foreground,
      Color? border,
    }) => Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          borderRadius: BorderRadius.circular(12),
          color: background ?? theme.colorScheme.surface,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: border ?? theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: foreground ?? theme.colorScheme.onSurface,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: inter(
                      13.5,
                      FontWeight.w600,
                      foreground ?? theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  tile(
                    Icons.chat_outlined,
                    'WhatsApp',
                    _sharing ? null : _openWhatsApp,
                    background: dark
                        ? SimplekColors.navyDeep
                        : SimplekColors.skyTint,
                    border: dark ? null : SimplekColors.skyLine,
                  ),
                  const SizedBox(width: 8),
                  tile(
                    Icons.share_outlined,
                    'Share PDF',
                    _sharing ? null : _sharePdf,
                    background: dark
                        ? SimplekColors.navyDeep
                        : SimplekColors.navy,
                    foreground: Colors.white,
                    border: Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  tile(Icons.print_outlined, 'Print', _print),
                  const SizedBox(width: 8),
                  tile(
                    Icons.mail_outline,
                    'Email',
                    _sharing ? null : _openEmail,
                  ),
                ],
              ),
              if (view.onRecordPayment != null && view.balance > 0) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => view.onRecordPayment!(),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Record payment'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (view != null) {
      final theme = Theme.of(context);
      return Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Row(
                  children: [
                    SquareIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            _invoiceNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: inter(
                              20,
                              FontWeight.w700,
                              theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(view.status),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      onSelected: (value) async {
                        switch (value) {
                          case 'edit':
                            await view.onEdit?.call();
                          case 'duplicate':
                            await view.onDuplicate?.call();
                          case 'payment':
                            await view.onRecordPayment?.call();
                          case 'download':
                            await _download();
                          case 'delete':
                            await view.onDelete?.call();
                        }
                      },
                      itemBuilder: (_) => [
                        if (view.onEdit != null)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit invoice'),
                          ),
                        if (view.onDuplicate != null)
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate invoice'),
                          ),
                        if (view.onRecordPayment != null)
                          const PopupMenuItem(
                            value: 'payment',
                            child: Text('Record payment'),
                          ),
                        if (kIsWeb)
                          const PopupMenuItem(
                            value: 'download',
                            child: Text('Download PDF'),
                          ),
                        if (view.onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete invoice'),
                          ),
                      ],
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: const Icon(Icons.more_horiz),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _viewBody(view)),
            ],
          ),
        ),
        bottomNavigationBar: _viewActions(view),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.previewProfile != null
              ? 'Sample invoice format'
              : 'Invoice Preview',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              widget.previewProfile != null ? 'Close' : 'Save & Close',
            ),
          ),
        ],
      ),
      body: widget.previewProfile != null
          ? PdfPreview(
              build: _generatePdf,
              canChangePageFormat: false,
              canChangeOrientation: false,
              allowPrinting: false,
              allowSharing: false,
            )
          : _SavedDocumentPreview(
              buildPdf: _generatePdf,
              addNewLabel: 'Save & Add New Invoice',
              onAddNew: () => Navigator.of(context).pop(true),
            ),
      bottomNavigationBar: widget.previewProfile != null
          ? null
          : DocumentShareBar(
              onWhatsApp: _sharing ? null : _openWhatsApp,
              onEmail: _sharing ? null : _openEmail,
              onShare: _sharing ? null : _sharePdf,
            ),
    );
  }
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
    LiveSync.changes.addListener(_loadProducts);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_applySearch)
      ..dispose();
    LiveSync.changes.removeListener(_loadProducts);
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await OfflineStore.flush('products', 'products');
      if (mounted) {
        unawaited(
          _showSyncRejections(
            context,
            'products',
            (item) => 'Product or service "${item['name'] ?? ''}"',
          ),
        );
      }
      final rows = await Supabase.instance.client
          .from('products')
          .select(
            'id, name, product_type, selling_price, uqc_code, hsn_sac_id, hsn_sac_code, hsn_sac_description, gst_rate, is_active',
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
    final services = _products
        .where((product) => product['product_type'] == 'service')
        .length;

    return Scaffold(
      floatingActionButton: BusinessAccess.readOnly
          ? null
          : CreateButton(label: 'Add item', onPressed: _addProduct),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PageHeader(title: _showingCached ? 'Items (offline)' : 'Items'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _ListSearch(
                controller: _searchController,
                hint: 'Search name, type or unit',
                onChanged: (_) {},
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Products',
                      value: '${_products.length - services}',
                      tone: TileTone.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Services',
                      value: '$services',
                      tone: TileTone.sky,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(visibleProducts)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> visibleProducts) {
    if (_isLoading && _products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: const [SkeletonRows()],
      );
    }
    if (_errorMessage != null) return _loadError(_errorMessage!, _loadProducts);
    final hasSearch = _searchController.text.trim().isNotEmpty;
    final gst = BusinessSettings.isGstRegistered.value;
    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          if (visibleProducts.isEmpty)
            EmptyState(
              icon: Icons.inventory_2_outlined,
              message: hasSearch
                  ? 'No items match this search.'
                  : 'No products or services yet. Add one to use it in invoices.',
              actionLabel: hasSearch || BusinessAccess.readOnly
                  ? null
                  : 'Add item',
              onAction: _addProduct,
            )
          else
            RowGroup(
              children: [
                for (final product in visibleProducts)
                  Builder(
                    builder: (context) {
                      final service = product['product_type'] == 'service';
                      final price = product['selling_price'];
                      final details = [
                        service ? 'Service' : 'Product',
                        if (gst && product['gst_rate'] != null)
                          'GST ${percent(num.tryParse('${product['gst_rate']}') ?? 0)}',
                        if (gst && product['hsn_sac_code'] != null)
                          '${service ? 'SAC' : 'HSN'} ${product['hsn_sac_code']}',
                        if (product['uqc_code'] != null)
                          product['uqc_code'].toString(),
                      ].join(' · ');
                      return ListRowTile(
                        leading: IconTile(
                          service
                              ? Icons.sell_outlined
                              : Icons.inventory_2_outlined,
                          tone: service ? TileTone.sky : TileTone.orange,
                          size: 42,
                        ),
                        title: product['name']?.toString() ?? 'Unnamed item',
                        subtitle: details,
                        onTap: BusinessAccess.readOnly
                            ? null
                            : () => _editProduct(product),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (price != null)
                              Text(
                                rupees(num.tryParse('$price') ?? 0),
                                maxLines: 1,
                                style: inter(
                                  15,
                                  FontWeight.w700,
                                  Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            if (!BusinessAccess.readOnly)
                              PopupMenuButton<String>(
                                tooltip: 'Item actions',
                                onSelected: (value) => value == 'edit'
                                    ? _editProduct(product)
                                    : _removeCatalogEntry(
                                        context,
                                        'products',
                                        product,
                                        _loadProducts,
                                      ),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit item'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete item'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
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
      late final Map<String, dynamic> saved;
      try {
        // Return the saved row, with its id, so a document can link to it.
        saved = Map<String, dynamic>.from(
          _isEditing
              ? await Supabase.instance.client
                    .from('products')
                    .update(product)
                    .eq('id', widget.product!['id'])
                    .select()
                    .single()
              : await Supabase.instance.client
                    .from('products')
                    .insert(product)
                    .select()
                    .single(),
        );
      } catch (error) {
        if (error is PostgrestException || error is AuthException) rethrow;
        if (_isEditing) rethrow;
        throw const _NotSavedOffline();
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final note =
          _isEditing && productChangeShowsOnOldInvoices(widget.product, saved)
          ? ' ${oldInvoicesNote(gst: isGstRegistered)}'
          : '';
      Navigator.of(context).pop(widget.returnRecord ? saved : true);
      invoiceChanges.value++;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${_isProduct ? 'Product' : 'Service'} saved successfully.$note',
          ),
          duration: Duration(seconds: note.isEmpty ? 4 : 8),
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
                LabeledField(
                  label: 'Item Type',
                  child: DropdownButtonFormField<String>(
                    initialValue: _itemType,
                    decoration: const InputDecoration(),
                    items: const [
                      DropdownMenuItem(
                        value: 'product',
                        child: Text('Product'),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: Text('Service'),
                      ),
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
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: _isProduct ? 'Product Name' : 'Service Name',
                  child: TextFormField(
                    controller: _nameController,
                    enabled: !_isSaving,
                    decoration: InputDecoration(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? '${_isProduct ? 'Product' : 'Service'} name is required'
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Selling price',
                  child: TextFormField(
                    controller: _sellingPriceController,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(prefixText: '₹ '),
                    validator: (value) =>
                        _amountValidator(value, label: 'selling price'),
                  ),
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
                      hintText: 'Search ${_isProduct ? 'HSN' : 'SAC'} master',
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
                  LabeledField(
                    label: 'GST rate (%)',
                    child: TextFormField(
                      controller: _gstRateController,
                      enabled: !_isSaving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        helperText:
                            'Enter the rate manually; it is not taken from the HSN/SAC master.',
                      ),
                      validator: (value) =>
                          _taxRateValidator(value, required: true),
                    ),
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
      builder: (field) => LabeledField(
        label: 'Unit of Measurement',
        child: InputDecorator(
          decoration: InputDecoration(errorText: field.errorText),
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
                height: (MediaQuery.sizeOf(context).height * 0.6).clamp(
                  200,
                  420,
                ),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

/// One invoice colour scheme as a square: paper colour with an ink swatch,
/// an orange border and tick when chosen (Settings.png).
class _ColourSwatch extends StatelessWidget {
  const _ColourSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });
  final InvoicePalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: palette.label,
    child: Semantics(
      selected: selected,
      label: palette.label,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Pressable(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            color: palette.paperColor,
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? SimplekColors.orange
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: palette.inkColor,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: SimplekColors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 13,
                  color: SimplekColors.navy,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
