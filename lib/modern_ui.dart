import 'package:flutter/material.dart';

import 'app_theme.dart';

export 'app_theme.dart';

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
      'partial' => Color(dark ? 0xFF8EA2FF : 0xFF2A3FD6),
      'draft' || 'cancelled' => Color(dark ? 0xFF9AA3C0 : 0xFF667091),
      'overdue' => Color(dark ? 0xFFF87171 : 0xFFB91C1C),
      _ => Color(dark ? 0xFFFBBF24 : 0xFF92400E),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.isEmpty
            ? ''
            : status[0].toUpperCase() + status.substring(1).toLowerCase(),
        style: TextStyle(
          color: color,
          fontSize: 11.5,
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

/// The home screen: money owed up front, then shortcuts and recent invoices.
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

  static String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final blank = loading && recent.isEmpty;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
        children: [
          Text(_greeting(), style: TextStyle(color: muted, fontSize: 14)),
          const SizedBox(height: 2),
          Text(
            businessName.isEmpty ? 'Your business today' : businessName,
            style: theme.textTheme.headlineSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          if (error != null) ...[
            Card(
              child: ListTile(
                leading: const TintedIcon(
                  Icons.cloud_off_outlined,
                  color: SimplekColors.warning,
                ),
                title: const Text('Could not refresh'),
                subtitle: const Text('Totals below may be out of date.'),
                trailing: TextButton(
                  onPressed: onRefresh,
                  child: const Text('Retry'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _HeroCard(
            outstanding: blank ? '—' : outstanding,
            sales: blank ? '—' : sales,
            invoiceCount: blank ? '—' : invoiceCount,
            loading: loading,
            onNewInvoice: readOnly ? null : onNewInvoice,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.people_alt_outlined,
                  color: SimplekColors.violet,
                  label: 'Customers',
                  value: blank ? '—' : customerCount,
                ),
              ),
              if (productCount != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.inventory_2_outlined,
                    color: SimplekColors.success,
                    label: 'Items',
                    value: blank ? '—' : productCount!,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 26),
          if (!readOnly) ...[
            Text('Quick actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 560 ? 4 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final action in [
                      (
                        Icons.receipt_long_outlined,
                        'Invoice',
                        SimplekColors.brand,
                        onNewInvoice,
                      ),
                      (
                        Icons.description_outlined,
                        'Quotation',
                        SimplekColors.violet,
                        onNewQuotation,
                      ),
                      (
                        Icons.person_add_alt_outlined,
                        'Customer',
                        SimplekColors.warning,
                        onCustomer,
                      ),
                      (
                        Icons.add_box_outlined,
                        'Product / Service',
                        SimplekColors.success,
                        onProduct,
                      ),
                    ])
                      SizedBox(
                        width: width,
                        child: _ActionTile(
                          icon: action.$1,
                          label: action.$2,
                          color: action.$3,
                          onTap: action.$4,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent invoices',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              TextButton(onPressed: onInvoices, child: const Text('View all')),
            ],
          ),
          const SizedBox(height: 6),
          if (recent.isEmpty && !loading)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const TintedIcon(Icons.receipt_long_outlined, size: 56),
                    const SizedBox(height: 14),
                    Text(
                      error == null
                          ? 'Ready for your first invoice?'
                          : 'Invoices are unavailable',
                      style: theme.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'It takes under a minute, and you can share it right away.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                    if (!readOnly) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: onNewInvoice,
                        child: const Text('Create invoice'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (recent.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (index, row) in recent.indexed) ...[
                    if (index > 0) const Divider(indent: 72),
                    _RecentInvoiceRow(row: row, onTap: onInvoices),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.outstanding,
    required this.sales,
    required this.invoiceCount,
    required this.loading,
    required this.onNewInvoice,
  });
  final String outstanding, sales, invoiceCount;
  final bool loading;
  final VoidCallback? onNewInvoice;

  @override
  Widget build(BuildContext context) {
    const soft = Color(0xCCFFFFFF);
    return Container(
      decoration: BoxDecoration(
        gradient: SimplekColors.heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x553B5BFD),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            right: -40,
            top: -50,
            child: _Glow(size: 170, alpha: 0.12),
          ),
          const Positioned(
            right: 40,
            bottom: -70,
            child: _Glow(size: 150, alpha: 0.08),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To collect',
                  style: TextStyle(color: soft, fontSize: 14),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    outstanding,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: Colors.white,
                      backgroundColor: Color(0x33FFFFFF),
                    ),
                  ),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _HeroFigure(label: 'Total sales', value: sales),
                    _HeroFigure(label: 'Invoices', value: invoiceCount),
                  ],
                ),
                if (onNewInvoice != null) const SizedBox(height: 18),
                if (onNewInvoice != null)
                  FilledButton.icon(
                    onPressed: onNewInvoice,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: SimplekColors.brandDeep,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('New invoice'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.alpha});
  final double size, alpha;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: alpha),
    ),
  );
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12.5),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label, value;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          TintedIcon(icon, color: color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TintedIcon(icon, color: color, size: 42),
                const Spacer(),
                Icon(
                  Icons.add_circle,
                  color: color.withValues(alpha: 0.9),
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentInvoiceRow extends StatelessWidget {
  const _RecentInvoiceRow({required this.row, required this.onTap});
  final Map<String, String> row;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = row['customer'] ?? '';
    final initial = customer.trim().isEmpty
        ? '#'
        : customer.trim()[0].toUpperCase();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Text(
                initial,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.isEmpty ? 'Customer' : customer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      row['number'] ?? '',
                      row['date'] ?? '',
                    ].where((part) => part.isNotEmpty).join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(row['amount'] ?? '', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                InvoiceStatusBadge(row['status'] ?? 'draft'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
