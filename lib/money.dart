/// Money formatting and rounding shared by the app screens and the PDFs.
library;

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

/// The GST state code for a state or union territory name, e.g. "29" for
/// Karnataka. Returns null when the name is not recognised.
String? gstStateCode(String state) {
  final name = state.trim().toLowerCase();
  for (final entry in _gstStateCodes.entries) {
    if (entry.value.toLowerCase() == name) return entry.key;
  }
  return null;
}

/// "Karnataka (29)", or the name alone if its code is not known.
String stateWithCode(String state) {
  final code = gstStateCode(state);
  return code == null || state.trim().isEmpty
      ? state.trim()
      : '${state.trim()} ($code)';
}

const _gstStateCodes = <String, String>{
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
