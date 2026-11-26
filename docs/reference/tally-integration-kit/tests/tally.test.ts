import { beforeAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import { prisma } from '../src/lib/prisma';
import { isoDay } from '../src/lib/dates';
import { unitPrice } from '../src/lib/gst';
import { correctInvoiceRate } from '../src/modules/billing/rate-fix';
import { mobile, staffAgent } from './helpers';
import { product } from './shop-helpers';

/** Change request 07 (CHANGES-07.md). The check names match TECHNICAL-SPEC section 12. */

let admin: request.Agent;
let accounts: request.Agent;
let adminId: string;

beforeAll(async () => {
  const a = await staffAgent('admin');
  admin = a.agent;
  adminId = a.staff.id;
  accounts = (await staffAgent('accounts')).agent;
});

const today = () => isoDay(new Date()); // the IST day, as the reports use

async function offlineInvoice(over: Record<string, unknown> = {}) {
  const p = await product();
  const body = {
    customer: { name: 'Store Customer', mobile: mobile(), email: null, address: '5, Market Road, Shivamogga' },
    delivery: 'courier',
    shipping: { line1: '5, Market Road', city: 'Shivamogga', district: 'Shivamogga', state: 'Karnataka', pincode: '577202' },
    sourceType: 'store',
    state: 'Karnataka',
    items: [{ productId: p.id, quantity: 2, rate: unitPrice(p).taxable / 100 }],
    paymentMode: 'Cash',
    ...over,
  };
  const r = await accounts.post('/api/staff/billing/offline-invoices').send(body);
  expect(r.status, JSON.stringify(r.body)).toBe(201);
  return r.body as { orderId: string; invoiceNumber: string };
}

/** A ₹3,500 bottle, as on the live site. */
const bottle = (tag: string) =>
  prisma.product.create({ data: { slug: `${tag}-${Date.now()}`, name: 'Rejwin', packSize: '1000 ml', hsnCode: '30049011', mrpPaise: 350000, mrpIncludesGst: true, gstPercent: 5, stock: 50, unitWeightGrams: 1200 } });

/** The vouchers of a Tally file, each with the sum of its top-level amounts (Tally needs zero). */
function vouchers(xml: string) {
  return [...xml.matchAll(/<VOUCHER REMOTEID="([^"]+)" VCHTYPE="([^"]+)"[\s\S]*?<\/VOUCHER>/g)].map((m) => {
    const body = m[0].replace(/<BILLALLOCATIONS\.LIST>[\s\S]*?<\/BILLALLOCATIONS\.LIST>/g, '').replace(/<ACCOUNTINGALLOCATIONS\.LIST>[\s\S]*?<\/ACCOUNTINGALLOCATIONS\.LIST>/g, '');
    const amounts = [...body.matchAll(/<AMOUNT>(-?[\d.]+)<\/AMOUNT>/g)].map((a) => Math.round(Number(a[1]) * 100));
    return { guid: m[1], type: m[2], text: m[0], balance: amounts.reduce((a, b) => a + b, 0), number: /<VOUCHERNUMBER>([^<]+)</.exec(m[0])![1] };
  });
}

function wellFormed(xml: string) {
  const stack: string[] = [];
  for (const m of xml.replace(/<\?xml[^>]*\?>/, '').matchAll(/<(\/?)([A-Za-z][\w.:-]*)[^>]*?(\/?)>/g)) {
    if (m[3]) continue;
    if (!m[1]) stack.push(m[2]);
    else if (stack.pop() !== m[2]) return false;
  }
  return stack.length === 0;
}

const tally = async (kinds?: string) => (await accounts.get(`/api/staff/billing/tally?from=${today()}&to=${today()}${kinds ? `&kinds=${kinds}` : ''}`)).text;

describe('change 07.3: the Tally export TallyPrime accepts', () => {
  it('TL7a: receipts are accounting-view vouchers with both lines as ALLLEDGERENTRIES.LIST, against the bill; cash and UPI', async () => {
    const rate = unitPrice(await product()).taxable / 100;
    const cash = await offlineInvoice({ items: [{ productId: (await product()).id, quantity: 1, rate }], paymentMode: 'Cash' });
    const upi = await offlineInvoice({ items: [{ productId: (await product()).id, quantity: 1, rate }], paymentMode: 'UPI' });
    const xml = await tally('receipts');
    expect(wellFormed(xml)).toBe(true);
    const vs = vouchers(xml);
    for (const v of vs) {
      expect(v.type).toBe('Receipt');
      expect(v.text).toContain('OBJVIEW="Accounting Voucher View"');
      expect(v.text).toContain('<PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>');
      expect(v.text).not.toContain('<LEDGERENTRIES.LIST>');
      expect([...v.text.matchAll(/<ALLLEDGERENTRIES\.LIST>/g)].length).toBe(2);
      expect(v.balance).toBe(0);
    }
    const c = vs.find((v) => v.number === `R-${cash.invoiceNumber}`)!;
    expect(c.text).toMatch(new RegExp(`<ALLLEDGERENTRIES.LIST><LEDGERNAME>Store Customer[^<]*</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>[\\d.]+</AMOUNT><BILLALLOCATIONS.LIST><NAME>${cash.invoiceNumber.replace(/\//g, '\\/')}</NAME><BILLTYPE>Agst Ref</BILLTYPE>`));
    expect(c.text).toMatch(/<ALLLEDGERENTRIES.LIST><LEDGERNAME>Cash<\/LEDGERNAME><ISDEEMEDPOSITIVE>Yes<\/ISDEEMEDPOSITIVE><AMOUNT>-[\d.]+<\/AMOUNT><\/ALLLEDGERENTRIES.LIST>/);
    expect(vs.find((v) => v.number === `R-${upi.invoiceNumber}`)!.text).toContain('<LEDGERNAME>HDFC Bank (UPI)</LEDGERNAME>');
  });

  it('TL7b: an unpaid sale stays outstanding (New Ref, no receipt); a paid one is closed by its Agst Ref receipt', async () => {
    const unpaid = await offlineInvoice({ paymentMode: null });
    const paid = await offlineInvoice({ paymentMode: 'UPI' });
    const vs = vouchers(await tally());
    const sale = vs.find((v) => v.number === unpaid.invoiceNumber)!;
    expect(sale.text).toMatch(/<BILLTYPE>New Ref<\/BILLTYPE><BILLCREDITPERIOD>30 Days<\/BILLCREDITPERIOD><AMOUNT>-([\d.]+)<\/AMOUNT>/);
    expect(vs.some((v) => v.type === 'Receipt' && v.text.includes(`<NAME>${unpaid.invoiceNumber}</NAME>`))).toBe(false);
    const paidSale = vs.find((v) => v.number === paid.invoiceNumber)!;
    const billed = /<BILLTYPE>New Ref<\/BILLTYPE><BILLCREDITPERIOD>30 Days<\/BILLCREDITPERIOD><AMOUNT>-([\d.]+)<\/AMOUNT>/.exec(paidSale.text)![1];
    const receipt = vs.find((v) => v.number === `R-${paid.invoiceNumber}`)!;
    expect(receipt.text).toContain(`<NAME>${paid.invoiceNumber}</NAME><BILLTYPE>Agst Ref</BILLTYPE><AMOUNT>${billed}</AMOUNT>`);
  });

  it('TL7c: no purchases, no supplier masters, no 0-amount vouchers', async () => {
    const p = await product();
    await accounts.post('/api/staff/billing/stock').send({ productId: p.id, quantity: 200, date: today(), note: 'Opening stock' });
    const xml = await tally();
    expect(xml).not.toContain('VCHTYPE="Purchase"');
    expect(xml).not.toContain('Sundry Creditors');
    expect(xml).not.toMatch(/Opening stock/);
    for (const v of vouchers(xml)) expect(v.text).not.toMatch(/<LEDGERENTRIES\.LIST><LEDGERNAME>[^<]+<\/LEDGERNAME><ISDEEMEDPOSITIVE>(Yes|No)<\/ISDEEMEDPOSITIVE><AMOUNT>-?0\.00<\/AMOUNT>/);
    // Asking for purchases gives nothing.
    expect(vouchers(await tally('purchases')).length).toBe(0);
  });

  it('TL7d: stable REMOTEID/GUID from the database ID; "already exported on" per voucher; re-export keeps the same IDs', async () => {
    const inv = await offlineInvoice({ paymentMode: 'UPI' });
    const before = (await accounts.get(`/api/staff/billing/tally/summary?from=${today()}&to=${today()}`)).body;
    expect(before.list.find((v: { number: string }) => v.number === inv.invoiceNumber).exportedAt).toBeNull();
    const first = vouchers(await tally());
    const second = vouchers(await tally());
    const row = await prisma.invoice.findUniqueOrThrow({ where: { number: inv.invoiceNumber } });
    const s1 = first.find((v) => v.number === inv.invoiceNumber)!;
    expect(s1.guid).toBe(`rejwin-sales-${row.id}`);
    expect(s1.text).toContain(`<GUID>rejwin-sales-${row.id}</GUID>`);
    expect(first.find((v) => v.number === `R-${inv.invoiceNumber}`)!.guid).toBe(`rejwin-receipt-${row.id}`);
    expect(second.map((v) => v.guid)).toEqual(first.map((v) => v.guid));
    expect(new Set(second.map((v) => v.guid)).size).toBe(second.length);
    const after = (await accounts.get(`/api/staff/billing/tally/summary?from=${today()}&to=${today()}`)).body;
    const listed = after.list.filter((v: { number: string }) => v.number === inv.invoiceNumber || v.number === `R-${inv.invoiceNumber}`);
    expect(listed).toHaveLength(2);
    for (const v of listed) expect(v.exportedAt).not.toBeNull();
    const rec = await prisma.tallyExport.findUniqueOrThrow({ where: { guid: `rejwin-sales-${row.id}` } });
    expect(rec.count).toBe(2);
  });

  it('TL7e: masters before the vouchers, created only if missing: customers, sales, Duties & Taxes, Round Off, Cash, Bank and UPI, Discount Allowed with GST', async () => {
    await offlineInvoice({ discount: { type: 'amount', value: 100 } });
    const xml = await tally();
    const masters = xml.slice(0, xml.indexOf('<REPORTNAME>Vouchers</REPORTNAME>'));
    const m = (name: string, parent: string) => expect(masters).toMatch(new RegExp(`<LEDGER NAME="${name.replace(/[()%.]/g, '\\$&')}" ACTION="Create"><NAME.LIST><NAME>[^<]+</NAME></NAME.LIST><PARENT>${parent}</PARENT>`));
    m('Sales GST 5% Local', 'Sales Accounts');
    m('Sales GST 5% Interstate', 'Sales Accounts');
    m('Output CGST 2.5%', 'Duties &amp; Taxes');
    m('Output SGST 2.5%', 'Duties &amp; Taxes');
    m('Output IGST 5%', 'Duties &amp; Taxes');
    m('Round Off', 'Indirect Expenses');
    m('Cash', 'Cash-in-Hand');
    m('HDFC Bank', 'Bank Accounts');
    m('HDFC Bank (UPI)', 'Bank Accounts');
    expect(masters).toMatch(/<LEDGER NAME="Store Customer[^"]*" ACTION="Create"><NAME.LIST><NAME>[^<]+<\/NAME><\/NAME.LIST><PARENT>Sundry Debtors<\/PARENT>/);
    expect(masters).toMatch(/<LEDGER NAME="Discount Allowed" ACTION="Create">.*<APPROPRIATEFOR>GST<\/APPROPRIATEFOR><GSTAPPROPRIATETO>Goods<\/GSTAPPROPRIATETO><EXCISEALLOCTYPE>Based on Value<\/EXCISEALLOCTYPE>/);
    expect(masters).toMatch(/<GSTDUTYHEAD>Central Tax<\/GSTDUTYHEAD>/);
    expect(masters).not.toContain('<VOUCHER');
  });

  it('TL7f: every ledger name comes from the settings', async () => {
    await accounts.put('/api/staff/billing/tally-settings').send({ ledgers: { igst: 'IGST Out', cash: 'Cash Box', discount: 'Disc Allowed' } });
    try {
      await offlineInvoice({ state: 'Maharashtra', delivery: 'courier', shipping: { line1: '1, Road', city: 'Pune', district: 'Pune', state: 'Maharashtra', pincode: '411001' }, discount: { type: 'amount', value: 50 }, paymentMode: 'Cash' });
      const xml = await tally();
      expect(xml).toContain('<LEDGERNAME>IGST Out</LEDGERNAME>');
      expect(xml).toContain('<LEDGERNAME>Cash Box</LEDGERNAME>');
      expect(xml).toContain('<LEDGERNAME>Disc Allowed</LEDGERNAME>');
      expect(xml).toContain('<LEDGER NAME="IGST Out" ACTION="Create">');
    } finally {
      const { defaults } = (await admin.get('/api/staff/billing/tally-settings')).body;
      await admin.put('/api/staff/billing/tally-settings').send({ ledgers: defaults });
    }
  });

  it('TL7g: rate is the product taxable rate; AMOUNT is the invoice line value; percentage, rupee and inter-state sales balance to the paisa and equal the GSTR-1 totals', async () => {
    const p = await product();
    const rate = unitPrice(p).taxable;
    const pct = await offlineInvoice({ items: [{ productId: p.id, quantity: 4, rate: rate / 100 }], discount: { type: 'percent', value: 10 }, paymentMode: null });
    const rup = await offlineInvoice({ items: [{ productId: p.id, quantity: 1, rate: rate / 100 }], discount: { type: 'amount', value: 50 }, paymentMode: 'UPI' });
    const inter = await offlineInvoice({ state: 'Kerala', delivery: 'courier', shipping: { line1: '1, Road', city: 'Kochi', district: 'Ernakulam', state: 'Kerala', pincode: '682001' }, items: [{ productId: p.id, quantity: 4, rate: rate / 100 }], paymentMode: 'Cash' });
    const sampleXml = await tally();
    // Change 07.3: TALLY_SAMPLE=<file> keeps this export as the sample attached to CHANGE-STATUS.md.
    if (process.env.TALLY_SAMPLE) (await import('fs')).writeFileSync(process.env.TALLY_SAMPLE, sampleXml);
    const vs = vouchers(sampleXml);
    for (const v of vs) expect(v.balance, `${v.type} ${v.number}`).toBe(0);
    for (const inv of [pct, rup, inter]) {
      const row = await prisma.invoice.findUniqueOrThrow({ where: { number: inv.invoiceNumber } });
      const s = row.snapshot as unknown as { items: { taxablePaise: number; discountPaise: number }[]; totals: { discountLabel?: string } };
      const v = vs.find((x) => x.number === inv.invoiceNumber)!;
      expect(v.text).toContain(`<RATE>${(rate / 100).toFixed(2)}/Nos</RATE>`);
      const lineValue = s.items[0].taxablePaise + (/%/.test(s.totals.discountLabel ?? '') ? 0 : s.items[0].discountPaise);
      expect(v.text).toContain(`<AMOUNT>${(lineValue / 100).toFixed(2)}</AMOUNT><ACTUALQTY>`);
    }
    expect(vs.find((v) => v.number === inter.invoiceNumber)!.text).toContain('<LEDGERNAME>Sales GST 5% Interstate</LEDGERNAME>');
    expect(vs.find((v) => v.number === inter.invoiceNumber)!.text).toContain('<LEDGERNAME>Output IGST 5%</LEDGERNAME>');
    // The check summary equals the site's reports, which GSTR-1 is built from.
    const summary = (await accounts.get(`/api/staff/billing/tally/summary?from=${today()}&to=${today()}`)).body;
    expect(summary.matchesReports).toBe(true);
  });

  it('TL7h: a rupee discount comes off the price including GST: ₹500 off one ₹3,500 bottle is ₹3,000 at the rate 3,333.33', async () => {
    const p = await bottle('tl7h');
    const inv = await offlineInvoice({ items: [{ productId: p.id, quantity: 1, rate: 3333.33 }], discount: { type: 'amount', value: 500 }, paymentMode: 'UPI' });
    const row = await prisma.invoice.findUniqueOrThrow({ where: { number: inv.invoiceNumber } });
    const s = row.snapshot as unknown as { items: { ratePaise: number }[]; totals: { totalPaise: number; discountPaise: number; taxablePaise: number; discountEnteredPaise: number } };
    expect(s.items[0].ratePaise).toBe(333333);
    expect(s.totals.totalPaise).toBe(300000);
    expect(s.totals.discountPaise).toBe(47619);
    expect(s.totals.taxablePaise).toBe(285714);
    expect(s.totals.discountEnteredPaise).toBe(50000);
    // The edit form shows ₹500 again.
    const form = (await accounts.get(`/api/staff/billing/offline-invoices/${row.orderId}`)).body;
    expect(form.discount).toEqual({ type: 'amount', value: 500 });
  });

  it('TL7i: the cause of 3,357.00 (EHB/2026-27/06 to 08): a raised rate is put back to the product rate and the total stays the same', async () => {
    const p = await bottle('tl7i');
    // As saved before this change: the rate raised to 3,357 so that ₹500 off the base price came to ₹3,000.
    const inv = await offlineInvoice({ items: [{ productId: p.id, quantity: 1, rate: 3357 }], paymentMode: 'UPI' });
    const row = await prisma.invoice.findUniqueOrThrow({ where: { number: inv.invoiceNumber } });
    const snap = row.snapshot as Record<string, any>;
    // Make the stored copy look like the old one: ₹500 off the base price, total ₹3,000.
    snap.totals = { ...snap.totals, discountPaise: 50000, taxablePaise: 285700, cgstPaise: 7143, sgstPaise: 7142, igstPaise: 0, taxPaise: 14285, roundOffPaise: 15, totalPaise: 300000, discountLabel: 'Discount' };
    delete snap.totals.discountEnteredPaise;
    snap.items[0] = { ...snap.items[0], discountPaise: 50000, taxablePaise: 285700 };
    await prisma.invoice.update({ where: { id: row.id }, data: { snapshot: snap } });

    const dry = await correctInvoiceRate(inv.invoiceNumber, adminId, false);
    expect(dry.status).toBe('would correct');
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: row.id } })).snapshot).toEqual(snap);
    const done = await correctInvoiceRate(inv.invoiceNumber, adminId, true);
    expect(done.status).toBe('corrected');
    const fixed = (await prisma.invoice.findUniqueOrThrow({ where: { id: row.id } })).snapshot as Record<string, any>;
    expect(fixed.items[0].ratePaise).toBe(333333);
    expect(fixed.totals.totalPaise).toBe(300000);
    expect(fixed.invoiceNumber).toBe(inv.invoiceNumber);
    const versions = await prisma.invoiceVersion.findMany({ where: { invoiceId: row.id } });
    expect(versions.length).toBe(1);
    expect((await correctInvoiceRate(inv.invoiceNumber, adminId, true)).status).toBe('rate already correct');
    const xml = await tally('sales');
    expect(vouchers(xml).find((v) => v.number === inv.invoiceNumber)!.text).toContain('<RATE>3333.33/Nos</RATE>');
  });
});

describe('change 07.2: Tally settings for Accounts, nothing about purchases', () => {
  it('TS7: Accounts edits the one shared set; every rename is logged with who, when, old and new; no Purchases or Suppliers group', async () => {
    const r = await accounts.put('/api/staff/billing/tally-settings').send({ ledgers: { bank: 'SBI Current' } });
    expect(r.status).toBe(200);
    expect(r.body.ledgers.bank).toBe('SBI Current');
    const seen = (await admin.get('/api/staff/billing/tally-settings')).body;
    expect(seen.ledgers.bank).toBe('SBI Current');
    expect(Object.values(seen.labels)).toEqual(['Sales (Karnataka)', 'Sales (other states)', 'CGST', 'SGST', 'IGST', 'Discount', 'Round off', 'Cash', 'Bank', 'UPI receipts', "Customers' group", 'Stock item', 'Unit']);
    expect(Object.keys(seen.ledgers)).not.toContain('purchases');
    expect(Object.keys(seen.ledgers)).not.toContain('suppliersGroup');
    const log = seen.renames[0];
    expect(log).toMatchObject({ setting: 'Bank', from: 'HDFC Bank', to: 'SBI Current' });
    expect(log.by).toBeTruthy();
    expect(new Date(log.at).getTime()).toBeGreaterThan(Date.now() - 60_000);
    // The old purchase settings cannot be set through the page.
    await prisma.setting.deleteMany({ where: { key: 'tally.ledgers' } });
    await accounts.put('/api/staff/billing/tally-settings').send({ ledgers: { purchases: 'Purchase GST 5%', bank: 'HDFC Bank' } });
    const row = await prisma.setting.findUniqueOrThrow({ where: { key: 'tally.ledgers' } });
    expect(Object.keys(row.value as object)).not.toContain('purchases');
    // Marketing and the doctor cannot.
    expect((await (await staffAgent('marketing')).agent.put('/api/staff/billing/tally-settings').send({ ledgers: { bank: 'X' } })).status).toBe(403);
  });
});

