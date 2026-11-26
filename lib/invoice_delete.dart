part of 'main.dart';

// CR-25B B1: deleting invoices (a soft delete with Undo) and the GST warnings
// on deleting or editing an invoice and on changing details that old
// invoices show again.

/// The highlighted line a GST-registered business sees before deleting.
const gstDeleteWarning =
    'If this invoice is already included in a GST return (GSTR-1), deleting '
    'it will cause differences in your GST filings.';

/// Shown before editing an invoice dated before today (GST businesses only).
const gstEditWarning =
    "Changes to this invoice may cause differences in GST returns you've "
    'already filed.';

/// After saving details that old invoices also show (business profile,
/// product HSN/SAC or GST rate).
String oldInvoicesNote({required bool gst}) => gst
    ? 'Old invoices will also show the new details when you open or share '
          "them again, which may not match GST returns you've already filed."
    : 'Old invoices will also show the new details when you open or share '
          'them again.';

/// The one shared warning dialog for deleting or editing an invoice.
/// Returns true when the user chose [confirmLabel].
Future<bool> showInvoiceWarning(
  BuildContext context, {
  required String title,
  String? body,
  String? gstLine,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (body != null) Text(body),
            if (body != null && gstLine != null) const SizedBox(height: 12),
            if (gstLine != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dark
                      ? SimplekColors.orange.withValues(alpha: 0.16)
                      : SimplekColors.orangeTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: SimplekColors.orange.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: dark
                          ? SimplekColors.orange
                          : SimplekColors.orangeText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        gstLine,
                        style: inter(
                          14,
                          FontWeight.w600,
                          theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// "Delete invoice INV/2026-27/24?", with the GST line for GST businesses.
Future<bool> confirmDeleteInvoice(BuildContext context, String number) =>
    showInvoiceWarning(
      context,
      title: 'Delete invoice $number?',
      body: 'It will be removed from your invoices, totals and reports.',
      gstLine: BusinessSettings.isGstRegistered.value ? gstDeleteWarning : null,
      confirmLabel: 'Delete',
      destructive: true,
    );

/// Asked once when Edit is opened on an invoice dated before today, for GST
/// businesses only. True when the edit may go ahead.
Future<bool> confirmEditInvoice(
  BuildContext context,
  Map<String, dynamic> invoice, {
  DateTime? today,
}) async {
  if (!editNeedsGstWarning(invoice, today: today)) return true;
  final number = invoice['invoice_number']?.toString().trim() ?? '';
  return showInvoiceWarning(
    context,
    title: number.isEmpty ? 'Edit this invoice?' : 'Edit invoice $number?',
    gstLine: gstEditWarning,
    confirmLabel: 'Edit anyway',
  );
}

/// True when editing [invoice] needs the GST warning: the business is GST
/// registered and the invoice is dated before today.
bool editNeedsGstWarning(Map<String, dynamic> invoice, {DateTime? today}) {
  if (!BusinessSettings.isGstRegistered.value) return false;
  final date = parseStoredDate(invoice['invoice_date']);
  if (date == null) return false;
  final now = today ?? DateTime.now();
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).isBefore(DateTime(now.year, now.month, now.day));
}

/// Asks, deletes the invoice on the server and shows "Invoice deleted" with
/// Undo for 10 seconds. [onChanged] runs after the delete and after an Undo.
/// Returns true when the invoice was deleted.
Future<bool> deleteInvoiceWithUndo(
  BuildContext context, {
  required String invoiceId,
  required String number,
  VoidCallback? onChanged,
}) async {
  if (BusinessAccess.readOnly) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(BusinessAccess.readOnlyMessage)),
    );
    return false;
  }
  if (!await confirmDeleteInvoice(context, number)) return false;
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  final client = Supabase.instance.client;
  try {
    await client.rpc('delete_invoice', params: {'p_invoice_id': invoiceId});
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _connectionMessage(error, fallback: 'Unable to delete this invoice.'),
        ),
      ),
    );
    return false;
  }
  invoiceChanges.value++;
  onChanged?.call();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Invoice $number deleted'),
        duration: const Duration(seconds: 10),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await client.rpc(
                'restore_invoice',
                params: {'p_invoice_id': invoiceId},
              );
              invoiceChanges.value++;
              onChanged?.call();
              messenger.showSnackBar(
                SnackBar(content: Text('Invoice $number restored')),
              );
            } catch (error) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    _connectionMessage(
                      error,
                      fallback: 'Unable to restore this invoice.',
                    ),
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  return true;
}

/// Business profile fields that old invoices show again when reopened.
const _profileFieldsOnInvoices = {
  'name',
  'address',
  'addressLine1',
  'addressLine2',
  'landmark',
  'city',
  'district',
  'pincode',
  'businessState',
  'gstin',
  'bankName',
  'bankBranch',
  'bankAccount',
  'ifsc',
  'upiId',
};

/// True when saving [after] over [before] changes something old invoices
/// show: the business name, address, GSTIN, bank or UPI details.
bool profileChangeShowsOnOldInvoices(
  Map<String, String> before,
  Map<String, String> after,
) {
  if (before.isEmpty) return false;
  for (final key in _profileFieldsOnInvoices) {
    if (!after.containsKey(key)) continue;
    if ((before[key] ?? '').trim() != (after[key] ?? '').trim()) return true;
  }
  return false;
}

/// True when an edited product's HSN/SAC code or GST rate changed.
bool productChangeShowsOnOldInvoices(
  Map<String, dynamic>? before,
  Map<String, dynamic> after,
) {
  if (before == null) return false;
  String code(Object? value) => value?.toString().trim() ?? '';
  double? rate(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
  return code(before['hsn_sac_code']) != code(after['hsn_sac_code']) ||
      rate(before['gst_rate']) != rate(after['gst_rate']);
}
