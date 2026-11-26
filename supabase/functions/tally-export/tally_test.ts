/**
 * The Tally export, from the kit's tests (tests/tally.test.ts TL7a-TL7i and
 * TL6, tests/tally-06.test.excerpt.ts): every assertion that applies to
 * Simplek is kept, on Simplek's data, plus the Simplek cases (several GST
 * rates, services, inter-state, a business without GST, partial payments,
 * round off, same-name customers, deleted after export, "Ledger lines only").
 *
 * Runs with Node 22+ (`node --test supabase/functions/tally-export/`) and
 * with Deno (`deno test`): node:test and node:assert work in both.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { escapeHtml, tallyExport, tallyFileName, tallyLedgers, type ExportData } from './tally.ts';
import { customer, gstBusiness, invoice, item, nonGstBusiness, payment } from './fixtures.ts';

/** The vouchers of a Tally file, each with the sum of its top-level amounts (Tally needs zero). The kit's helper. */
function vouchers(xml: string) {
  return [...xml.matchAll(/<VOUCHER(?: REMOTEID="([^"]+)")? VCHTYPE="([^"]+)"[\s\S]*?<\/VOUCHER>/g)].map((m) => {
    const body = m[0].replace(/<BILLALLOCATIONS\.LIST>[\s\S]*?<\/BILLALLOCATIONS\.LIST>/g, '').replace(/<ACCOUNTINGALLOCATIONS\.LIST>[\s\S]*?<\/ACCOUNTINGALLOCATIONS\.LIST>/g, '');
    const amounts = [...body.matchAll(/<AMOUNT>(-?[\d.]+)<\/AMOUNT>/g)].map((a) => Math.round(Number(a[1]) * 100));
    return { guid: m[1], type: m[2], text: m[0], balance: amounts.reduce((a, b) => a + b, 0), number: /<VOUCHERNUMBER>([^<]+)</.exec(m[0])![1] };
  });
}

/** Well-formed XML: every tag closes in order. The kit's helper. */
function wellFormed(xml: string) {
  const stack: string[] = [];
  for (const m of xml.replace(/<\?xml[^>]*\?>/, '').matchAll(/<(\/?)([A-Za-z][\w.:-]*)[^>]*?(\/?)>/g)) {
    if (m[3]) continue;
    if (!m[1]) stack.push(m[2]);
    else if (stack.pop() !== m[2]) return false;
  }
  return stack.length === 0;
}

const find = (xml: string, number: string) => vouchers(xml).find((v) => v.number === number)!;

test('TL6/TL7g: well formed, and every voucher balances to 0.00', () => {
  for (const data of [gstBusiness(), nonGstBusiness()]) {
    const { xml } = tallyExport(data);
    assert.ok(wellFormed(xml));
    const vs = vouchers(xml);
    assert.ok(vs.length > 0);
    for (const v of vs) assert.equal(v.balance, 0, `${v.type} ${v.number}`);
  }
});

test('TL7a: receipts are accounting-view vouchers with both lines as ALLLEDGERENTRIES.LIST, against the bill; cash, UPI and bank', () => {
  const { xml } = tallyExport(gstBusiness(), ['receipts']);
  const vs = vouchers(xml);
  assert.equal(vs.length, 3);
  for (const v of vs) {
    assert.equal(v.type, 'Receipt');
    assert.ok(v.text.includes('OBJVIEW="Accounting Voucher View"'));
    assert.ok(v.text.includes('<PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>'));
    assert.ok(!v.text.includes('<LEDGERENTRIES.LIST>'));
    assert.equal([...v.text.matchAll(/<ALLLEDGERENTRIES\.LIST>/g)].length, 2);
    assert.equal(v.balance, 0);
  }
  const cash = find(xml, 'R-INV/2026-27/01-1');
  assert.match(cash.text, /<ALLLEDGERENTRIES.LIST><LEDGERNAME>Kiran Traders<\/LEDGERNAME><ISDEEMEDPOSITIVE>No<\/ISDEEMEDPOSITIVE><AMOUNT>1000.00<\/AMOUNT><BILLALLOCATIONS.LIST><NAME>INV\/2026-27\/01<\/NAME><BILLTYPE>Agst Ref<\/BILLTYPE>/);
  assert.match(cash.text, /<ALLLEDGERENTRIES.LIST><LEDGERNAME>Cash<\/LEDGERNAME><ISDEEMEDPOSITIVE>Yes<\/ISDEEMEDPOSITIVE><AMOUNT>-1000.00<\/AMOUNT><\/ALLLEDGERENTRIES.LIST>/);
  assert.ok(find(xml, 'R-INV/2026-27/01-2').text.includes('<LEDGERNAME>UPI receipts</LEDGERNAME>'));
  assert.ok(find(xml, 'R-INV/2026-27/04-1').text.includes('<LEDGERNAME>Bank</LEDGERNAME>'));
});

test('TL7b + Simplek: an unpaid sale stays outstanding (New Ref); two partial payments are two receipts that add up to the bill', () => {
  const data = gstBusiness();
  const { xml } = tallyExport(data);
  const unpaid = find(xml, 'INV/2026-27/02');
  assert.match(unpaid.text, /<BILLTYPE>New Ref<\/BILLTYPE><BILLCREDITPERIOD>7 Days<\/BILLCREDITPERIOD><AMOUNT>-1770.00<\/AMOUNT>/);
  assert.ok(!vouchers(xml).some((v) => v.type === 'Receipt' && v.text.includes('<NAME>INV/2026-27/02</NAME>')));
  const billed = Number(/<BILLTYPE>New Ref<\/BILLTYPE><BILLCREDITPERIOD>7 Days<\/BILLCREDITPERIOD><AMOUNT>-([\d.]+)<\/AMOUNT>/.exec(find(xml, 'INV/2026-27/01').text)![1]);
  const received = ['R-INV/2026-27/01-1', 'R-INV/2026-27/01-2']
    .map((n) => Number(/<BILLTYPE>Agst Ref<\/BILLTYPE><AMOUNT>([\d.]+)<\/AMOUNT>/.exec(find(xml, n).text)![1]))
    .reduce((a, b) => a + b, 0);
  assert.equal(received.toFixed(2), billed.toFixed(2));
  // The credit period is the invoice's own due date; none without one.
  assert.ok(!find(xml, 'INV/2026-27/05').text.includes('<BILLCREDITPERIOD>'));
});

test('TL7c: no purchases, no supplier masters, no 0-amount vouchers or lines', () => {
  const data = gstBusiness();
  data.invoices.push(invoice('99999999-9999-9999-9999-999999999999', 'INV/2026-27/99', [item({ taxable: 0, rate: 18 })], { total_amount: 0 }));
  data.payments.push(payment('ccccccc1-0000-0000-0000-000000000001', data.invoices[0], 0, 9));
  const { xml } = tallyExport(data);
  assert.ok(!xml.includes('VCHTYPE="Purchase"'));
  assert.ok(!xml.includes('Sundry Creditors'));
  assert.ok(!xml.includes('INV/2026-27/99'));
  assert.ok(!xml.includes('R-INV/2026-27/01-9'));
  for (const v of vouchers(xml)) {
    assert.doesNotMatch(v.text, /<LEDGERENTRIES\.LIST><LEDGERNAME>[^<]+<\/LEDGERNAME><ISDEEMEDPOSITIVE>(Yes|No)<\/ISDEEMEDPOSITIVE><AMOUNT>-?0\.00<\/AMOUNT>/);
  }
});

test('TL7d: stable REMOTEID/GUID from the database ID; "already exported on" per voucher; re-export keeps the same IDs', () => {
  const first = tallyExport(gstBusiness());
  const second = tallyExport(gstBusiness());
  const sale = find(first.xml, 'INV/2026-27/01');
  assert.equal(sale.guid, 'simplek-sales-11111111-1111-1111-1111-111111111111');
  assert.ok(sale.text.includes('<GUID>simplek-sales-11111111-1111-1111-1111-111111111111</GUID>'));
  assert.equal(find(first.xml, 'R-INV/2026-27/01-1').guid, 'simplek-receipt-aaaaaaa1-0000-0000-0000-000000000001');
  assert.deepEqual(vouchers(second.xml).map((v) => v.guid), vouchers(first.xml).map((v) => v.guid));
  const guids = vouchers(first.xml).map((v) => v.guid);
  assert.equal(new Set(guids).size, guids.length);
  const listed = first.summary.list.find((v) => v.number === 'INV/2026-27/01')!;
  assert.equal(listed.exportedAt, '2026-11-21T05:00:00Z');
  assert.equal(first.summary.list.find((v) => v.number === 'INV/2026-27/02')!.exportedAt, null);
});

test('TL7e: masters before the vouchers, created only if missing: customers, rate-wise sales and Duties & Taxes, Round Off, Cash, Bank and UPI', () => {
  const { xml } = tallyExport(gstBusiness());
  const masters = xml.slice(0, xml.indexOf('<REPORTNAME>Vouchers</REPORTNAME>'));
  const m = (name: string, parent: string) =>
    assert.match(masters, new RegExp(`<LEDGER NAME="${name.replace(/[()%.]/g, '\\$&')}" ACTION="Create"><NAME.LIST><NAME>[^<]+</NAME></NAME.LIST><PARENT>${parent}</PARENT>`));
  m('Sales GST 5% Local', 'Sales Accounts');
  m('Sales GST 18% Local', 'Sales Accounts');
  m('Sales GST 12% Interstate', 'Sales Accounts');
  m('Service Sales GST 18% Local', 'Sales Accounts');
  m('Output CGST 2.5%', 'Duties &amp; Taxes');
  m('Output SGST 2.5%', 'Duties &amp; Taxes');
  m('Output CGST 9%', 'Duties &amp; Taxes');
  m('Output SGST 9%', 'Duties &amp; Taxes');
  m('Output IGST 12%', 'Duties &amp; Taxes');
  m('Round Off', 'Indirect Expenses');
  m('Cash', 'Cash-in-Hand');
  m('Bank', 'Bank Accounts');
  m('UPI receipts', 'Bank Accounts');
  assert.match(masters, /<LEDGER NAME="Kiran Traders" ACTION="Create"><NAME.LIST><NAME>[^<]+<\/NAME><\/NAME.LIST><PARENT>Sundry Debtors<\/PARENT>/);
  assert.match(masters, /<LEDGER NAME="Service Sales GST 18% Local" ACTION="Create">.*?<GSTTYPEOFSUPPLY>Services<\/GSTTYPEOFSUPPLY>/);
  assert.match(masters, /<GSTDUTYHEAD>Central Tax<\/GSTDUTYHEAD>/);
  assert.ok(!masters.includes('<VOUCHER'));
  // No discounts in Simplek yet: the Discount Allowed master stays out (T2.7).
  assert.ok(!masters.includes('Discount Allowed'));
  // Units first, then stock items with HSN and the GST rate.
  assert.ok(masters.indexOf('<UNIT NAME="Nos"') < masters.indexOf('<STOCKITEM'));
  assert.match(masters, /<STOCKITEM NAME="Tea 1 kg" ACTION="Create"><NAME.LIST><NAME>Tea 1 kg<\/NAME><\/NAME.LIST><BASEUNITS>Kgs<\/BASEUNITS>.*?<HSNCODE>0902<\/HSNCODE>.*?<GSTRATE>2.5<\/GSTRATE>.*?<GSTRATE>2.5<\/GSTRATE>.*?<GSTRATE>5<\/GSTRATE>/);
  assert.match(masters, /<STOCKITEM NAME="Steel Chair" ACTION="Create">.*?<HSNCODE>94017100<\/HSNCODE>.*?<GSTRATE>9<\/GSTRATE>.*?<GSTRATE>9<\/GSTRATE>.*?<GSTRATE>18<\/GSTRATE>/);
  // Services are not stock items.
  assert.ok(!masters.includes('<STOCKITEM NAME="Installation"'));
});

test('TL7f: every ledger name comes from the settings (per business)', () => {
  const data = gstBusiness();
  data.settings = {
    company: 'Malnad Kitchen Pvt Ltd',
    ledgers: { cash: 'Cash Box', upi: 'SBI UPI' },
    rates: { '12': { igst: 'IGST Out 12' }, '18': { salesLocal: 'Sales 18 KA' } },
    units: { KGS: 'Kg' },
  };
  const { xml } = tallyExport(data);
  assert.ok(xml.includes('<SVCURRENTCOMPANY>Malnad Kitchen Pvt Ltd</SVCURRENTCOMPANY>'));
  for (const name of ['IGST Out 12', 'Cash Box', 'SBI UPI', 'Sales 18 KA']) {
    assert.ok(xml.includes(`<LEDGERNAME>${name}</LEDGERNAME>`), name);
    assert.ok(xml.includes(`<LEDGER NAME="${name}" ACTION="Create">`), name);
  }
  assert.ok(xml.includes('<UNIT NAME="Kg" ACTION="Create">'));
  assert.ok(xml.includes('<RATE>500.00/Kg</RATE>'));
  // The company name defaults to the business name.
  assert.ok(tallyExport(gstBusiness()).xml.includes('<SVCURRENTCOMPANY>Malnad Kitchen</SVCURRENTCOMPANY>'));
});

test('TL7g: RATE is the unit price, AMOUNT the invoice line value (not rate x quantity); inter-state uses the interstate ledger and IGST; the summary equals the reports', () => {
  const data = gstBusiness();
  const { xml } = tallyExport(data);
  const mixed = find(xml, 'INV/2026-27/03');
  // 3 x 333.33 = 999.99 on the invoice: the line value, not 999.99 recomputed.
  assert.ok(mixed.text.includes('<RATE>333.33/Nos</RATE><AMOUNT>999.99</AMOUNT><ACTUALQTY> 3 Nos</ACTUALQTY><BILLEDQTY> 3 Nos</BILLEDQTY>'));
  const inter = find(xml, 'INV/2026-27/04');
  assert.ok(inter.text.includes('<LEDGERNAME>Sales GST 12% Interstate</LEDGERNAME>'));
  assert.ok(inter.text.includes('<LEDGERNAME>Output IGST 12%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>360.00</AMOUNT>'));
  assert.ok(!inter.text.includes('CGST'));
  assert.ok(inter.text.includes('<PLACEOFSUPPLY>Kerala</PLACEOFSUPPLY>'));
  // matchesReports against Simplek's Reports for the same dates.
  const s = tallyExport(data).summary;
  data.report = { invoices: 6, taxable: s.taxablePaise / 100, cgst: s.cgstPaise / 100, sgst: s.sgstPaise / 100, igst: s.igstPaise / 100, total: s.totalPaise / 100 };
  assert.equal(tallyExport(data).summary.matchesReports, true);
  data.report = { ...data.report, total: s.totalPaise / 100 + 1 };
  assert.equal(tallyExport(data).summary.matchesReports, false);
});

test('Simplek: a mixed 5% + 18% invoice has one tax line per rate; CGST and SGST per rate are sums of the lines', () => {
  const v = find(tallyExport(gstBusiness()).xml, 'INV/2026-27/01');
  assert.ok(v.text.includes('<LEDGERNAME>Output CGST 2.5%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>25.00</AMOUNT>'));
  assert.ok(v.text.includes('<LEDGERNAME>Output SGST 2.5%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>25.00</AMOUNT>'));
  assert.ok(v.text.includes('<LEDGERNAME>Output CGST 9%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>180.00</AMOUNT>'));
  assert.ok(v.text.includes('<LEDGERNAME>Output SGST 9%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>180.00</AMOUNT>'));
  assert.ok(v.text.includes('<ACCOUNTINGALLOCATIONS.LIST><LEDGERNAME>Sales GST 5% Local</LEDGERNAME>'));
  assert.ok(v.text.includes('<ACCOUNTINGALLOCATIONS.LIST><LEDGERNAME>Sales GST 18% Local</LEDGERNAME>'));
  assert.ok(v.text.includes('<PARTYGSTIN>29AAGCB7383J1Z4</PARTYGSTIN>'));
  assert.equal(v.balance, 0);
});

test('Simplek: services are ledger lines, not stock items; a mixed goods-and-services invoice has both', () => {
  const { xml } = tallyExport(gstBusiness());
  const services = find(xml, 'INV/2026-27/02');
  assert.ok(!services.text.includes('<ALLINVENTORYENTRIES.LIST>'));
  assert.ok(services.text.includes('<LEDGERENTRIES.LIST><LEDGERNAME>Service Sales GST 18% Local</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>1500.00</AMOUNT></LEDGERENTRIES.LIST>'));
  const mixed = find(xml, 'INV/2026-27/03');
  assert.ok(mixed.text.includes('<STOCKITEMNAME>Steel Chair</STOCKITEMNAME>'));
  assert.ok(mixed.text.includes('<LEDGERNAME>Service Sales GST 18% Local</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>500.00</AMOUNT>'));
  for (const v of [services, mixed]) assert.equal(v.balance, 0);
});

test('Simplek: round off goes to the Round Off ledger (5% on Rs 101 = Rs 106)', () => {
  const v = find(tallyExport(gstBusiness()).xml, 'INV/2026-27/05');
  assert.ok(v.text.includes('<AMOUNT>-106.00</AMOUNT>'));
  assert.ok(v.text.includes('<LEDGERNAME>Output CGST 2.5%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>2.53</AMOUNT>'));
  assert.ok(v.text.includes('<LEDGERNAME>Output SGST 2.5%</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>2.52</AMOUNT>'));
  // 101 + 5.05 = 106.05, rounded to 106: the 0.05 is a debit to Round Off.
  assert.ok(v.text.includes('<LEDGERENTRIES.LIST><LEDGERNAME>Round Off</LEDGERNAME><ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE><AMOUNT>-0.05</AMOUNT></LEDGERENTRIES.LIST>'));
  assert.equal(v.balance, 0);
});

test('Simplek (rule 10): two customers with the same name get their mobile added; two products with the same name their HSN', () => {
  const { xml } = tallyExport(gstBusiness());
  assert.ok(xml.includes('<LEDGER NAME="Asha Rao (9876500002)" ACTION="Create">'));
  assert.ok(xml.includes('<LEDGER NAME="Asha Rao (9876500003)" ACTION="Create">'));
  assert.ok(find(xml, 'INV/2026-27/02').text.includes('<PARTYLEDGERNAME>Asha Rao (9876500002)</PARTYLEDGERNAME>'));
  assert.ok(xml.includes('<STOCKITEM NAME="Bolt (73181500)" ACTION="Create">'));
  assert.ok(xml.includes('<STOCKITEM NAME="Bolt (73181600)" ACTION="Create">'));
  // A single customer keeps the plain name.
  assert.ok(xml.includes('<LEDGER NAME="Kiran Traders" ACTION="Create">'));
});

test('Simplek: a business without GST: one Sales ledger, GST "Not Applicable", no tax, Unregistered/Consumer, no PARTYGSTIN or PLACEOFSUPPLY', () => {
  const { xml } = tallyExport(nonGstBusiness());
  assert.ok(xml.includes('<LEDGER NAME="Sales" ACTION="Create"><NAME.LIST><NAME>Sales</NAME></NAME.LIST><PARENT>Sales Accounts</PARENT><GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE>'));
  assert.ok(xml.includes('<STOCKITEM NAME="Steel Chair" ACTION="Create"><NAME.LIST><NAME>Steel Chair</NAME></NAME.LIST><BASEUNITS>Nos</BASEUNITS><GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE></STOCKITEM>'));
  for (const no of ['Duties &amp; Taxes', 'CGST', 'SGST', 'IGST', '<PARTYGSTIN>', '<PLACEOFSUPPLY>', 'GSTDETAILS']) assert.ok(!xml.includes(no), no);
  assert.ok(xml.includes('<GSTREGISTRATIONTYPE>Unregistered/Consumer</GSTREGISTRATIONTYPE>'));
  const v = find(xml, 'BILL/2026-27/01');
  assert.ok(v.text.includes('<LEDGERNAME>Sales</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>300.00</AMOUNT>'));
  assert.equal(v.balance, 0);
});

test('Simplek (T2.9): "Ledger lines only" writes every line to the rate-wise sales ledgers, no stock items or units', () => {
  const data = gstBusiness();
  data.settings = { itemsAs: 'ledger' };
  const { xml } = tallyExport(data);
  assert.ok(!xml.includes('<STOCKITEM'));
  assert.ok(!xml.includes('<UNIT '));
  assert.ok(!xml.includes('<ALLINVENTORYENTRIES.LIST>'));
  const v = find(xml, 'INV/2026-27/01');
  assert.ok(v.text.includes('<LEDGERENTRIES.LIST><LEDGERNAME>Sales GST 5% Local</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>1000.00</AMOUNT></LEDGERENTRIES.LIST>'));
  assert.ok(v.text.includes('<LEDGERENTRIES.LIST><LEDGERNAME>Sales GST 18% Local</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>2000.00</AMOUNT></LEDGERENTRIES.LIST>'));
  for (const each of vouchers(xml)) assert.equal(each.balance, 0, each.number);
});

test('Simplek (T2.12): a deleted invoice that was exported gives the warning and is not in the file', () => {
  const { xml, summary } = tallyExport(gstBusiness());
  assert.deepEqual(summary.exportedThenDeleted, [{ number: 'INV/2026-27/00', issuedAt: '2026-11-19', exportedAt: '2026-11-20T06:00:00Z' }]);
  assert.ok(!xml.includes('<VOUCHERNUMBER>INV/2026-27/00</VOUCHERNUMBER>'));
});

test('TL6: the summary counts vouchers, quantity, taxable value, tax, total and receipts', () => {
  const { summary } = tallyExport(gstBusiness());
  assert.equal(summary.vouchers.total, summary.vouchers.sales + summary.vouchers.receipts + summary.vouchers.creditNotes);
  assert.deepEqual(summary.vouchers, { sales: 6, receipts: 3, creditNotes: 0, total: 9 });
  assert.equal(summary.taxablePaise, (1000 + 2000 + 1500 + 999.99 + 500 + 3000 + 101 + 200) * 100);
  assert.equal(summary.cgstPaise + summary.sgstPaise + summary.igstPaise, (50 + 360 + 270 + 180 + 90 + 360 + 5.05 + 36) * 100);
  assert.equal(summary.receiptsPaise, 3410 * 100 + 3360 * 100);
  assert.equal(summary.quantity.sold, 2 + 4 + 1 + 3 + 1 + 1 + 1 + 1 + 1);
});

test('rule 9: XML escaping of every text value; the file name', () => {
  assert.equal(escapeHtml(`A & B <C> "D" 'E'`), 'A &amp; B &lt;C&gt; &quot;D&quot; &#39;E&#39;');
  const data = gstBusiness();
  data.invoices[1] = { ...data.invoices[1], customer_name: 'Shah & Sons <HQ>', customer: customer('Shah & Sons <HQ>', { phone: '9876500077' }) };
  const { xml } = tallyExport(data);
  assert.ok(wellFormed(xml));
  assert.ok(xml.includes('<LEDGER NAME="Shah &amp; Sons &lt;HQ&gt;" ACTION="Create">'));
  assert.equal(tallyFileName('Malnad Kitchen & Co.', '2026-11-01', '2026-11-30'), 'Tally_Malnad_Kitchen_Co_2026-11-01_2026-11-30.xml');
});

test('the settings: saved names over the standard ones, per rate and per unit', () => {
  const N = tallyLedgers({ ledgers: { cash: ' Cash Box ' }, rates: { '18': { cgst: 'CGST 9 Out' } }, units: { KGS: 'Kg' } });
  assert.equal(N.L.cash, 'Cash Box');
  assert.equal(N.L.bank, 'Bank');
  assert.equal(N.rate(18).cgst, 'CGST 9 Out');
  assert.equal(N.rate(18).sgst, 'Output SGST 9%');
  assert.equal(N.rate(0.25).igst, 'Output IGST 0.25%');
  assert.equal(N.rate(0.25).cgst, 'Output CGST 0.13%');
  assert.equal(N.unit('KGS'), 'Kg');
  assert.equal(N.unit('NOS'), 'Nos');
  assert.equal(N.unit(null), 'Nos');
  assert.equal(N.itemsAs, 'stock');
});

test('the structure matches the kit samples: same tags, in the same order, same signs', () => {
  const kit = readFileSync(new URL('../../../docs/reference/tally-integration-kit/samples/Tally-sample-export.xml', import.meta.url), 'utf8');
  const shape = (voucher: string) =>
    [...voucher.matchAll(/<([A-Z][A-Z.]*)[ >]/g)].map((m) => m[1]).filter((t, i, all) => t !== all[i - 1]).join(' ');
  // A one-item, one-rate, intra-state Simplek sale has the kit's sale shape
  // (no PARTYGSTIN, no discount, no round off).
  const kitSale = vouchers(kit).find((v) => v.number === 'INV/2026-27/02')!.text.replace(/<LEDGERENTRIES\.LIST><LEDGERNAME>Discount Allowed[\s\S]*?<\/LEDGERENTRIES\.LIST>/, '');
  const one: ExportData = { ...gstBusiness(), invoices: [invoice('12121212-1212-1212-1212-121212121212', 'INV/2026-27/10', [item({ taxable: 1000, rate: 5, quantity: 2, unit_price: 500 })])], payments: [] };
  const ours = vouchers(tallyExport(one).xml)[0].text;
  assert.equal(shape(ours), shape(kitSale));
  // The receipt shape is the kit's corrected receipt.
  const kitReceipt = vouchers(kit).find((v) => v.type === 'Receipt')!.text;
  const ourReceipt = find(tallyExport(gstBusiness(), ['receipts']).xml, 'R-INV/2026-27/01-1').text;
  assert.equal(shape(ourReceipt), shape(kitReceipt));
  // Envelope: masters block, then vouchers block, both with SVCURRENTCOMPANY.
  const head = (xml: string) => xml.split('\n').map((l) => l.replace(/<SVCURRENTCOMPANY>[^<]*</, '<SVCURRENTCOMPANY><').slice(0, 120)).filter((l) => !l.startsWith('<TALLYMESSAGE')).join('\n');
  assert.equal(head(tallyExport(gstBusiness()).xml), head(kit));
});
