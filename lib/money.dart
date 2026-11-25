/// Money formatting and rounding shared by the app screens and the PDFs.
library;

export 'india_states.dart'
    show gstStateCode, stateWithCode, sameGstState, composeBusinessAddress;

/// Amount in whole paise, avoiding floating-point noise such as 2799.9899.
int toPaise(num amount) => (amount * 100).round();

/// Rounds a document total to the nearest rupee, 50 paise and above going up
/// (the same rule as the Eesha Herbals reference invoice).
double roundToRupee(num amount) {
  final paise = toPaise(amount);
  final rupees = paise >= 0 ? (paise + 50) ~/ 100 : -((-paise + 50) ~/ 100);
  return rupees.toDouble();
}

/// The "Round off" line: rounded total minus the exact total, to the paisa.
double roundOffFor(num exactTotal) =>
    (toPaise(roundToRupee(exactTotal)) - toPaise(exactTotal)) / 100;

/// Indian digit grouping: 1234567.8 -> "12,34,567.80".
String indianNumber(num amount, {int decimals = 2}) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts.first;
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    grouped = '${groups.join(',')},$last3';
  }
  final text = parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  return negative ? '-$text' : text;
}

/// "₹12,34,567.80". Negative amounts use a true minus sign: "− ₹0.40".
String rupees(num amount) {
  if (amount < 0) return '− ₹${indianNumber(-amount)}';
  return '₹${indianNumber(amount)}';
}

/// Quantity without trailing zeros: 2.0 -> "2", 1.5 -> "1.5".
String plainQuantity(num quantity) {
  final text = quantity.toStringAsFixed(3);
  return text.contains('.')
      ? text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : text;
}

/// GST rate without trailing zeros: 18.0 -> "18%", 2.5 -> "2.5%".
String percent(num rate) => '${plainQuantity(rate)}%';

/// dd/mm/yyyy, or "-" when there is no date.
String displayDate(DateTime? date) => date == null
    ? '-'
    : '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/${date.year}';

/// Parses a stored date such as "2026-11-19" or "2026-11-19T00:00:00".
DateTime? parseStoredDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
