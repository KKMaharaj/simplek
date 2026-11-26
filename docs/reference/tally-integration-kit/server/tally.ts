import { prisma } from '../../lib/prisma';
import { audit } from '../../lib/audit';
import { escapeHtml } from '../../lib/pdf';
import { istParts } from '../../lib/dates';
import { InvoiceSnapshot } from '../invoices/snapshot';
import { getSettings } from '../settings/store';
import { creditNotesIn, invoicesIn, salesReport } from './reports';

/**
 * The Tally export for TallyPrime XML import (Import > Transactions, with masters).
 *
 * Change 06.12 built it; change 07.3 fixed it after the client's import failed:
 * - Sales and Credit Notes are invoice-view vouchers (OBJVIEW and PERSISTEDVIEW
 *   "Invoice Voucher View"): the stock item with quantity, rate, discount % and
 *   amount in ALLINVENTORYENTRIES.LIST, and the party, tax, discount and round-off
 *   lines in LEDGERENTRIES.LIST.
 * - Receipts (and any other accounting voucher: Payment, Journal, Contra) are
 *   accounting-view vouchers (OBJVIEW and PERSISTEDVIEW "Accounting Voucher View")
 *   and every line is ALLLEDGERENTRIES.LIST. LEDGERENTRIES.LIST only works in
 *   invoice view; in a receipt Tally drops both lines and the voucher arrives empty.
 * - Every voucher carries a stable REMOTEID and GUID from its database ID, so
 *   importing the same file again updates the voucher instead of adding a second.
 * - No purchases and no supplier masters (change 07.2): the client enters
 *   purchases directly in Tally. No voucher with an amount of 0 is written.
 * - Masters, created only when missing (ACTION="Create"), before the vouchers:
 *   the unit, the stock item, the customers (Sundry Debtors), the sales ledgers,
 *   CGST, SGST and IGST under Duties & Taxes, Round Off, Cash under Cash-in-Hand,
 *   the bank and UPI ledgers under Bank Accounts, and Discount Allowed with GST
 *   "Include in assessable value: GST, Appropriate to: Goods, Method: Based on Value".
 * - The item AMOUNT is the invoice's own line value, never rate × quantity, so
 *   Tally matches the invoice to the paisa. Every ledger name comes from the Tally
 *   settings (one shared set).
 */

export interface TallyLedgers {
  salesLocal: string;
  salesInterstate: string;
  cgst: string;
  sgst: string;
  igst: string;
  discount: string;
  roundOff: string;
  cash: string;
  bank: string;
  upi: string;
  customersGroup: string;
  stockItem: string;
  unit: string;
}

export const TALLY_DEFAULTS: TallyLedgers = {
  salesLocal: 'Sales GST 5% Local',
  salesInterstate: 'Sales GST 5% Interstate',
  cgst: 'Output CGST 2.5%',
  sgst: 'Output SGST 2.5%',
  igst: 'Output IGST 5%',
  discount: 'Discount Allowed',
  roundOff: 'Round Off',
  cash: 'Cash',
  bank: 'HDFC Bank',
  upi: 'HDFC Bank (UPI)',
  customersGroup: 'Sundry Debtors',
  stockItem: 'Rejwin, 1000 ml',
  unit: 'Nos',
};

/** Change 07.2: the settings list, in this order. */
export const TALLY_LABELS: Record<keyof TallyLedgers, string> = {
  salesLocal: 'Sales (Karnataka)',
  salesInterstate: 'Sales (other states)',
  cgst: 'CGST',
  sgst: 'SGST',
  igst: 'IGST',
  discount: 'Discount',
  roundOff: 'Round off',
  cash: 'Cash',
  bank: 'Bank',
  upi: 'UPI receipts',
  customersGroup: "Customers' group",
  stockItem: 'Stock item',
  unit: 'Unit',
};

const KEY = 'tally.ledgers';
const KEYS = Object.keys(TALLY_DEFAULTS) as (keyof TallyLedgers)[];

/** The names in use: the saved ones over the defaults; anything no longer in the list (purchases) is dropped. */
export async function tallyLedgers(): Promise<TallyLedgers> {
  const row = await prisma.setting.findUnique({ where: { key: KEY } });
  const saved = (row?.value as Partial<Record<string, string>>) ?? {};
  return Object.fromEntries(KEYS.map((k) => [k, typeof saved[k] === 'string' && saved[k] ? saved[k] : TALLY_DEFAULTS[k]])) as unknown as TallyLedgers;
}

/** Change 07.2: every rename is logged with who, when, the old name and the new name. */
export async function saveTallyLedgers(values: Partial<TallyLedgers>, staffId: string) {
  const before = await tallyLedgers();
  const next = { ...before } as TallyLedgers;
  for (const k of KEYS) if (typeof values[k] === 'string') next[k] = values[k]!;
  // Values saved before change 07.2 (the purchase settings) are kept as they were, unused.
  const row = await prisma.setting.findUnique({ where: { key: KEY } });
  const stored = row?.value && typeof row.value === 'object' && !Array.isArray(row.value) ? (row.value as Record<string, unknown>) : {};
  const value = { ...stored, ...next };
  await prisma.setting.upsert({ where: { key: KEY }, create: { key: KEY, value }, update: { value } });
  const renames = KEYS.filter((k) => next[k] !== before[k]).map((k) => ({ setting: TALLY_LABELS[k], from: before[k], to: next[k] }));
  if (renames.length) {
    await audit({ type: 'staff', id: staffId }, 'tally.ledgers_change', 'setting', KEY, { renames, changed: renames.map((r) => `${r.setting}: ${r.from} → ${r.to}`) });
  }
  return next;
}

/** Change 07.2: the rename log, newest first. */
export async function tallyRenames(limit = 50) {
  const rows = await prisma.auditLog.findMany({ where: { action: 'tally.ledgers_change' }, orderBy: { createdAt: 'desc' }, take: limit });
  const staff = await prisma.staff.findMany({ where: { id: { in: [...new Set(rows.map((r) => r.actorId).filter(Boolean) as string[])] } }, select: { id: true, name: true } });
  const name = (id: string | null) => staff.find((s) => s.id === id)?.name ?? 'Unknown';
  return rows.flatMap((r) => {
    const d = (r.detail ?? {}) as { renames?: { setting: string; from: string; to: string }[]; changed?: string[] };
    const list = d.renames ?? (d.changed ?? []).map((c) => {
      const m = /^(.*?): (.*) → (.*)$/.exec(c);
      return m ? { setting: m[1], from: m[2], to: m[3] } : { setting: c, from: '', to: '' };
    });
    return list.map((x) => ({ ...x, at: r.createdAt, by: name(r.actorId) }));
  });
}

const x = (s: unknown) => escapeHtml(s);
const amt = (paise: number) => (paise / 100).toFixed(2);
const date = (d: Date) => {
  const p = istParts(d);
  return `${p.y}${String(p.m).padStart(2, '0')}${String(p.d).padStart(2, '0')}`;
};
const pct = (n: number) => String(Number(n.toFixed(2)));

/** A line of a ledger. Debits are negative with ISDEEMEDPOSITIVE Yes, as Tally writes them. */
const line = (tag: 'LEDGERENTRIES.LIST' | 'ALLLEDGERENTRIES.LIST', name: string, paise: number, debit: boolean, inner = '') =>
  `<${tag}><LEDGERNAME>${x(name)}</LEDGERNAME><ISDEEMEDPOSITIVE>${debit ? 'Yes' : 'No'}</ISDEEMEDPOSITIVE><AMOUNT>${debit ? '-' : ''}${amt(Math.abs(paise))}</AMOUNT>${inner}</${tag}>`;
/** Invoice view (Sales, Credit Note). */
const ledger = (name: string, paise: number, debit: boolean, inner = '') => line('LEDGERENTRIES.LIST', name, paise, debit, inner);
/** Accounting view (Receipt, Payment, Journal, Contra). */
const accLedger = (name: string, paise: number, debit: boolean, inner = '') => line('ALLLEDGERENTRIES.LIST', name, paise, debit, inner);
const bill = (ref: string, kind: 'New Ref' | 'Agst Ref', paise: number, debit: boolean, days?: number) =>
  `<BILLALLOCATIONS.LIST><NAME>${x(ref)}</NAME><BILLTYPE>${kind}</BILLTYPE>${days != null ? `<BILLCREDITPERIOD>${days} Days</BILLCREDITPERIOD>` : ''}<AMOUNT>${debit ? '-' : ''}${amt(Math.abs(paise))}</AMOUNT></BILLALLOCATIONS.LIST>`;
const msg = (inner: string) => `<TALLYMESSAGE xmlns:UDF="TallyUDF">${inner}</TALLYMESSAGE>`;

/** The stable GUID of a voucher: the same database row always gives the same GUID. */
export const tallyGuid = (kind: 'sales' | 'receipt' | 'creditnote', id: string) => `rejwin-${kind === 'receipt' ? 'receipt' : kind === 'sales' ? 'sales' : 'creditnote'}-${id}`;
const ids = (guid: string) => ` REMOTEID="${x(guid)}"`;
const guidTag = (guid: string) => `<GUID>${x(guid)}</GUID>`;

type Inv = Awaited<ReturnType<typeof invoicesIn>>[number];
const snap = (i: { snapshot: unknown }) => i.snapshot as unknown as InvoiceSnapshot;

/** The customer's ledger name: their name, with the mobile number when two customers share a name. */
function partyNames(invs: { order: { customerId: string }; snapshot: unknown }[]) {
  const byName = new Map<string, Set<string>>();
  for (const i of invs) {
    const n = snap(i).buyer.name.trim();
    byName.set(n, (byName.get(n) ?? new Set()).add(i.order.customerId));
  }
  return (i: { order: { customerId: string }; snapshot: unknown }) => {
    const s = snap(i);
    const n = s.buyer.name.trim();
    return (byName.get(n)?.size ?? 0) > 1 ? `${n} (${s.buyer.mobile})` : n;
  };
}

/**
 * One invoice's lines. The item amount is the invoice's own line value: its
 * taxable value, with a rupee discount (coupon or amount) added back because that
 * goes on the Discount Allowed ledger instead; percentage discounts (bulk, or a
 * percentage discount on an offline invoice) stay on the item as DISCOUNT %.
 */
export function invoiceLines(s: InvoiceSnapshot) {
  const percent = /\((\d+(?:\.\d+)?)%\)/.exec(s.totals.discountLabel ?? '');
  const items = s.items.map((it) => {
    const rupee = percent ? 0 : it.discountPaise;
    const amount = it.taxablePaise + rupee;
    const pctOff = (it.bulkDiscountPaise ?? 0) + (percent ? it.discountPaise : 0);
    const discPct = pctOff ? (it.bulkDiscountPaise && percent ? 100 * (1 - (1 - (s.totals.bulkDiscountPercent ?? 0) / 100) * (1 - Number(percent[1]) / 100)) : it.bulkDiscountPaise ? (s.totals.bulkDiscountPercent ?? 0) : Number(percent![1])) : 0;
    return { it, amount, discPct };
  });
  const rupeeDiscount = percent ? 0 : s.totals.discountPaise;
  const tax = s.totals.cgstPaise + s.totals.sgstPaise + s.totals.igstPaise;
  const itemsTotal = items.reduce((a, l) => a + l.amount, 0);
  // Everything must add up to the invoice; any difference of rounding goes to Round Off.
  const roundOff = s.totals.totalPaise - (itemsTotal - rupeeDiscount + tax + s.totals.shippingPaise);
  return { items, rupeeDiscount, roundOff };
}

function inventory(L: TallyLedgers, salesLedger: string, l: ReturnType<typeof invoiceLines>['items'][number], outward: boolean) {
  const q = ` ${l.it.quantity} ${L.unit}`;
  const sign = outward ? '' : '-';
  return `<ALLINVENTORYENTRIES.LIST><STOCKITEMNAME>${x(L.stockItem)}</STOCKITEMNAME><ISDEEMEDPOSITIVE>${outward ? 'No' : 'Yes'}</ISDEEMEDPOSITIVE><RATE>${amt(l.it.ratePaise)}/${x(L.unit)}</RATE>${l.discPct ? `<DISCOUNT>${pct(l.discPct)}</DISCOUNT>` : ''}<AMOUNT>${sign}${amt(l.amount)}</AMOUNT><ACTUALQTY>${q}</ACTUALQTY><BILLEDQTY>${q}</BILLEDQTY><ACCOUNTINGALLOCATIONS.LIST><LEDGERNAME>${x(salesLedger)}</LEDGERNAME><ISDEEMEDPOSITIVE>${outward ? 'No' : 'Yes'}</ISDEEMEDPOSITIVE><AMOUNT>${sign}${amt(l.amount)}</AMOUNT></ACCOUNTINGALLOCATIONS.LIST></ALLINVENTORYENTRIES.LIST>`;
}

/** Sales (outward) or Credit Note (the reverse), in invoice view. */
function itemVoucher(L: TallyLedgers, kind: 'Sales' | 'Credit Note', guid: string, number: string, when: Date, party: string, s: InvoiceSnapshot, amountPaise: number, narration: string, billRef: { name: string; type: 'New Ref' | 'Agst Ref'; days?: number }) {
  const sale = kind === 'Sales';
  const lines = invoiceLines(s);
  const salesLedger = s.intraState ? L.salesLocal : L.salesInterstate;
  const t = s.totals;
  const parts = [
    ledger(party, amountPaise, sale, bill(billRef.name, billRef.type, amountPaise, sale, billRef.days)),
    ...lines.items.map((l) => inventory(L, salesLedger, l, sale)),
    ...(lines.rupeeDiscount ? [ledger(L.discount, lines.rupeeDiscount, sale)] : []),
    ...(t.shippingPaise ? [ledger(salesLedger, t.shippingPaise, !sale)] : []),
    ...(t.cgstPaise ? [ledger(L.cgst, t.cgstPaise, !sale)] : []),
    ...(t.sgstPaise ? [ledger(L.sgst, t.sgstPaise, !sale)] : []),
    ...(t.igstPaise ? [ledger(L.igst, t.igstPaise, !sale)] : []),
    ...(lines.roundOff ? [ledger(L.roundOff, lines.roundOff, sale ? lines.roundOff < 0 : lines.roundOff > 0)] : []),
  ];
  return msg(
    `<VOUCHER${ids(guid)} VCHTYPE="${kind}" ACTION="Create" OBJVIEW="Invoice Voucher View">${guidTag(guid)}<DATE>${date(when)}</DATE><VOUCHERTYPENAME>${kind}</VOUCHERTYPENAME><VOUCHERNUMBER>${x(number)}</VOUCHERNUMBER><REFERENCE>${x(s.invoiceNumber)}</REFERENCE><PARTYLEDGERNAME>${x(party)}</PARTYLEDGERNAME><PARTYNAME>${x(party)}</PARTYNAME><BASICBUYERNAME>${x(s.buyer.name)}</BASICBUYERNAME><STATENAME>${x(s.buyer.state || s.placeOfSupply)}</STATENAME><PLACEOFSUPPLY>${x(s.placeOfSupply)}</PLACEOFSUPPLY>${s.buyer.gstin ? `<PARTYGSTIN>${x(s.buyer.gstin)}</PARTYGSTIN>` : ''}<ISINVOICE>Yes</ISINVOICE><PERSISTEDVIEW>Invoice Voucher View</PERSISTEDVIEW><NARRATION>${x(narration)}</NARRATION>${parts.join('')}</VOUCHER>`,
  );
}

/** A Receipt in accounting view: the customer credited Agst Ref the invoice, the cash, bank or UPI ledger debited. */
export function receiptVoucher(guid: string, number: string, when: Date, party: string, payLedger: string, paise: number, invoiceNumber: string, narration: string) {
  return msg(
    `<VOUCHER${ids(guid)} VCHTYPE="Receipt" ACTION="Create" OBJVIEW="Accounting Voucher View">${guidTag(guid)}<DATE>${date(when)}</DATE><VOUCHERTYPENAME>Receipt</VOUCHERTYPENAME><VOUCHERNUMBER>${x(number)}</VOUCHERNUMBER><PARTYLEDGERNAME>${x(party)}</PARTYLEDGERNAME><NARRATION>${x(narration)}</NARRATION><PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>${accLedger(party, paise, false, bill(invoiceNumber, 'Agst Ref', paise, false))}${accLedger(payLedger, paise, true)}</VOUCHER>`,
  );
}

const PAY_LEDGER = (L: TallyLedgers, type: string, mode: string | null) => (type === 'online' ? L.bank : mode === 'Cash' ? L.cash : mode === 'UPI' ? L.upi : L.bank);

/** Ledger masters, created only when missing. */
function ledgerMaster(name: string, parent: string, inner = '') {
  return msg(`<LEDGER NAME="${x(name)}" ACTION="Create"><NAME.LIST><NAME>${x(name)}</NAME></NAME.LIST><PARENT>${x(parent)}</PARENT>${inner}</LEDGER>`);
}
const taxMaster = (name: string, head: 'Central Tax' | 'State Tax' | 'Integrated Tax', rate: number) =>
  ledgerMaster(name, 'Duties & Taxes', `<TAXTYPE>GST</TAXTYPE><GSTDUTYHEAD>${head}</GSTDUTYHEAD><RATEOFTAXCALCULATION>${pct(rate)}</RATEOFTAXCALCULATION><ISBILLWISEON>No</ISBILLWISEON>`);

export function fixedMasters(L: TallyLedgers) {
  const unique = <T extends { name: string }>(list: T[]) => list.filter((m, i) => list.findIndex((o) => o.name === m.name) === i);
  const ledgers = unique([
    { name: L.salesLocal, xml: ledgerMaster(L.salesLocal, 'Sales Accounts', '<GSTAPPLICABLE>&#4; Applicable</GSTAPPLICABLE><GSTTYPEOFSUPPLY>Goods</GSTTYPEOFSUPPLY><ISBILLWISEON>No</ISBILLWISEON>') },
    { name: L.salesInterstate, xml: ledgerMaster(L.salesInterstate, 'Sales Accounts', '<GSTAPPLICABLE>&#4; Applicable</GSTAPPLICABLE><GSTTYPEOFSUPPLY>Goods</GSTTYPEOFSUPPLY><ISBILLWISEON>No</ISBILLWISEON>') },
    { name: L.cgst, xml: taxMaster(L.cgst, 'Central Tax', 2.5) },
    { name: L.sgst, xml: taxMaster(L.sgst, 'State Tax', 2.5) },
    { name: L.igst, xml: taxMaster(L.igst, 'Integrated Tax', 5) },
    { name: L.roundOff, xml: ledgerMaster(L.roundOff, 'Indirect Expenses', '<GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE>') },
    { name: L.cash, xml: ledgerMaster(L.cash, 'Cash-in-Hand') },
    { name: L.bank, xml: ledgerMaster(L.bank, 'Bank Accounts') },
    { name: L.upi, xml: ledgerMaster(L.upi, 'Bank Accounts') },
    {
      name: L.discount,
      // Include in assessable value calculation for: GST; Appropriate to: Goods; Method of calculation: Based on Value.
      xml: ledgerMaster(L.discount, 'Indirect Expenses', '<GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE><APPROPRIATEFOR>GST</APPROPRIATEFOR><GSTAPPROPRIATETO>Goods</GSTAPPROPRIATETO><EXCISEALLOCTYPE>Based on Value</EXCISEALLOCTYPE>'),
    },
  ]);
  return [
    msg(`<UNIT NAME="${x(L.unit)}" ACTION="Create"><NAME>${x(L.unit)}</NAME><ISSIMPLEUNIT>Yes</ISSIMPLEUNIT></UNIT>`),
    msg(
      `<STOCKITEM NAME="${x(L.stockItem)}" ACTION="Create"><NAME.LIST><NAME>${x(L.stockItem)}</NAME></NAME.LIST><BASEUNITS>${x(L.unit)}</BASEUNITS><GSTAPPLICABLE>&#4; Applicable</GSTAPPLICABLE><GSTDETAILS.LIST><APPLICABLEFROM>20260401</APPLICABLEFROM><CALCULATIONTYPE>On Value</CALCULATIONTYPE><HSNCODE>30049011</HSNCODE><TAXABILITY>Taxable</TAXABILITY><STATEWISEDETAILS.LIST><STATENAME>&#4; Any</STATENAME><RATEDETAILS.LIST><GSTRATEDUTYHEAD>Central Tax</GSTRATEDUTYHEAD><GSTRATE>2.5</GSTRATE></RATEDETAILS.LIST><RATEDETAILS.LIST><GSTRATEDUTYHEAD>State Tax</GSTRATEDUTYHEAD><GSTRATE>2.5</GSTRATE></RATEDETAILS.LIST><RATEDETAILS.LIST><GSTRATEDUTYHEAD>Integrated Tax</GSTRATEDUTYHEAD><GSTRATE>5</GSTRATE></RATEDETAILS.LIST></STATEWISEDETAILS.LIST></GSTDETAILS.LIST></STOCKITEM>`,
    ),
    ...ledgers.map((l) => l.xml),
  ];
}

export type TallyKind = 'sales' | 'receipts' | 'creditnotes';
export const TALLY_KINDS: TallyKind[] = ['sales', 'receipts', 'creditnotes'];

interface VoucherRow {
  guid: string;
  kind: 'sales' | 'receipt' | 'creditnote';
  number: string;
  date: Date;
  party: string;
  amountPaise: number;
  xml: string;
}

export async function tallyExport(from: Date, to: Date, kinds: TallyKind[] = TALLY_KINDS, markExported = false) {
  const L = await tallyLedgers();
  const s = await getSettings();
  const want = (k: TallyKind) => kinds.includes(k);
  const invs = want('sales') ? await invoicesIn({ from, to }) : [];
  const cns = want('creditnotes') ? await creditNotesIn({ from, to }) : [];
  const paid = want('receipts')
    ? await prisma.invoice.findMany({ where: { paidAt: { gte: from, lt: to }, order: { deletedAt: null } }, include: { order: { select: { type: true, customerId: true, orderNumber: true } } }, orderBy: { paidAt: 'asc' } })
    : [];

  const all = [...invs, ...cns.map((c) => ({ ...c.invoice })), ...paid] as unknown as { order: { customerId: string }; snapshot: unknown }[];
  const party = partyNames(all);

  // Masters: the fixed ledgers, the unit and stock item, and each customer under Sundry Debtors.
  const customers = new Map<string, InvoiceSnapshot>();
  for (const i of all) customers.set(party(i), snap(i));
  const masters = [
    ...fixedMasters(L),
    ...[...customers.entries()].map(([name, sn]) =>
      msg(
        `<LEDGER NAME="${x(name)}" ACTION="Create"><NAME.LIST><NAME>${x(name)}</NAME></NAME.LIST><PARENT>${x(L.customersGroup)}</PARENT><ISBILLWISEON>Yes</ISBILLWISEON><ADDRESS.LIST><ADDRESS>${x(sn.buyer.address)}</ADDRESS></ADDRESS.LIST><LEDSTATENAME>${x(sn.buyer.state || sn.placeOfSupply)}</LEDSTATENAME><COUNTRYNAME>India</COUNTRYNAME>${/\b\d{6}\b/.test(sn.buyer.address) ? `<PINCODE>${/\b(\d{6})\b/.exec(sn.buyer.address)![1]}</PINCODE>` : ''}<LEDGERMOBILE>${x(sn.buyer.mobile)}</LEDGERMOBILE>${sn.buyer.email ? `<EMAIL>${x(sn.buyer.email)}</EMAIL>` : ''}<GSTREGISTRATIONTYPE>${sn.buyer.gstin ? 'Regular' : 'Unregistered/Consumer'}</GSTREGISTRATIONTYPE>${sn.buyer.gstin ? `<PARTYGSTIN>${x(sn.buyer.gstin)}</PARTYGSTIN>` : ''}</LEDGER>`,
      ),
    ),
  ];

  const vouchers: VoucherRow[] = [];
  for (const i of invs) {
    const sn = snap(i);
    if (!sn.totals.totalPaise) continue;
    const guid = tallyGuid('sales', i.id);
    vouchers.push({ guid, kind: 'sales', number: i.number, date: i.issuedAt, party: party(i), amountPaise: sn.totals.totalPaise, xml: itemVoucher(L, 'Sales', guid, i.number, i.issuedAt, party(i), sn, sn.totals.totalPaise, `Order ${i.order.orderNumber}`, { name: i.number, type: 'New Ref', days: 30 }) });
  }
  for (const i of paid) {
    const sn = snap(i);
    const total = sn.totals.totalPaise;
    if (!total) continue;
    const guid = tallyGuid('receipt', i.id);
    const p = party(i as never);
    const narration = `${i.order.type === 'online' ? 'Paid online via Razorpay' : `Paid by ${i.paymentMode ?? 'cash'}`} against ${i.number}`;
    vouchers.push({ guid, kind: 'receipt', number: `R-${i.number}`, date: i.paidAt!, party: p, amountPaise: total, xml: receiptVoucher(guid, `R-${i.number}`, i.paidAt!, p, PAY_LEDGER(L, i.order.type, i.paymentMode), total, i.number, narration) });
  }
  for (const c of cns) {
    if (!c.amountPaise) continue;
    const sn = snap(c.invoice);
    const guid = tallyGuid('creditnote', c.id);
    const p = party(c.invoice as never);
    vouchers.push({ guid, kind: 'creditnote', number: c.number, date: c.createdAt, party: p, amountPaise: c.amountPaise, xml: itemVoucher(L, 'Credit Note', guid, c.number, c.createdAt, p, sn, c.amountPaise, `Against ${c.invoice.number}: ${c.reason}`, { name: c.invoice.number, type: 'Agst Ref' }) });
  }

  // "Already exported on [date]", per voucher.
  const before = vouchers.length ? await prisma.tallyExport.findMany({ where: { guid: { in: vouchers.map((v) => v.guid) } } }) : [];
  const exportedOn = new Map(before.map((b) => [b.guid, b.firstExportedAt]));
  if (markExported && vouchers.length) {
    const now = new Date();
    await prisma.$transaction([
      ...vouchers.map((v) =>
        prisma.tallyExport.upsert({ where: { guid: v.guid }, create: { guid: v.guid, kind: v.kind, number: v.number, firstExportedAt: now, lastExportedAt: now }, update: { number: v.number, lastExportedAt: now, count: { increment: 1 } } }),
      ),
      ...(invs.length ? [prisma.invoice.updateMany({ where: { id: { in: invs.map((i) => i.id) } }, data: { tallyExportedAt: now } })] : []),
    ]);
  }

  const sales = vouchers.filter((v) => v.kind === 'sales');
  const receipts = vouchers.filter((v) => v.kind === 'receipt');
  const credit = vouchers.filter((v) => v.kind === 'creditnote');

  // The check summary, against the site's sales report for the same dates.
  const report = want('sales') ? await salesReport({ from, to }) : null;
  const sum = (k: 'taxablePaise' | 'cgstPaise' | 'sgstPaise' | 'igstPaise' | 'totalPaise') => invs.reduce((a, i) => a + snap(i).totals[k], 0);
  const exportedThenDeleted = await prisma.invoice.findMany({ where: { tallyExportedAt: { not: null }, order: { deletedAt: { not: null } } }, select: { number: true, issuedAt: true, tallyExportedAt: true } });
  const summary = {
    vouchers: { sales: sales.length, receipts: receipts.length, creditNotes: credit.length, total: vouchers.length },
    quantity: { sold: invs.reduce((a, i) => a + snap(i).items.reduce((b, it) => b + it.quantity, 0), 0), returned: cns.reduce((a, c) => a + snap(c.invoice).items.reduce((b, it) => b + it.quantity, 0), 0) },
    taxablePaise: sum('taxablePaise'),
    cgstPaise: sum('cgstPaise'),
    sgstPaise: sum('sgstPaise'),
    igstPaise: sum('igstPaise'),
    totalPaise: sum('totalPaise'),
    receiptsPaise: receipts.reduce((a, v) => a + v.amountPaise, 0),
    matchesReports: report
      ? report.totals.invoices === invs.length &&
        report.totals.taxablePaise === sum('taxablePaise') &&
        report.totals.cgstPaise === sum('cgstPaise') &&
        report.totals.sgstPaise === sum('sgstPaise') &&
        report.totals.igstPaise === sum('igstPaise') &&
        report.totals.totalPaise === sum('totalPaise')
      : null,
    exportedThenDeleted: exportedThenDeleted.map((i) => ({ number: i.number, issuedAt: i.issuedAt, exportedAt: i.tallyExportedAt })),
    /** Change 07.3: each voucher, with the date it was first exported (null when new). */
    list: vouchers.map((v) => ({ kind: v.kind, number: v.number, date: v.date, party: v.party, amountPaise: v.amountPaise, exportedAt: exportedOn.get(v.guid) ?? null })),
  };

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY>
<IMPORTDATA><REQUESTDESC><REPORTNAME>All Masters</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${x(s.identity.name)}</SVCURRENTCOMPANY></STATICVARIABLES></REQUESTDESC><REQUESTDATA>
${masters.join('\n')}
</REQUESTDATA></IMPORTDATA>
<IMPORTDATA><REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${x(s.identity.name)}</SVCURRENTCOMPANY></STATICVARIABLES></REQUESTDESC><REQUESTDATA>
${[...sales, ...receipts, ...credit].map((v) => v.xml).join('\n')}
</REQUESTDATA></IMPORTDATA>
</BODY></ENVELOPE>
`;
  return { xml, summary, count: { sales: sales.length, creditNotes: credit.length } };
}

export type { Inv };
