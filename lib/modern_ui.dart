import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'form_fields.dart';
import 'india_states.dart';
import 'ui_kit.dart';

export 'app_theme.dart';
export 'form_fields.dart';
export 'india_states.dart';
export 'ui_kit.dart';

/// Which section of the app shell is showing.
class DesignSettings {
  static final destination = ValueNotifier(0);

  /// Always true. The old "Classic" design was removed; a few document
  /// screens still branch on this until those branches are deleted.
  static final modern = ValueNotifier(true);
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
        LabeledField(
          label: 'Document terms',
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              helperText: 'Edits apply to this document only.',
            ),
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

  /// Save and go back.
  final VoidCallback? onClose;

  /// Save and open the preview.
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final close = OutlinedButton(
                onPressed: saving ? null : onClose,
                child: const Text('Save', maxLines: 1),
              );
              final next = FilledButton.icon(
                onPressed: saving ? null : onNext,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SimplekColors.navy,
                        ),
                      )
                    : const Icon(Icons.visibility_outlined),
                label: Text(
                  saving ? 'Saving…' : 'Save and preview',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
              if (constraints.maxWidth < 330 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [next, const SizedBox(height: 8), close],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 2, child: close),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: next),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => StatusChip(status);
}

/// A field that opens a searchable list (states, districts). The label sits
/// above the box; when nothing is chosen the box shows only a grey hint, so
/// the two can never overlap (CR-25 change 3).
class SearchablePickerField extends StatelessWidget {
  const SearchablePickerField({
    super.key,
    required this.label,
    required this.options,
    this.value,
    this.onChanged,
    this.validator,
    this.required = false,
    this.hint = 'Select',
    this.helperText,
    this.sheetTitle,
    this.searchHint = 'Search',
    this.emptyText = 'Nothing matches',
    this.readOnly = false,
  });

  final String label;
  final List<String> options;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool required;
  final String hint;
  final String? helperText;
  final String? sheetTitle;
  final String searchHint;
  final String emptyText;

  /// Shows the value but can't be changed (e.g. the state from a GSTIN).
  final bool readOnly;

  Future<void> _open(BuildContext context, FormFieldState<String> field) async {
    var query = '';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) {
          final visible = options
              .where((option) => option.toLowerCase().contains(query))
              .toList();
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      sheetTitle ?? 'Select ${label.toLowerCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: options.length > 12,
                      decoration: InputDecoration(
                        hintText: searchHint,
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (text) =>
                          update(() => query = text.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(emptyText, textAlign: TextAlign.center),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, index) {
                              final option = visible[index];
                              final selected = option == field.value;
                              return ListTile(
                                title: Text(option),
                                selected: selected,
                                trailing: selected
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () =>
                                    Navigator.of(sheetContext).pop(option),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (context.mounted && result != null) {
      field.didChange(result);
      onChanged?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onChanged == null && !readOnly;
    return FormField<String>(
      key: ValueKey('$label:$value:$readOnly'),
      initialValue: value,
      validator: validator,
      builder: (field) {
        final shown = field.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FieldLabel(label, required: required),
            Opacity(
              opacity: disabled ? 0.5 : 1,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: readOnly || disabled
                    ? null
                    : () => _open(context, field),
                child: InputDecorator(
                  isEmpty: false,
                  decoration: InputDecoration(
                    errorText: field.errorText,
                    helperText: helperText,
                    filled: true,
                    fillColor: readOnly ? SimplekColors.navyTint : null,
                    suffixIcon: Icon(
                      readOnly ? Icons.lock_outline : Icons.expand_more,
                    ),
                  ),
                  child: Text(
                    shown ?? hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shown == null
                        ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                        : const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The state / union territory picker used everywhere.
class SearchableStateField extends StatelessWidget {
  const SearchableStateField({
    super.key,
    this.label = 'State',
    this.value,
    this.onChanged,
    this.validator,
    this.required = false,
    this.helperText,
    this.readOnly = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool required;
  final String? helperText;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => SearchablePickerField(
    label: label,
    options: indiaStateNames,
    value: stateNamed(value ?? '')?.name,
    onChanged: onChanged,
    validator: validator,
    required: required,
    helperText: helperText,
    readOnly: readOnly,
    hint: 'Select state',
    sheetTitle: 'Select State / Union Territory',
    searchHint: 'Search states and UTs',
    emptyText: 'No matching states or Union Territories',
  );
}

/// The home screen (docs/design/Home.png and WebHome.png): money owed up
/// front on a navy card, four quick actions, then recent invoices.
class ModernOverview extends StatelessWidget {
  const ModernOverview({
    super.key,
    required this.sales,
    required this.outstanding,
    required this.invoiceCount,
    required this.customerCount,
    this.productCount,
    this.businessName = '',
    this.readOnly = false,
    required this.loading,
    required this.error,
    required this.recent,
    required this.onNewInvoice,
    required this.onNewQuotation,
    required this.onCustomer,
    required this.onProduct,
    required this.onInvoices,
    required this.onRefresh,
    this.onOpenInvoice,
    this.onPayment,
    this.onSearch,
    this.onReports,
    this.unpaidCount,
    this.collected,
    this.partlyPaidCount,
  });
  final String sales, outstanding, invoiceCount, customerCount, businessName;
  final String? productCount;
  final bool loading;

  /// Hides everything that creates records (view-only accountant access).
  final bool readOnly;
  final String? error;
  final List<Map<String, String>> recent;
  final VoidCallback onNewInvoice,
      onNewQuotation,
      onCustomer,
      onProduct,
      onInvoices;
  final Future<void> Function() onRefresh;

  /// Opens one recent invoice by id. Falls back to the list when null.
  final void Function(String id)? onOpenInvoice;

  /// Record payment. When null the fourth tile adds a product instead.
  final VoidCallback? onPayment;
  final VoidCallback? onSearch;
  final VoidCallback? onReports;
  final int? unpaidCount;
  final String? collected;
  final int? partlyPaidCount;

  static String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
  }

  bool get _blank => loading && recent.isEmpty;
  String _figure(String value) => _blank ? '—' : value;

  List<(IconData, String, TileTone, VoidCallback)> get _actions => [
    (Icons.receipt_long_outlined, 'Invoice', TileTone.orange, onNewInvoice),
    (Icons.description_outlined, 'Quotation', TileTone.sky, onNewQuotation),
    (Icons.people_alt_outlined, 'Customer', TileTone.navy, onCustomer),
    onPayment != null
        ? (
            Icons.account_balance_wallet_outlined,
            'Payment',
            TileTone.orange,
            onPayment!,
          )
        : (Icons.inventory_2_outlined, 'Item', TileTone.orange, onProduct),
  ];

  Widget _header(BuildContext context, {bool wide = false}) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(), style: theme.textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                businessName.isEmpty ? 'Your business today' : businessName,
                style: wide
                    ? theme.textTheme.headlineMedium
                    : theme.textTheme.headlineSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (wide && onSearch != null) ...[
          const SizedBox(width: 16),
          SizedBox(
            width: 320,
            child: Pressable(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text('Search everything', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          if (!readOnly) ...[
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onNewInvoice,
              icon: const Icon(Icons.add),
              label: const Text('New invoice'),
            ),
          ],
        ] else ...[
          if (onSearch != null) ...[
            const SizedBox(width: 8),
            SquareIconButton(
              icon: Icons.search,
              tooltip: 'Search everything',
              onPressed: onSearch,
            ),
          ],
          const SizedBox(width: 8),
          SquareIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: loading ? null : onRefresh,
          ),
        ],
      ],
    );
  }

  Widget _errorCard() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          const IconTile(Icons.cloud_off_outlined, size: 40),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Could not refresh. Totals may be out of date.',
              maxLines: 2,
            ),
          ),
          TextButton(onPressed: onRefresh, child: const Text('Retry')),
        ],
      ),
    ),
  );

  Widget _recentRows(BuildContext context) {
    if (recent.isEmpty && loading) return const SkeletonRows(count: 3);
    if (recent.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message: error == null
            ? 'No invoices yet. Create your first invoice.'
            : 'Invoices are unavailable right now.',
        actionLabel: readOnly ? null : 'Create invoice',
        onAction: readOnly ? null : onNewInvoice,
      );
    }
    return RowGroup(
      children: [
        for (final row in recent)
          ListRowTile(
            leading: InitialTile(row['customer'] ?? ''),
            title: (row['customer'] ?? '').isEmpty
                ? 'Customer'
                : row['customer']!,
            subtitle: [
              row['number'] ?? '',
              row['date'] ?? '',
            ].where((part) => part.isNotEmpty).join(' · '),
            trailingTop: Text(
              row['amount'] ?? '',
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
              ),
            ),
            trailingBottom: StatusChip(row['status'] ?? 'draft'),
            onTap: onOpenInvoice != null && (row['id'] ?? '').isNotEmpty
                ? () => onOpenInvoice!(row['id']!)
                : onInvoices,
          ),
      ],
    );
  }

  Widget _recentHeading(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          'Recent invoices',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      TextButton(onPressed: onInvoices, child: const Text('View all')),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= 900
        ? _wide(context)
        : _phone(context, constraints.maxWidth),
  );

  Widget _phone(BuildContext context, double width) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
      children: [
        _header(context),
        const SizedBox(height: 14),
        if (error != null) _errorCard(),
        _MoneyCard(
          outstanding: _figure(outstanding),
          unpaidCount: unpaidCount,
          sales: _figure(sales),
          invoiceCount: _figure(invoiceCount),
          loading: loading,
          onNewInvoice: readOnly ? null : onNewInvoice,
        ),
        if (!readOnly) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (index, action) in _actions.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ActionTile(
                    icon: action.$1,
                    label: action.$2,
                    tone: action.$3,
                    onTap: action.$4,
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 18),
        _recentHeading(context),
        const SizedBox(height: 6),
        _recentRows(context),
      ],
    ),
  );

  Widget _wide(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
        children: [
          _header(context, wide: true),
          const SizedBox(height: 22),
          if (error != null) _errorCard(),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MoneyCard(
                    outstanding: _figure(outstanding),
                    unpaidCount: unpaidCount,
                    loading: loading,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _WideStat(
                    label: 'Total sales',
                    value: _figure(sales),
                    note: '$invoiceCount invoices',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _WideStat(
                    label: 'Collected',
                    value: _figure(collected ?? '—'),
                    tone: TileTone.sky,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _WideStat(
                    label: 'Invoices',
                    value: _figure(invoiceCount),
                    note: partlyPaidCount == null
                        ? null
                        : '$partlyPaidCount partly paid',
                    tone: TileTone.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _recentHeading(context),
                    const SizedBox(height: 6),
                    _recentRows(context),
                  ],
                ),
              ),
              if (!readOnly) ...[
                const SizedBox(width: 18),
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Quick actions',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      RowGroup(
                        children: [
                          ListRowTile(
                            leading: const IconTile(
                              Icons.description_outlined,
                              tone: TileTone.sky,
                              size: 40,
                            ),
                            title: 'New quotation',
                            subtitle: 'Send prices first',
                            showChevron: true,
                            onTap: onNewQuotation,
                          ),
                          if (onPayment != null)
                            ListRowTile(
                              leading: const IconTile(
                                Icons.account_balance_wallet_outlined,
                                size: 40,
                              ),
                              title: 'Record payment',
                              subtitle: 'Mark money received',
                              showChevron: true,
                              onTap: onPayment,
                            ),
                          ListRowTile(
                            leading: const IconTile(
                              Icons.people_alt_outlined,
                              tone: TileTone.navy,
                              size: 40,
                            ),
                            title: 'Add customer',
                            subtitle: 'Name, mobile, GSTIN',
                            showChevron: true,
                            onTap: onCustomer,
                          ),
                          if (onReports != null)
                            ListRowTile(
                              leading: const IconTile(
                                Icons.download_outlined,
                                tone: TileTone.sky,
                                size: 40,
                              ),
                              title: 'Export for accountant',
                              subtitle: 'Reports, Tally, Excel',
                              showChevron: true,
                              onTap: onReports,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The navy "To collect" card.
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({
    required this.outstanding,
    required this.loading,
    this.unpaidCount,
    this.sales,
    this.invoiceCount,
    this.onNewInvoice,
    this.compact = false,
  });
  final String outstanding;
  final bool loading;
  final int? unpaidCount;
  final String? sales;
  final String? invoiceCount;
  final VoidCallback? onNewInvoice;

  /// Web: the figure only, as one of four stat cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget tile(String label, String value) => Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: SimplekColors.navy2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: inter(13, FontWeight.w500, const Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: inter(18, FontWeight.w700, Colors.white)),
          ),
        ],
      ),
    );
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 20),
      decoration: BoxDecoration(
        color: dark ? SimplekColors.navyDeep : SimplekColors.navy,
        borderRadius: BorderRadius.circular(compact ? 16 : 22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'To collect',
            style: inter(14, FontWeight.w600, const Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              outstanding,
              style: inter(
                compact ? 28 : 36,
                FontWeight.w700,
                Colors.white,
              ).copyWith(letterSpacing: -0.8),
            ),
          ),
          if (unpaidCount != null)
            Text(
              'from $unpaidCount unpaid invoice${unpaidCount == 1 ? '' : 's'}',
              style: inter(13.5, FontWeight.w500, SimplekColors.sky),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: SimplekColors.sky,
                backgroundColor: Color(0x33FFFFFF),
              ),
            ),
          if (!compact && sales != null && invoiceCount != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: tile('Total sales', sales!)),
                const SizedBox(width: 10),
                Expanded(child: tile('Invoices', invoiceCount!)),
              ],
            ),
          ],
          if (!compact && onNewInvoice != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onNewInvoice,
              icon: const Icon(Icons.add),
              label: const Text('New invoice'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WideStat extends StatelessWidget {
  const _WideStat({
    required this.label,
    required this.value,
    this.note,
    this.tone,
  });
  final String label, value;
  final String? note;
  final TileTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = tone == null
        ? null
        : toneColors(tone!, theme.brightness == Brightness.dark);
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors?.background ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors == null
              ? theme.colorScheme.outlineVariant
              : colors.foreground.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: inter(
              14,
              FontWeight.w600,
              colors?.foreground ?? theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: inter(28, FontWeight.w700, theme.colorScheme.onSurface),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: inter(
                13,
                FontWeight.w500,
                colors?.foreground ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final TileTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      onTap: onTap,
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            IconTile(icon, tone: tone, size: 44),
            const SizedBox(height: 8),
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
    );
  }
}
