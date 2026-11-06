import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/document_text.dart';

void main() {
  test(
    'optional Bill To fields are on separate lines without empty labels',
    () {
      expect(customerBillingDetails(name: ' Client '), 'Client');
      expect(
        customerBillingDetails(
          name: 'Client',
          address: 'Road\nMumbai',
          gstin: ' 27abc ',
          phone: '9876543210',
        ),
        'Client\nRoad\nMumbai\nGSTIN: 27ABC\nPhone: 9876543210',
      );
      expect(
        customerBillingDetails(name: 'Client', address: ' ', gstin: ' '),
        'Client',
      );
    },
  );
  test('amount words use Indian rupees, lakh, crore and paise', () {
    expect(amountInWords(0), 'Rupees Zero Only');
    expect(amountInWords(0.05), 'Rupees Zero and Five Paise Only');
    expect(amountInWords(1180), 'Rupees One Thousand One Hundred Eighty Only');
    expect(
      amountInWords(56640),
      'Rupees Fifty Six Thousand Six Hundred Forty Only',
    );
    expect(
      amountInWords(12345678.90),
      'Rupees One Crore Twenty Three Lakh Forty Five Thousand Six Hundred Seventy Eight and Ninety Paise Only',
    );
    expect(amountInWords(99.999), 'Rupees One Hundred Only');
    expect(() => amountInWords(-1), throwsArgumentError);
    expect(() => amountInWords(double.nan), throwsArgumentError);
  });
  test(
    'successful saves finalize new and edited invoices without losing payments',
    () {
      expect(finalizedInvoiceStatus(1180, 0), 'sent');
      expect(finalizedInvoiceStatus(1180, 500), 'partial');
      expect(finalizedInvoiceStatus(1180, 1180), 'paid');
      expect(finalizedInvoiceStatus(1000, 1180), 'paid');
      expect(finalizedInvoiceStatus(0, 0), 'paid');
    },
  );
}
