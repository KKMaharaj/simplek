// CR-25B B3: money in integer paise and the one rounding rule (lib/money.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:simplek/money.dart';

Paise _p(String rupees) => Paise.parse(rupees);

void main() {
  group('Paise.parse', () {
    test('reads text and numbers exactly', () {
      expect(Paise.parse('2.53').value, 253);
      expect(Paise.parse(2.53).value, 253);
      expect(Paise.parse(2799.99).value, 279999);
      expect(Paise.parse('1,25,00,000').value, 1250000000);
      expect(Paise.parse(12500000).value, 1250000000);
      expect(Paise.parse('.5').value, 50);
      expect(Paise.parse('-0.40').value, -40);
    });

    test('rounds a third decimal half-up', () {
      expect(Paise.parse('2.525').value, 253);
      expect(Paise.parse('2.524').value, 252);
      expect(Paise.parse('0.005').value, 1);
      expect(Paise.parse('-2.525').value, -253);
    });

    test('anything unreadable is zero', () {
      for (final value in [null, '', 'abc', '1.2.3', double.nan]) {
        expect(Paise.parse(value), Paise.zero, reason: '$value');
      }
    });
  });

  group('the rounding rule', () {
    test('5% on ₹101: CGST and SGST add up to the tax', () {
      final line = LineMoney.of(quantity: 1, rate: '101', gstRate: 5);
      expect(line.taxable, _p('101'));
      expect(line.tax, _p('5.05'));
      expect(line.cgst(intraState: true), _p('2.53'));
      expect(line.sgst(intraState: true), _p('2.52'));
      expect(
        line.cgst(intraState: true) + line.sgst(intraState: true),
        line.tax,
      );
      expect(line.igst(intraState: false), _p('5.05'));
      expect(line.cgst(intraState: false), Paise.zero);
      final money = DocumentMoney([line], intraState: true);
      expect(money.exactTotal, _p('106.05'));
      expect(money.payable, _p('106'));
      expect(money.roundOff, _p('-0.05'));
    });

    test('3 × ₹33.33 @ 18%', () {
      final line = LineMoney.of(quantity: '3', rate: '33.33', gstRate: '18');
      expect(line.taxable, _p('99.99'));
      // 99.99 × 18% = 17.9982 → ₹18.00
      expect(line.tax, _p('18.00'));
      expect(line.cgst(intraState: true), _p('9.00'));
      expect(line.sgst(intraState: true), _p('9.00'));
      final money = DocumentMoney([line], intraState: true);
      expect(money.exactTotal, _p('117.99'));
      expect(money.payable, _p('118'));
      expect(money.roundOff, _p('0.01'));
    });

    test('a 0% line has no tax', () {
      final line = LineMoney.of(quantity: '2', rate: '49.99', gstRate: '0');
      expect(line.taxable, _p('99.98'));
      expect(line.tax, Paise.zero);
      expect(line.total, _p('99.98'));
      final empty = LineMoney.of(quantity: '', rate: '', gstRate: '');
      expect(empty.total, Paise.zero);
    });

    test('a mixed-rate invoice is the sum of its lines', () {
      final lines = [
        LineMoney.of(quantity: 1, rate: '101', gstRate: 5),
        LineMoney.of(quantity: 3, rate: '33.33', gstRate: 18),
        LineMoney.of(quantity: '1.5', rate: '250.10', gstRate: 12),
        LineMoney.of(quantity: 1, rate: '101', gstRate: 5),
        LineMoney.of(quantity: 4, rate: '12.5', gstRate: 0),
      ];
      // 1.5 × 250.10 = 375.15; 12% = 45.018 → 45.02
      expect(lines[2].taxable, _p('375.15'));
      expect(lines[2].tax, _p('45.02'));
      final money = DocumentMoney(lines, intraState: true);
      expect(money.subtotal, _p('727.14'));
      expect(money.tax, _p('73.12'));
      // CGST is the sum of each line's half, not half of the total.
      expect(money.cgst, _p('2.53') + _p('9.00') + _p('22.51') + _p('2.53'));
      expect(money.cgst + money.sgst, money.tax);
      expect(money.igst, Paise.zero);
      expect(money.exactTotal, _p('800.26'));
      expect(money.payable, _p('800'));
      expect(money.roundOff, _p('-0.26'));
      final igst = DocumentMoney(lines, intraState: false);
      expect(igst.igst, money.tax);
      expect(igst.cgst + igst.sgst, Paise.zero);
    });

    test('a ₹1.25 crore invoice stays exact', () {
      final line = LineMoney.of(
        quantity: '2.5',
        rate: '5000000.40',
        gstRate: '18',
      );
      expect(line.taxable, _p('12500001.00'));
      expect(line.tax, _p('2250000.18'));
      expect(line.cgst(intraState: true), _p('1125000.09'));
      expect(line.sgst(intraState: true), _p('1125000.09'));
      final money = DocumentMoney([line], intraState: true);
      expect(money.exactTotal, _p('14750001.18'));
      expect(money.payable, _p('14750001'));
      expect(rupees(money.payable.inRupees), '₹1,47,50,001.00');
    });

    test('inputs are rounded to the places the database stores', () {
      // Rate to the paisa, quantity to 3 places, GST % to 2 places.
      expect(
        LineMoney.of(quantity: 3, rate: '33.333', gstRate: 0).taxable,
        _p('99.99'),
      );
      expect(
        LineMoney.of(quantity: '1.0005', rate: '1000', gstRate: 0).taxable,
        _p('1001'),
      );
      expect(
        LineMoney.of(quantity: 1, rate: '1000', gstRate: '0.125').tax,
        _p('1.30'),
      );
    });

    test('round off: 50 paise and above go up', () {
      expect(_p('117.50').roundedToRupee(), _p('118'));
      expect(_p('117.49').roundedToRupee(), _p('117'));
      expect(roundToRupee(117.5), 118);
      expect(roundOffFor(117.49), -0.49);
    });

    test('an odd paisa of tax goes to CGST', () {
      for (final (tax, cgst, sgst) in [
        ('0.01', '0.01', '0.00'),
        ('0.03', '0.02', '0.01'),
        ('5.05', '2.53', '2.52'),
        ('18.00', '9.00', '9.00'),
      ]) {
        expect(_p(tax).cgstShare, _p(cgst), reason: tax);
        expect(_p(tax).sgstShare, _p(sgst), reason: tax);
      }
    });
  });
}
