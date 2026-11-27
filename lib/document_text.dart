/// Simplek's website, linked from the word "Simplek" in every PDF footer
/// (change request 26 Nov 2026, invoice footer). Change it only here.
const kSimplekWebsite = 'https://simplek.in';

String? validateDocumentNumber(String? value) {
  final number = value?.trim() ?? '';
  if (number.isEmpty) return null;
  return RegExp(r'^[A-Za-z0-9/-]{1,40}$').hasMatch(number)
      ? null
      : 'Use up to 40 letters, digits, / or -';
}

/// Indian numbering, rounded to the same two decimals printed on documents.
String amountInWords(double amount) {
  if (!amount.isFinite || amount < 0) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Must be finite and non-negative',
    );
  }
  final parts = amount.toStringAsFixed(2).split('.');
  final rupees = int.parse(parts[0]);
  final paise = int.parse(parts[1]);
  return 'Rupees ${_numberWords(rupees)}${paise == 0 ? '' : ' and ${_numberWords(paise)} Paise'} Only';
}

String _numberWords(int n) {
  const small = [
    'Zero',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  const tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];
  if (n < 20) return small[n];
  if (n < 100) {
    return '${tens[n ~/ 10]}${n % 10 == 0 ? '' : ' ${small[n % 10]}'}';
  }
  for (final scale in const {
    10000000: 'Crore',
    100000: 'Lakh',
    1000: 'Thousand',
    100: 'Hundred',
  }.entries) {
    if (n >= scale.key) {
      return '${_numberWords(n ~/ scale.key)} ${scale.value}${n % scale.key == 0 ? '' : ' ${_numberWords(n % scale.key)}'}';
    }
  }
  throw StateError('Unreachable amount');
}

String customerBillingDetails({
  required String name,
  String address = '',
  String gstin = '',
  String phone = '',
}) => [
  name.trim(),
  if (address.trim().isNotEmpty) address.trim(),
  if (gstin.trim().isNotEmpty) 'GSTIN: ${gstin.trim().toUpperCase()}',
  if (phone.trim().isNotEmpty) 'Phone: ${phone.trim()}',
].join('\n');

String finalizedInvoiceStatus(double total, double paid) => paid >= total
    ? 'paid'
    : paid > 0
    ? 'partial'
    : 'sent';
