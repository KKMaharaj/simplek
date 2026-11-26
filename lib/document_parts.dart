part of 'main.dart';

// Pieces shared by the invoice and quotation builders (UI-25, NewInvoice.png):
// the top bar, date fields, item cards with a quantity stepper, and the
// totals card.

/// A top bar with a square back button and a Fraunces title.
PreferredSizeWidget _simplekAppBar(
  BuildContext context,
  String title, {
  String? subtitle,
  List<Widget> actions = const [],
}) {
  final theme = Theme.of(context);
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: subtitle == null ? 68 : 76,
    titleSpacing: 16,
    title: Row(
      children: [
        if (canPop) ...[
          SquareIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      for (final action in actions) ...[action, const SizedBox(width: 8)],
      const SizedBox(width: 8),
    ],
  );
}

/// A labelled date box that opens the date picker ("25 Nov 2026 ▾").
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    this.emptyText = 'No date',
  });
  final String label;
  final DateTime? date;
  final VoidCallback? onTap;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LabeledField(
      label: label,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        color: theme.inputDecorationTheme.fillColor,
        child: InputDecorator(
          decoration: const InputDecoration(
            suffixIcon: Icon(Icons.expand_more),
          ),
          child: Text(
            date == null ? emptyText : screenDate(date),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}

/// − [qty] + : whole steps, the field still accepts decimals.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;

  void _step(int by) {
    final current = double.tryParse(controller.text.trim()) ?? 0;
    final next = (current + by).clamp(1, 1e9);
    controller.text = plainQuantity(next);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget button(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        semanticLabel: tooltip,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
        ),
      ),
    );
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: dark ? SimplekColors.darkField : SimplekColors.skyTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark ? SimplekColors.darkLine : SimplekColors.skyLine,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, 'Less', () => _step(-1)),
          SizedBox(
            width: 56,
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: inter(16, FontWeight.w700, theme.colorScheme.onSurface),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: SimplekColors.orange,
                    width: 2,
                  ),
                ),
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
              validator: (value) {
                final quantity = double.tryParse(value?.trim() ?? '');
                return quantity == null || quantity <= 0 ? '' : null;
              },
            ),
          ),
          button(Icons.add, 'More', () => _step(1)),
        ],
      ),
    );
  }
}

/// One item on a document: the chosen product, quantity, rate, GST and the
/// line amount.
class _LineItemCard extends StatelessWidget {
  const _LineItemCard({
    required this.item,
    required this.usesGst,
    required this.onPick,
    required this.onChanged,
    this.onRemove,
  });
  final InvoiceLineItem item;
  final bool usesGst;
  final VoidCallback onPick;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget numberField(
      TextEditingController controller,
      String label, {
      String? prefix,
      String? suffix,
      required String? Function(double? value) check,
    }) => LabeledField(
      label: label,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 16),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(prefixText: prefix, suffixText: suffix),
        validator: (value) => check(double.tryParse(value?.trim() ?? '')),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _PickedRecordField(
                    label: 'Product or service',
                    placeholder: 'Choose a product or service',
                    title: item.productController.text,
                    subtitle: item.summary,
                    emptyError: 'Choose a product or service',
                    onPick: onPick,
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 8),
                  SquareIconButton(
                    icon: Icons.close,
                    tooltip: 'Remove this item',
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final qty = SizedBox(
                  width: 148,
                  child: LabeledField(
                    label: 'Qty',
                    child: _QuantityStepper(
                      controller: item.quantityController,
                      focusNode: item.quantityFocus,
                      onChanged: onChanged,
                    ),
                  ),
                );
                final rate = numberField(
                  item.rateController,
                  'Rate',
                  prefix: '₹ ',
                  check: (value) =>
                      value == null || value < 0 ? 'Enter the rate' : null,
                );
                final gst = numberField(
                  item.gstRateController,
                  'GST',
                  suffix: '%',
                  check: (value) => value == null || value < 0 || value > 100
                      ? 'Enter 0 to 100'
                      : null,
                );
                final priceRow = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: rate),
                    if (usesGst) ...[
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: gst),
                    ],
                  ],
                );
                if (constraints.maxWidth >= 420) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      qty,
                      const SizedBox(width: 10),
                      Expanded(child: priceRow),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [qty, const SizedBox(height: 10), priceRow],
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    usesGst ? 'Amount incl. GST' : 'Amount',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  rupees(item.total),
                  style: inter(
                    17,
                    FontWeight.w700,
                    theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Taxable value, CGST/SGST or IGST, round off and the orange total.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.usesGst,
    required this.intraState,
    required this.exactTotal,
    required this.total,
    required this.totalLabel,
  });
  final double taxable, cgst, sgst, igst, exactTotal, total;
  final bool usesGst, intraState;
  final String totalLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final roundOff = roundOffFor(exactTotal);
    Widget line(String label, double amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            label == 'Round off' && amount > 0
                ? '+ ${rupees(amount)}'
                : rupees(amount),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
    return SectionCard(
      child: Column(
        children: [
          line(usesGst ? 'Taxable value' : 'Subtotal', taxable),
          if (usesGst)
            if (intraState) ...[
              line('CGST', cgst),
              line('SGST', sgst),
            ] else
              line('IGST', igst),
          if (roundOff != 0) line('Round off', roundOff),
          const SizedBox(height: 6),
          Divider(color: dark ? SimplekColors.darkLine : SimplekColors.skyLine),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  totalLabel,
                  style: inter(
                    17,
                    FontWeight.w700,
                    dark ? SimplekColors.orange : SimplekColors.orangeText,
                  ),
                ),
              ),
              Text(
                rupees(total),
                style: inter(
                  19,
                  FontWeight.w700,
                  dark ? SimplekColors.orange : SimplekColors.orangeText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// List padding that keeps a long form at most 760 px wide and centred,
/// beside the sidebar on wide screens.
EdgeInsets _formPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final available = width >= 1024
      ? (width - 248).clamp(0, 1160).toDouble()
      : width;
  final side = ((available - 760) / 2).clamp(16, double.infinity).toDouble();
  return EdgeInsets.fromLTRB(side, 8, side, 32);
}

/// Sales by week for the period on screen: sky bars, the latest week in
/// orange (Reports.png). Uses the invoices already loaded.
class _WeeklySalesChart extends StatelessWidget {
  const _WeeklySalesChart({required this.invoices});
  final List<Map<String, dynamic>> invoices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dated = [
      for (final invoice in invoices)
        if (parseStoredDate(invoice['invoice_date']) case final date?)
          (date, (invoice['total_amount'] as num?)?.toDouble() ?? 0),
    ];
    if (dated.isEmpty) return const SizedBox.shrink();
    final latest = dated
        .map((entry) => entry.$1)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final end = DateUtils.dateOnly(latest);
    // Four weeks ending on the latest invoice date.
    final weeks = [
      for (var i = 3; i >= 0; i--)
        (
          start: end.subtract(Duration(days: i * 7 + 6)),
          end: end.subtract(Duration(days: i * 7)),
        ),
    ];
    final totals = [
      for (final week in weeks)
        dated
            .where(
              (entry) =>
                  !DateUtils.dateOnly(entry.$1).isBefore(week.start) &&
                  !DateUtils.dateOnly(entry.$1).isAfter(week.end),
            )
            .fold<double>(0, (sum, entry) => sum + entry.$2),
    ];
    final highest = totals.reduce((a, b) => a > b ? a : b);
    String label(({DateTime start, DateTime end}) week) =>
        '${week.start.day}–${week.end.day} ${screenDate(week.end).split(' ')[1]}';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sales by week',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text('last 4 weeks', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: rupees(totals[i]),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            height: highest == 0
                                ? 4
                                : (100 * totals[i] / highest).clamp(4, 100),
                            decoration: BoxDecoration(
                              color: i == 3
                                  ? SimplekColors.orange
                                  : (totals[i] == highest
                                        ? SimplekColors.sky
                                        : SimplekColors.skyTint),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label(weeks[i]),
                            maxLines: 1,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
