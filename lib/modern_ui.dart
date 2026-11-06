import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DesignSettings {
  static final modern = ValueNotifier(true);
  static final destination = ValueNotifier(0);
  static Future<void> load() async {
    modern.value =
        (await SharedPreferences.getInstance()).getBool('modern_design') ??
        true;
  }

  static Future<void> setModern(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(
      'modern_design',
      value,
    );
    destination.value = 0;
    modern.value = value;
  }
}

ThemeData simplekTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = Color(dark ? 0xFF0B0F19 : 0xFFF8FAFC);
  final surface = Color(dark ? 0xFF161F30 : 0xFFFFFFFF);
  final primary = Color(dark ? 0xFF60A5FA : 0xFF1E3A8A);
  final text = Color(dark ? 0xFFF8FAFC : 0xFF0F172A);
  final muted = Color(dark ? 0xFF94A3B8 : 0xFF64748B);
  final border = Color(dark ? 0xFF283548 : 0xFFE2E8F0);
  final scheme =
      ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF0B0F19) : Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        outlineVariant: border,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: background,
    textTheme: base.textTheme
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          headlineMedium: base.textTheme.headlineMedium!.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: text,
            letterSpacing: -0.6,
          ),
          titleLarge: base.textTheme.titleLarge!.copyWith(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: text,
          ),
          titleMedium: base.textTheme.titleMedium!.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: base.textTheme.titleLarge!.copyWith(
        color: text,
        fontSize: 21,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: shape,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: primary.withValues(alpha: 0.12),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      shape: shape,
    ),
  );
}

class DesignSelector extends StatelessWidget {
  const DesignSelector({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: DesignSettings.modern,
    builder: (context, modern, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<bool>(
          key: ValueKey(modern),
          initialValue: modern,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'App design'),
          items: const [
            DropdownMenuItem(value: true, child: Text('Modern')),
            DropdownMenuItem(
              value: false,
              child: Text('Classic — previous design'),
            ),
          ],
          onChanged: (value) async {
            if (value != null) await DesignSettings.setModern(value);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Switch back to Classic anytime. Your records and settings stay unchanged.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class EditorSection extends StatelessWidget {
  const EditorSection(this.title, this.subtitle, {super.key});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class EditableTerms extends StatelessWidget {
  const EditableTerms({super.key, required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      maintainState: true,
      leading: const Icon(Icons.notes_outlined),
      title: const Text('Terms and conditions'),
      subtitle: const Text('Prefilled from Settings • Tap to edit'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Document terms',
            helperText: 'Edits apply to this document only.',
          ),
        ),
      ],
    ),
  );
}

class DocumentSaveBar extends StatelessWidget {
  const DocumentSaveBar({
    super.key,
    required this.saving,
    required this.onClose,
    required this.onNext,
  });
  final bool saving;
  final VoidCallback? onClose;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final close = OutlinedButton.icon(
              onPressed: saving ? null : onClose,
              icon: const Icon(Icons.check),
              label: const Text('Save & Close'),
            );
            final next = FilledButton.icon(
              onPressed: saving ? null : onNext,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(saving ? 'Saving...' : 'Save & Next'),
            );
            if (constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [next, const SizedBox(height: 8), close],
              );
            }
            return Row(
              children: [
                Expanded(child: close),
                const SizedBox(width: 12),
                Expanded(child: next),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class DocumentShareBar extends StatelessWidget {
  const DocumentShareBar({
    super.key,
    required this.onWhatsApp,
    required this.onEmail,
    required this.onShare,
  });
  final VoidCallback? onWhatsApp;
  final VoidCallback? onEmail;
  final VoidCallback? onShare;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 20;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: narrow
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 16) / 3,
                child: FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share PDF'),
                ),
              ),
              SizedBox(
                width: narrow
                    ? (stacked
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 8) / 2)
                    : (constraints.maxWidth - 16) / 3,
                child: OutlinedButton(
                  onPressed: onWhatsApp,
                  child: const Text('WhatsApp', maxLines: 1, softWrap: false),
                ),
              ),
              SizedBox(
                width: narrow
                    ? (stacked
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 8) / 2)
                    : (constraints.maxWidth - 16) / 3,
                child: OutlinedButton(
                  onPressed: onEmail,
                  child: const Text('Email'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class InvoiceStatusBadge extends StatelessWidget {
  const InvoiceStatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (status.toLowerCase()) {
      'paid' => Color(dark ? 0xFF34D399 : 0xFF047857),
      'overdue' => Color(dark ? 0xFFF87171 : 0xFFB91C1C),
      _ => Color(dark ? 0xFFFBBF24 : 0xFF92400E),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class SearchableStateField extends StatelessWidget {
  const SearchableStateField({
    super.key,
    this.initialValue,
    this.isExpanded = true,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.validator,
  });
  final String? initialValue;
  final bool isExpanded;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) {
    if (!DesignSettings.modern.value) {
      return DropdownButtonFormField<String>(
        initialValue: initialValue,
        isExpanded: isExpanded,
        items: items,
        onChanged: onChanged,
        decoration: decoration,
        validator: validator,
      );
    }
    return FormField<String>(
      key: ValueKey(initialValue),
      initialValue: initialValue,
      validator: validator,
      builder: (field) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChanged == null
            ? null
            : () async {
                var query = '';
                final result = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (sheetContext) => StatefulBuilder(
                    builder: (context, update) => Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.65,
                        child: Column(
                          children: [
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Select State / Union Territory',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: TextField(
                                decoration: const InputDecoration(
                                  hintText: 'Search states and UTs',
                                  prefixIcon: Icon(Icons.search),
                                ),
                                onChanged: (value) => update(
                                  () => query = value.trim().toLowerCase(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final item in items.where(
                                    (item) => (item.value ?? '')
                                        .toLowerCase()
                                        .contains(query),
                                  ))
                                    ListTile(
                                      title: Text(item.value ?? ''),
                                      selected: item.value == field.value,
                                      trailing: item.value == field.value
                                          ? const Icon(Icons.check)
                                          : null,
                                      onTap: () => Navigator.of(
                                        sheetContext,
                                      ).pop(item.value),
                                    ),
                                  if (!items.any(
                                    (item) => (item.value ?? '')
                                        .toLowerCase()
                                        .contains(query),
                                  ))
                                    const ListTile(
                                      title: Text(
                                        'No matching states or Union Territories',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                if (context.mounted && result != null) {
                  field.didChange(result);
                  onChanged!(result);
                }
              },
        child: InputDecorator(
          decoration: decoration.copyWith(errorText: field.errorText),
          isEmpty: field.value == null,
          child: Row(
            children: [
              Expanded(child: Text(field.value ?? 'Select state')),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }
}

class ModernOverview extends StatelessWidget {
  const ModernOverview({
    super.key,
    required this.sales,
    required this.outstanding,
    required this.invoiceCount,
    required this.customerCount,
    this.productCount,
    required this.loading,
    required this.error,
    required this.recent,
    required this.onNewInvoice,
    required this.onNewQuotation,
    required this.onCustomer,
    required this.onProduct,
    required this.onInvoices,
    required this.onRefresh,
  });
  final String sales, outstanding, invoiceCount, customerCount;
  final String? productCount;
  final bool loading;
  final String? error;
  final List<Map<String, String>> recent;
  final VoidCallback onNewInvoice,
      onNewQuotation,
      onCustomer,
      onProduct,
      onInvoices;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        const EditorSection(
          'Business overview',
          'Your sales, customers and next steps.',
        ),
        if (error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Could not refresh your overview. Previous totals may be out of date.',
                  ),
                  TextButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        if (loading) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 720
                ? 4
                : (c.maxWidth < 340 ||
                          MediaQuery.textScalerOf(context).scale(14) > 20
                      ? 1
                      : 2);
            final width = (c.maxWidth - (columns - 1) * 12) / columns;
            Widget metric(
              String label,
              String value,
              IconData icon,
              bool prominent,
            ) => SizedBox(
              width: width,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 18),
                      Text(
                        label,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        loading && recent.isEmpty ? '—' : value,
                        style: TextStyle(
                          fontSize: prominent ? 24 : 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                metric('Total sales', sales, Icons.trending_up, true),
                metric(
                  'Outstanding',
                  outstanding,
                  Icons.account_balance_wallet_outlined,
                  true,
                ),
                metric(
                  'Invoices',
                  invoiceCount,
                  Icons.receipt_long_outlined,
                  false,
                ),
                metric('Customers', customerCount, Icons.people_outline, false),
                if (productCount != null)
                  metric(
                    'Products & services',
                    productCount!,
                    Icons.inventory_2_outlined,
                    false,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onNewInvoice,
              icon: const Icon(Icons.add),
              label: const Text('New invoice'),
            ),
            OutlinedButton.icon(
              onPressed: onNewQuotation,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Quotation'),
            ),
            OutlinedButton.icon(
              onPressed: onCustomer,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Customer'),
            ),
            OutlinedButton.icon(
              onPressed: onProduct,
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Product / Service'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Recent invoices',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextButton(onPressed: onInvoices, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty && !loading)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    error == null
                        ? 'Ready for your first invoice?'
                        : 'Invoices are unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create an invoice, or view your saved invoices.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onNewInvoice,
                    child: const Text('Create invoice'),
                  ),
                ],
              ),
            ),
          ),
        ...recent.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onInvoices,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['number'] ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(row['customer'] ?? ''),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            row['amount'] ?? '',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          InvoiceStatusBadge(row['status'] ?? 'draft'),
                          Text(
                            row['date'] ?? '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
