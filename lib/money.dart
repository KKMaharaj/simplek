/// Money formatting and rounding shared by the app screens and the PDFs.
///
/// ## The rounding rule (CR-25B B3, BUILD-STANDARDS 8.1)
///
/// All money maths is done in whole paise ([Paise]), never in `double`.
/// Quantities, rates and GST percentages are read as exact decimals.
///
/// 1. Line taxable value = quantity × rate, rounded half-up to the paisa.
/// 2. Line tax = taxable value × GST % ÷ 100, rounded half-up to the paisa.
/// 3. Within the business's state: CGST = tax ÷ 2 rounded half-up, and
///    SGST = tax − CGST, so the two always add up to the tax exactly
///    (₹5.05 → ₹2.53 + ₹2.52). Otherwise IGST = tax.
/// 4. Line total = taxable value + tax.
/// 5. Document subtotal, tax, CGST, SGST and IGST are sums of the line
///    values. The PDF's rate-wise CGST/SGST lines are sums of the line
///    values at that rate.
/// 6. Total payable = subtotal + tax, rounded to the rupee half-up (50 paise
///    and above go up, decided on 19 Nov); the difference is "Round off".
/// 7. The amount in words is always the printed total payable.
///
/// "Half-up" means half away from zero, which is what Postgres `round()`
/// does: `save_invoice` repeats this maths on the server and rejects a
/// mismatch. Postgres `numeric(…, 2)` columns are exact decimals; values are
/// converted to and from [Paise] at that boundary only.
library;

export 'india_states.dart'
    show gstStateCode, stateWithCode, sameGstState, composeBusinessAddress;

/// An amount of money in whole paise. Arithmetic stays in integers; the
/// rupee value ([inRupees]) is only for display and for sending to the
/// server.
extension type const Paise(int value) implements Object {
  static const zero = Paise(0);

  /// An amount read from the server or typed by the user: "2.53", 2.53,
  /// "1,234.5". Digits after the second decimal are rounded half-up.
  /// Anything unreadable is zero.
  static Paise parse(Object? amount) {
    final decimal = _Decimal.parse(amount);
    if (decimal == null) return zero;
    return Paise(_roundDiv(decimal.units * _hundred, decimal.denominator));
  }

  /// [value] / 100 as a number: for display and the JSON sent to the server.
  double get inRupees => value / 100;

  Paise operator +(Paise other) => Paise(value + other.value);
  Paise operator -(Paise other) => Paise(value - other.value);
  Paise operator -() => Paise(-value);
  bool operator <(Paise other) => value < other.value;
  bool operator >(Paise other) => value > other.value;
  bool operator <=(Paise other) => value <= other.value;
  bool operator >=(Paise other) => value >= other.value;
  bool get isZero => value == 0;
  bool get isNegative => value < 0;

  /// Rounded to the whole rupee, half-up (rule 6).
  Paise roundedToRupee() =>
      Paise(_roundDiv(BigInt.from(value), _hundred) * 100);

  /// Half of this amount, rounded half-up to the paisa.
  Paise get half => Paise(_roundDiv(BigInt.from(value), BigInt.two));

  /// CGST share of a tax amount: half, rounded half-up (rule 3).
  Paise get cgstShare => half;

  /// SGST share: the tax less the CGST share, so they add up exactly.
  Paise get sgstShare => this - cgstShare;

  static Paise sum(Iterable<Paise> amounts) =>
      amounts.fold(zero, (total, amount) => total + amount);
}

/// One line's amounts under the rounding rule (rules 1, 2 and 4).
class LineMoney {
  const LineMoney({required this.taxable, required this.tax});

  /// From the typed quantity, rate and GST % (numbers or text). An empty or
  /// unreadable value counts as zero. Each is first rounded half-up to the
  /// places the database stores (quantity 3, rate 2, GST % 2), so the app
  /// and the server always start from the same numbers.
  factory LineMoney.of({
    required Object? quantity,
    required Object? rate,
    Object? gstRate,
  }) {
    final q = (_Decimal.parse(quantity) ?? _Decimal.zero).rounded(3);
    final r = (_Decimal.parse(rate) ?? _Decimal.zero).rounded(2);
    final g = (_Decimal.parse(gstRate) ?? _Decimal.zero).rounded(2);
    final taxable = _roundDiv(
      q.units * r.units * _hundred,
      q.denominator * r.denominator,
    );
    final tax = _roundDiv(
      BigInt.from(taxable) * g.units,
      _hundred * g.denominator,
    );
    return LineMoney(taxable: Paise(taxable), tax: Paise(tax));
  }

  final Paise taxable;
  final Paise tax;
  Paise get total => taxable + tax;
  Paise cgst({required bool intraState}) =>
      intraState ? tax.cgstShare : Paise.zero;
  Paise sgst({required bool intraState}) =>
      intraState ? tax.sgstShare : Paise.zero;
  Paise igst({required bool intraState}) => intraState ? Paise.zero : tax;
}

/// A document's totals as sums of its lines (rules 5 and 6).
class DocumentMoney {
  DocumentMoney(Iterable<LineMoney> lines, {required this.intraState})
    : lines = List.unmodifiable(lines);

  final List<LineMoney> lines;
  final bool intraState;

  Paise get subtotal => Paise.sum(lines.map((line) => line.taxable));
  Paise get tax => Paise.sum(lines.map((line) => line.tax));
  Paise get cgst => Paise.sum(lines.map((l) => l.cgst(intraState: intraState)));
  Paise get sgst => Paise.sum(lines.map((l) => l.sgst(intraState: intraState)));
  Paise get igst => Paise.sum(lines.map((l) => l.igst(intraState: intraState)));

  /// Subtotal plus tax, before rounding to the rupee.
  Paise get exactTotal => subtotal + tax;

  /// The total payable, rounded to the rupee.
  Paise get payable => exactTotal.roundedToRupee();
  Paise get roundOff => payable - exactTotal;
}

final _hundred = BigInt.from(100);

/// n ÷ d rounded half away from zero (d > 0).
int _roundDiv(BigInt n, BigInt d) {
  final twice = n.abs() * BigInt.two + d;
  final magnitude = twice ~/ (d * BigInt.two);
  return (n.isNegative ? -magnitude : magnitude).toInt();
}

/// An exact decimal: [units] ÷ 10^scale.
class _Decimal {
  const _Decimal(this.units, this.scale);
  static final zero = _Decimal(BigInt.zero, 0);
  final BigInt units;
  final int scale;
  BigInt get denominator => BigInt.from(10).pow(scale);

  /// Rounded half away from zero to at most [places] decimals.
  _Decimal rounded(int places) {
    if (scale <= places) return this;
    final divisor = BigInt.from(10).pow(scale - places);
    return _Decimal(BigInt.from(_roundDiv(units, divisor)), places);
  }

  static _Decimal? parse(Object? value) {
    if (value == null) return null;
    if (value is int) return _Decimal(BigInt.from(value), 0);
    var text = value.toString().trim().replaceAll(',', '');
    if (value is double) {
      if (!value.isFinite) return null;
      // The shortest text that reads back as this double: 2.53, not
      // 2.529999…; long fractions are fine because they round later.
      text = value.toString();
      if (text.contains('e') || text.contains('E')) {
        text = value.toStringAsFixed(6);
      }
    }
    final match = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$').firstMatch(text);
    if (match == null) return null;
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    if (whole.isEmpty && fraction.isEmpty) return null;
    final units = BigInt.parse('${whole.isEmpty ? '0' : whole}$fraction');
    return _Decimal(match.group(1) == '-' ? -units : units, fraction.length);
  }
}

/// Amount in whole paise, avoiding floating-point noise such as 2799.9899.
int toPaise(num amount) => Paise.parse(amount).value;

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

/// Sent with each invoice save so the server checks the amounts strictly
/// against the same rule (see `save_invoice`).
const moneyRuleVersion = 'paise-v1';
