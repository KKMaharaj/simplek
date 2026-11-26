/**
 * The Tally export for TallyPrime XML import (Import > Transactions, with
 * masters), from the owner's proven kit
 * (docs/reference/tally-integration-kit/server/tally.ts). The kit's files
 * import into real TallyPrime, so its XML structure is kept exactly:
 * the same tags, in the same order, with the same signs. Only the data
 * differs (change request 26 Nov 2026, T2):
 *
 * - settings per business (company name, ledger names, units, the
 *   "Export items as" switch), not one shared set;
 * - one stock item per Simplek product (its name, HSN, unit and GST rate),
 *   two products with the same name get their HSN added (as rule 10);
 * - services (SAC) are ledger lines to the service sales ledger, inside the
 *   same invoice-view voucher; "Ledger lines only" does that for every line;
 * - one sales ledger and one tax ledger per GST rate, one tax line per rate;
 *   intra- or inter-state from the invoice's own state-code decision;
 * - a business without GST: one Sales ledger, stock items with GST "Not
 *   Applicable", no tax ledgers or lines, parties Unregistered/Consumer, no
 *   PARTYGSTIN or PLACEOFSUPPLY;
 * - one Receipt per Simplek payment (partial payments), R-<invoice>-<n>;
 * - no credit notes or discounts yet: those code paths stay, dormant;
 * - GUIDs simplek-sales-<invoice id> and simplek-receipt-<payment id>
 *   (rule 4: never change the prefix);
 * - the bill-wise credit period is the invoice's own due date.
 *
 * The kit's rules 1-11 (README) all hold; see the tests.
 *
 * This file has no Deno or Supabase imports, so the same code runs in the
 * edge function and in `node --test` (tally_test.ts).
 */

// --- helpers.excerpt.ts, unchanged ---------------------------------------

export function escapeHtml(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
export const TZ = 'Asia/Kolkata';
const IST_OFFSET_MIN = 330;

/** Calendar parts of a date as seen in India. */
export function istParts(d: Date) {
  const shifted = new Date(d.getTime() + IST_OFFSET_MIN * 60000);
  return { y: shifted.getUTCFullYear(), m: shifted.getUTCMonth() + 1, d: shifted.getUTCDate() };
}

// --- Settings ---------------------------------------------------------------

/** The fixed ledger names (the per-rate ones are made by `rateLedgers`). */
export interface TallyLedgers {
  sales: string;
  discount: string;
  roundOff: string;
  cash: string;
  bank: string;
  upi: string;
  customersGroup: string;
}

export const TALLY_DEFAULTS: TallyLedgers = {
  sales: 'Sales',
  discount: 'Discount Allowed',
  roundOff: 'Round Off',
  cash: 'Cash',
  bank: 'Bank',
  upi: 'UPI receipts',
  customersGroup: 'Sundry Debtors',
};

export const TALLY_LABELS: Record<keyof TallyLedgers, string> = {
  sales: 'Sales (no GST)',
  discount: 'Discount',
  roundOff: 'Round off',
  cash: 'Cash',
  bank: 'Bank',
  upi: 'UPI receipts',
  customersGroup: "Customers' group",
};

/** The names one GST rate needs. */
export interface RateLedgers {
  salesLocal: string;
  salesInterstate: string;
  serviceLocal: string;
  serviceInterstate: string;
  cgst: string;
  sgst: string;
  igst: string;
}
export const RATE_KEYS: (keyof RateLedgers)[] = [
  'salesLocal', 'salesInterstate', 'serviceLocal', 'serviceInterstate', 'cgst', 'sgst', 'igst',
];
export const RATE_LABELS: Record<keyof RateLedgers, string> = {
  salesLocal: 'Sales, within the state',
  salesInterstate: 'Sales, other states',
  serviceLocal: 'Service sales, within the state',
  serviceInterstate: 'Service sales, other states',
  cgst: 'CGST',
  sgst: 'SGST',
  igst: 'IGST',
};

export const pct = (n: number) => String(Number(n.toFixed(2)));

/** The standard names for one rate, in the kit's pattern. */
export function rateDefaults(rate: number): RateLedgers {
  return {
    salesLocal: `Sales GST ${pct(rate)}% Local`,
    salesInterstate: `Sales GST ${pct(rate)}% Interstate`,
    serviceLocal: `Service Sales GST ${pct(rate)}% Local`,
    serviceInterstate: `Service Sales GST ${pct(rate)}% Interstate`,
    cgst: `Output CGST ${pct(rate / 2)}%`,
    sgst: `Output SGST ${pct(rate / 2)}%`,
    igst: `Output IGST ${pct(rate)}%`,
  };
}

/** Simplek's UQC codes to Tally unit names (editable in Tally settings). */
export const UNIT_DEFAULTS: Record<string, string> = {
  NOS: 'Nos', PCS: 'Pcs', KGS: 'Kgs', GMS: 'Gms', LTR: 'Ltr', MLT: 'Ml', MTR: 'Mtr',
  CMS: 'Cms', BOX: 'Box', BAG: 'Bag', BTL: 'Btl', DOZ: 'Doz', PAC: 'Pac', SET: 'Set',
  PRS: 'Prs', ROL: 'Rol', SQF: 'Sqft', SQM: 'Sqm', TON: 'Ton', UNT: 'Unt', OTH: 'Nos',
};

export interface TallySettings {
  /** Company name exactly as in TallyPrime (SVCURRENTCOMPANY). */
  company: string;
  ledgers: Partial<TallyLedgers>;
  /** Per rate ("18", "2.5"), per key. */
  rates: Record<string, Partial<RateLedgers>>;
  units: Record<string, string>;
  /** T2.9: stock items (default), or every line to the sales ledgers. */
  itemsAs: 'stock' | 'ledger';
}

/** The names in use: the saved ones over the defaults (the kit's `tallyLedgers`). */
export function tallyLedgers(saved: Partial<TallySettings> | null | undefined) {
  const L = { ...TALLY_DEFAULTS } as TallyLedgers;
  for (const k of Object.keys(TALLY_DEFAULTS) as (keyof TallyLedgers)[]) {
    const v = saved?.ledgers?.[k];
    if (typeof v === 'string' && v.trim()) L[k] = v.trim();
  }
  const rate = (r: number): RateLedgers => {
    const base = rateDefaults(r);
    const over = saved?.rates?.[pct(r)] ?? {};
    for (const k of RATE_KEYS) {
      const v = over[k];
      if (typeof v === 'string' && v.trim()) base[k] = v.trim();
    }
    return base;
  };
  const unit = (uqc: string | null | undefined) => {
    const code = String(uqc ?? 'NOS').toUpperCase();
    const v = saved?.units?.[code];
    return typeof v === 'string' && v.trim() ? v.trim() : UNIT_DEFAULTS[code] ?? 'Nos';
  };
  return { L, rate, unit, itemsAs: saved?.itemsAs === 'ledger' ? 'ledger' as const : 'stock' as const };
}

// --- Input (from tally_export_data) ---------------------------------------

export interface ExportItem {
  product_id: string | null;
  item_name: string;
  quantity: number | string;
  uqc_code: string | null;
  unit_price: number | string | null;
  taxable_amount: number | string | null;
  gst_rate: number | string | null;
  tax_amount: number | string | null;
  cgst_amount: number | string | null;
  sgst_amount: number | string | null;
  igst_amount: number | string | null;
  product_type: string | null;
  hsn_sac_code: string | null;
  product_name: string | null;
  product_uqc: string | null;
  product_gst_rate: number | string | null;
}

export interface ExportCustomer {
  id: string | null;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  gstin: string | null;
  state: string | null;
}

export interface ExportInvoice {
  id: string;
  invoice_number: string;
  invoice_date: string;
  due_date: string | null;
  customer_name: string;
  customer_gstin: string | null;
  place_of_supply: string | null;
  tax_type: string | null;
  total_amount: number | string;
  customer: ExportCustomer | null;
  items: ExportItem[];
}

export interface ExportPayment {
  id: string;
  invoice_id: string;
  invoice_number: string;
  payment_date: string;
  amount: number | string;
  payment_method: string | null;
  sequence: number;
  customer_name: string;
  customer: ExportCustomer | null;
}

export interface ExportData {
  company: string;
  gst: boolean;
  business_state: string | null;
  settings: Partial<TallySettings> | null;
  invoices: ExportInvoice[];
  payments: ExportPayment[];
  exported: { guid: string; first_exported_at: string }[];
  exported_then_deleted: { number: string; invoice_date: string; exported_at: string }[];
  report: { invoices: number; taxable: number | string; cgst: number | string; sgst: number | string; igst: number | string; total: number | string } | null;
}

/** Rupees (number or numeric text) to integer paise, half away from zero. */
export const paise = (v: unknown) => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? Math.round(Math.abs(n) * 100) * Math.sign(n) : 0;
};

// --- XML pieces (the kit's, unchanged) ------------------------------------

const x = (s: unknown) => escapeHtml(s);
const amt = (p: number) => (p / 100).toFixed(2);
/** A stored date "2026-11-26" as YYYYMMDD; a timestamp in Indian time. */
const date = (d: string | Date) => {
  if (typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d)) return d.replaceAll('-', '');
  const p = istParts(new Date(d));
  return `${p.y}${String(p.m).padStart(2, '0')}${String(p.d).padStart(2, '0')}`;
};

/** A line of a ledger. Debits are negative with ISDEEMEDPOSITIVE Yes, as Tally writes them. */
const line = (tag: 'LEDGERENTRIES.LIST' | 'ALLLEDGERENTRIES.LIST', name: string, p: number, debit: boolean, inner = '') =>
  `<${tag}><LEDGERNAME>${x(name)}</LEDGERNAME><ISDEEMEDPOSITIVE>${debit ? 'Yes' : 'No'}</ISDEEMEDPOSITIVE><AMOUNT>${debit ? '-' : ''}${amt(Math.abs(p))}</AMOUNT>${inner}</${tag}>`;
/** Invoice view (Sales, Credit Note). */
const ledger = (name: string, p: number, debit: boolean, inner = '') => line('LEDGERENTRIES.LIST', name, p, debit, inner);
/** Accounting view (Receipt, Payment, Journal, Contra). */
const accLedger = (name: string, p: number, debit: boolean, inner = '') => line('ALLLEDGERENTRIES.LIST', name, p, debit, inner);
const bill = (ref: string, kind: 'New Ref' | 'Agst Ref', p: number, debit: boolean, days?: number | null) =>
  `<BILLALLOCATIONS.LIST><NAME>${x(ref)}</NAME><BILLTYPE>${kind}</BILLTYPE>${days != null ? `<BILLCREDITPERIOD>${days} Days</BILLCREDITPERIOD>` : ''}<AMOUNT>${debit ? '-' : ''}${amt(Math.abs(p))}</AMOUNT></BILLALLOCATIONS.LIST>`;
const msg = (inner: string) => `<TALLYMESSAGE xmlns:UDF="TallyUDF">${inner}</TALLYMESSAGE>`;

/** The stable GUID of a voucher: the same database row always gives the same GUID. */
export const tallyGuid = (kind: 'sales' | 'receipt' | 'creditnote', id: string) => `simplek-${kind}-${id}`;
const ids = (guid: string) => ` REMOTEID="${x(guid)}"`;
const guidTag = (guid: string) => `<GUID>${x(guid)}</GUID>`;

// --- Names ----------------------------------------------------------------

type PartyKey = { name: string; key: string; mobile: string };
const partyOf = (name: string, c: ExportCustomer | null): PartyKey => ({
  name: name.trim() || 'Customer',
  key: c?.id ?? (c?.phone ? `phone:${c.phone}` : `name:${name.trim().toLowerCase()}`),
  mobile: c?.phone ?? '',
});

/** Rule 10: two customers with the same name get the mobile number added. */
function partyNames(parties: PartyKey[]) {
  const byName = new Map<string, Set<string>>();
  for (const p of parties) byName.set(p.name, (byName.get(p.name) ?? new Set()).add(p.key));
  return (p: PartyKey) => ((byName.get(p.name)?.size ?? 0) > 1 && p.mobile ? `${p.name} (${p.mobile})` : p.name);
}

const isService = (it: ExportItem) => it.product_type === 'service';

// --- One invoice ----------------------------------------------------------

interface Line {
  it: ExportItem;
  amount: number;
  rate: number;
  service: boolean;
  tax: number;
  cgst: number;
  sgst: number;
  igst: number;
}

/**
 * One invoice's lines (the kit's `invoiceLines`). The item amount is the
 * invoice's own line value (rule 5), never rate x quantity; any difference
 * of rounding goes to Round Off. Simplek has no discounts yet, so the
 * kit's discount paths are dormant (rupeeDiscount is always 0).
 */
export function invoiceLines(inv: ExportInvoice, gst: boolean, intraState: boolean) {
  const items: Line[] = inv.items.map((it) => {
    const tax = gst ? paise(it.tax_amount) : 0;
    let cgst = gst ? paise(it.cgst_amount) : 0;
    let sgst = gst ? paise(it.sgst_amount) : 0;
    let igst = gst ? paise(it.igst_amount) : 0;
    // Lines saved before the paise rule may not carry the split: CGST is
    // half, rounded half-up, SGST the rest (B3); IGST the whole.
    if (gst && cgst + sgst + igst !== tax) {
      if (intraState) {
        cgst = Math.round(tax / 2);
        sgst = tax - cgst;
        igst = 0;
      } else {
        cgst = 0;
        sgst = 0;
        igst = tax;
      }
    }
    return { it, amount: paise(it.taxable_amount), rate: gst ? Number(it.gst_rate ?? 0) : 0, service: isService(it), tax, cgst, sgst, igst };
  });
  const rupeeDiscount = 0;
  const tax = items.reduce((a, l) => a + l.cgst + l.sgst + l.igst, 0);
  const itemsTotal = items.reduce((a, l) => a + l.amount, 0);
  // Everything must add up to the invoice; any difference of rounding goes to Round Off.
  const roundOff = paise(inv.total_amount) - (itemsTotal - rupeeDiscount + tax);
  return { items, rupeeDiscount, roundOff };
}

/** The stock-item name of a line: the product's name, with its HSN when two products share a name. */
function stockNames(invoices: ExportInvoice[]) {
  const byName = new Map<string, Set<string>>();
  const keyOf = (it: ExportItem) => it.product_id ?? `free:${it.item_name.trim().toLowerCase()}`;
  const nameOf = (it: ExportItem) => (it.product_name ?? it.item_name).trim() || 'Item';
  for (const inv of invoices) for (const it of inv.items) if (!isService(it)) {
    byName.set(nameOf(it), (byName.get(nameOf(it)) ?? new Set()).add(keyOf(it)));
  }
  return (it: ExportItem) => {
    const n = nameOf(it);
    return (byName.get(n)?.size ?? 0) > 1 && it.hsn_sac_code ? `${n} (${it.hsn_sac_code})` : n;
  };
}

type Names = ReturnType<typeof tallyLedgers>;

function salesLedgerOf(N: Names, gst: boolean, l: Line, intraState: boolean) {
  if (!gst) return N.L.sales;
  const R = N.rate(l.rate);
  return l.service ? (intraState ? R.serviceLocal : R.serviceInterstate) : intraState ? R.salesLocal : R.salesInterstate;
}

function inventory(N: Names, stockName: string, salesLedger: string, l: Line, outward: boolean) {
  const unit = N.unit(l.it.uqc_code ?? l.it.product_uqc);
  const q = ` ${Number(l.it.quantity)} ${unit}`;
  const sign = outward ? '' : '-';
  return `<ALLINVENTORYENTRIES.LIST><STOCKITEMNAME>${x(stockName)}</STOCKITEMNAME><ISDEEMEDPOSITIVE>${outward ? 'No' : 'Yes'}</ISDEEMEDPOSITIVE><RATE>${amt(paise(l.it.unit_price))}/${x(unit)}</RATE><AMOUNT>${sign}${amt(l.amount)}</AMOUNT><ACTUALQTY>${q}</ACTUALQTY><BILLEDQTY>${q}</BILLEDQTY><ACCOUNTINGALLOCATIONS.LIST><LEDGERNAME>${x(salesLedger)}</LEDGERNAME><ISDEEMEDPOSITIVE>${outward ? 'No' : 'Yes'}</ISDEEMEDPOSITIVE><AMOUNT>${sign}${amt(l.amount)}</AMOUNT></ACCOUNTINGALLOCATIONS.LIST></ALLINVENTORYENTRIES.LIST>`;
}

/** Credit days: due date minus invoice date (T2.13); none without a due date. */
const creditDays = (inv: ExportInvoice) => {
  if (!inv.due_date) return null;
  const days = Math.round((Date.parse(inv.due_date) - Date.parse(inv.invoice_date)) / 86400000);
  return days >= 0 ? days : 0;
};

/** Sales (outward) or Credit Note (the reverse), in invoice view (rule 1). */
function itemVoucher(
  N: Names,
  gst: boolean,
  stockName: (it: ExportItem) => string,
  kind: 'Sales' | 'Credit Note',
  guid: string,
  number: string,
  when: string,
  party: string,
  inv: ExportInvoice,
  intraState: boolean,
  amountPaise: number,
  narration: string,
  billRef: { name: string; type: 'New Ref' | 'Agst Ref'; days?: number | null },
) {
  const sale = kind === 'Sales';
  const lines = invoiceLines(inv, gst, intraState);
  const stock = N.itemsAs === 'stock';
  // Ledger lines (services, or every line with "Ledger lines only"),
  // added up per sales ledger.
  const ledgerTotals = new Map<string, number>();
  for (const l of lines.items) {
    if (stock && !l.service) continue;
    const name = salesLedgerOf(N, gst, l, intraState);
    ledgerTotals.set(name, (ledgerTotals.get(name) ?? 0) + l.amount);
  }
  // One tax line per rate (T2.4).
  const taxLines: string[] = [];
  if (gst) {
    const byRate = new Map<number, { cgst: number; sgst: number; igst: number }>();
    for (const l of lines.items) {
      const t = byRate.get(l.rate) ?? { cgst: 0, sgst: 0, igst: 0 };
      t.cgst += l.cgst;
      t.sgst += l.sgst;
      t.igst += l.igst;
      byRate.set(l.rate, t);
    }
    for (const [rate, t] of [...byRate.entries()].sort((a, b) => a[0] - b[0])) {
      const R = N.rate(rate);
      if (t.cgst) taxLines.push(ledger(R.cgst, t.cgst, !sale));
      if (t.sgst) taxLines.push(ledger(R.sgst, t.sgst, !sale));
      if (t.igst) taxLines.push(ledger(R.igst, t.igst, !sale));
    }
  }
  const parts = [
    ledger(party, amountPaise, sale, bill(billRef.name, billRef.type, amountPaise, sale, billRef.days)),
    ...lines.items
      .filter((l) => stock && !l.service)
      .map((l) => inventory(N, stockName(l.it), salesLedgerOf(N, gst, l, intraState), l, sale)),
    ...[...ledgerTotals.entries()].filter(([, p]) => p).map(([name, p]) => ledger(name, p, !sale)),
    ...(lines.rupeeDiscount ? [ledger(N.L.discount, lines.rupeeDiscount, sale)] : []),
    ...taxLines,
    ...(lines.roundOff ? [ledger(N.L.roundOff, lines.roundOff, sale ? lines.roundOff < 0 : lines.roundOff > 0)] : []),
  ];
  const state = inv.customer?.state || inv.place_of_supply || '';
  const gstin = gst ? (inv.customer_gstin || '').trim() : '';
  return msg(
    `<VOUCHER${ids(guid)} VCHTYPE="${kind}" ACTION="Create" OBJVIEW="Invoice Voucher View">${guidTag(guid)}<DATE>${date(when)}</DATE><VOUCHERTYPENAME>${kind}</VOUCHERTYPENAME><VOUCHERNUMBER>${x(number)}</VOUCHERNUMBER><REFERENCE>${x(inv.invoice_number)}</REFERENCE><PARTYLEDGERNAME>${x(party)}</PARTYLEDGERNAME><PARTYNAME>${x(party)}</PARTYNAME><BASICBUYERNAME>${x(inv.customer_name)}</BASICBUYERNAME><STATENAME>${x(state)}</STATENAME>${gst ? `<PLACEOFSUPPLY>${x(inv.place_of_supply || state)}</PLACEOFSUPPLY>` : ''}${gstin ? `<PARTYGSTIN>${x(gstin)}</PARTYGSTIN>` : ''}<ISINVOICE>Yes</ISINVOICE><PERSISTEDVIEW>Invoice Voucher View</PERSISTEDVIEW><NARRATION>${x(narration)}</NARRATION>${parts.join('')}</VOUCHER>`,
  );
}

/** A Receipt in accounting view (rule 2): the customer credited Agst Ref the invoice, the cash, bank or UPI ledger debited. */
export function receiptVoucher(guid: string, number: string, when: string, party: string, payLedger: string, p: number, invoiceNumber: string, narration: string) {
  return msg(
    `<VOUCHER${ids(guid)} VCHTYPE="Receipt" ACTION="Create" OBJVIEW="Accounting Voucher View">${guidTag(guid)}<DATE>${date(when)}</DATE><VOUCHERTYPENAME>Receipt</VOUCHERTYPENAME><VOUCHERNUMBER>${x(number)}</VOUCHERNUMBER><PARTYLEDGERNAME>${x(party)}</PARTYLEDGERNAME><NARRATION>${x(narration)}</NARRATION><PERSISTEDVIEW>Accounting Voucher View</PERSISTEDVIEW>${accLedger(party, p, false, bill(invoiceNumber, 'Agst Ref', p, false))}${accLedger(payLedger, p, true)}</VOUCHER>`,
  );
}

/** T2.6: cash -> Cash, upi -> UPI receipts, bank transfer, card and cheque -> Bank. */
const PAY_LEDGER = (L: TallyLedgers, method: string | null) => (method === 'cash' ? L.cash : method === 'upi' ? L.upi : L.bank);
const METHOD_WORDS: Record<string, string> = { cash: 'cash', upi: 'UPI', bank_transfer: 'bank transfer', card: 'card', cheque: 'cheque' };

// --- Masters (created only when missing, rule 7) --------------------------

function ledgerMaster(name: string, parent: string, inner = '') {
  return msg(`<LEDGER NAME="${x(name)}" ACTION="Create"><NAME.LIST><NAME>${x(name)}</NAME></NAME.LIST><PARENT>${x(parent)}</PARENT>${inner}</LEDGER>`);
}
const taxMaster = (name: string, head: 'Central Tax' | 'State Tax' | 'Integrated Tax', rate: number) =>
  ledgerMaster(name, 'Duties & Taxes', `<TAXTYPE>GST</TAXTYPE><GSTDUTYHEAD>${head}</GSTDUTYHEAD><RATEOFTAXCALCULATION>${pct(rate)}</RATEOFTAXCALCULATION><ISBILLWISEON>No</ISBILLWISEON>`);
const salesMaster = (name: string, gst: boolean, supply: 'Goods' | 'Services') =>
  ledgerMaster(name, 'Sales Accounts', gst
    ? `<GSTAPPLICABLE>&#4; Applicable</GSTAPPLICABLE><GSTTYPEOFSUPPLY>${supply}</GSTTYPEOFSUPPLY><ISBILLWISEON>No</ISBILLWISEON>`
    : `<GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE><ISBILLWISEON>No</ISBILLWISEON>`);

const stockItemMaster = (name: string, unit: string, gst: boolean, hsn: string, rate: number) =>
  msg(
    gst
      ? `<STOCKITEM NAME="${x(name)}" ACTION="Create"><NAME.LIST><NAME>${x(name)}</NAME></NAME.LIST><BASEUNITS>${x(unit)}</BASEUNITS><GSTAPPLICABLE>&#4; Applicable</GSTAPPLICABLE><GSTDETAILS.LIST><APPLICABLEFROM>20260401</APPLICABLEFROM><CALCULATIONTYPE>On Value</CALCULATIONTYPE><HSNCODE>${x(hsn)}</HSNCODE><TAXABILITY>${rate ? 'Taxable' : 'Nil Rated'}</TAXABILITY><STATEWISEDETAILS.LIST><STATENAME>&#4; Any</STATENAME><RATEDETAILS.LIST><GSTRATEDUTYHEAD>Central Tax</GSTRATEDUTYHEAD><GSTRATE>${pct(rate / 2)}</GSTRATE></RATEDETAILS.LIST><RATEDETAILS.LIST><GSTRATEDUTYHEAD>State Tax</GSTRATEDUTYHEAD><GSTRATE>${pct(rate / 2)}</GSTRATE></RATEDETAILS.LIST><RATEDETAILS.LIST><GSTRATEDUTYHEAD>Integrated Tax</GSTRATEDUTYHEAD><GSTRATE>${pct(rate)}</GSTRATE></RATEDETAILS.LIST></STATEWISEDETAILS.LIST></GSTDETAILS.LIST></STOCKITEM>`
      : `<STOCKITEM NAME="${x(name)}" ACTION="Create"><NAME.LIST><NAME>${x(name)}</NAME></NAME.LIST><BASEUNITS>${x(unit)}</BASEUNITS><GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE></STOCKITEM>`,
  );

/**
 * The fixed masters (the kit's `fixedMasters`): units and stock items, the
 * sales ledgers and tax ledgers of every rate used, Round Off, Cash, Bank
 * and UPI. Discount Allowed is not written while Simplek has no discounts.
 */
export function fixedMasters(N: Names, gst: boolean, invoices: ExportInvoice[], intra: (inv: ExportInvoice) => boolean, stockName: (it: ExportItem) => string, withDiscount = false) {
  const unique = <T extends { name: string }>(list: T[]) => list.filter((m, i) => list.findIndex((o) => o.name === m.name) === i);
  const units: { name: string; xml: string }[] = [];
  const stock: { name: string; xml: string }[] = [];
  const sales: { name: string; xml: string }[] = [];
  const taxes: { name: string; xml: string }[] = [];
  for (const inv of invoices) {
    const intraState = intra(inv);
    for (const l of invoiceLines(inv, gst, intraState).items) {
      const ledgerName = salesLedgerOf(N, gst, l, intraState);
      sales.push({ name: ledgerName, xml: salesMaster(ledgerName, gst, l.service ? 'Services' : 'Goods') });
      if (N.itemsAs === 'stock' && !l.service) {
        const unit = N.unit(l.it.uqc_code ?? l.it.product_uqc);
        units.push({ name: unit, xml: msg(`<UNIT NAME="${x(unit)}" ACTION="Create"><NAME>${x(unit)}</NAME><ISSIMPLEUNIT>Yes</ISSIMPLEUNIT></UNIT>`) });
        const rate = gst ? Number(l.it.product_gst_rate ?? l.it.gst_rate ?? 0) : 0;
        const name = stockName(l.it);
        stock.push({ name, xml: stockItemMaster(name, unit, gst, l.it.hsn_sac_code ?? '', rate) });
      }
      if (gst && l.rate) {
        const R = N.rate(l.rate);
        if (intraState) {
          taxes.push({ name: R.cgst, xml: taxMaster(R.cgst, 'Central Tax', l.rate / 2) });
          taxes.push({ name: R.sgst, xml: taxMaster(R.sgst, 'State Tax', l.rate / 2) });
        } else {
          taxes.push({ name: R.igst, xml: taxMaster(R.igst, 'Integrated Tax', l.rate) });
        }
      }
    }
  }
  const ledgers = unique([
    ...sales,
    ...taxes,
    { name: N.L.roundOff, xml: ledgerMaster(N.L.roundOff, 'Indirect Expenses', '<GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE>') },
    { name: N.L.cash, xml: ledgerMaster(N.L.cash, 'Cash-in-Hand') },
    { name: N.L.bank, xml: ledgerMaster(N.L.bank, 'Bank Accounts') },
    { name: N.L.upi, xml: ledgerMaster(N.L.upi, 'Bank Accounts') },
    ...(withDiscount
      ? [{
          name: N.L.discount,
          // Include in assessable value calculation for: GST; Appropriate to: Goods; Method of calculation: Based on Value.
          xml: ledgerMaster(N.L.discount, 'Indirect Expenses', '<GSTAPPLICABLE>&#4; Not Applicable</GSTAPPLICABLE><APPROPRIATEFOR>GST</APPROPRIATEFOR><GSTAPPROPRIATETO>Goods</GSTAPPROPRIATETO><EXCISEALLOCTYPE>Based on Value</EXCISEALLOCTYPE>'),
        }]
      : []),
  ]);
  return [...unique(units).map((u) => u.xml), ...unique(stock).map((s) => s.xml), ...ledgers.map((l) => l.xml)];
}

// --- The export -----------------------------------------------------------

/** Credit notes stay in the kit's code path, dormant until Simplek has them. */
export type TallyKind = 'sales' | 'receipts' | 'creditnotes';
export const TALLY_KINDS: TallyKind[] = ['sales', 'receipts'];

export interface VoucherRow {
  guid: string;
  kind: 'sales' | 'receipt' | 'creditnote';
  number: string;
  date: string;
  party: string;
  amountPaise: number;
  xml: string;
}

export function tallyExport(data: ExportData, kinds: TallyKind[] = TALLY_KINDS) {
  const N = tallyLedgers(data.settings);
  const gst = data.gst;
  const company = (data.settings?.company || data.company || '').trim();
  const want = (k: TallyKind) => kinds.includes(k);
  const invs = want('sales') ? data.invoices : [];
  const paid = want('receipts') ? data.payments : [];
  const intra = (inv: ExportInvoice) => inv.tax_type !== 'igst';

  const parties = [
    ...invs.map((i) => partyOf(i.customer_name, i.customer)),
    ...paid.map((p) => partyOf(p.customer_name, p.customer)),
  ];
  const party = partyNames(parties);
  const stockName = stockNames(invs);

  // Masters: the fixed ledgers, the units and stock items, and each customer under Sundry Debtors.
  const customers = new Map<string, { name: string; c: ExportCustomer | null; gstin: string; state: string }>();
  for (const i of invs) {
    customers.set(party(partyOf(i.customer_name, i.customer)), { name: i.customer_name, c: i.customer, gstin: (i.customer_gstin || i.customer?.gstin || '').trim(), state: i.customer?.state || i.place_of_supply || data.business_state || '' });
  }
  for (const p of paid) {
    const name = party(partyOf(p.customer_name, p.customer));
    if (!customers.has(name)) customers.set(name, { name: p.customer_name, c: p.customer, gstin: (p.customer?.gstin || '').trim(), state: p.customer?.state || data.business_state || '' });
  }
  const masters = [
    ...fixedMasters(N, gst, invs, intra, stockName),
    ...[...customers.entries()].map(([name, cu]) => {
      const address = cu.c?.address ?? '';
      const pin = /\b(\d{6})\b/.exec(address);
      const gstin = gst ? cu.gstin : '';
      return msg(
        `<LEDGER NAME="${x(name)}" ACTION="Create"><NAME.LIST><NAME>${x(name)}</NAME></NAME.LIST><PARENT>${x(N.L.customersGroup)}</PARENT><ISBILLWISEON>Yes</ISBILLWISEON><ADDRESS.LIST><ADDRESS>${x(address)}</ADDRESS></ADDRESS.LIST><LEDSTATENAME>${x(cu.state)}</LEDSTATENAME><COUNTRYNAME>India</COUNTRYNAME>${pin ? `<PINCODE>${pin[1]}</PINCODE>` : ''}<LEDGERMOBILE>${x(cu.c?.phone ?? '')}</LEDGERMOBILE>${cu.c?.email ? `<EMAIL>${x(cu.c.email)}</EMAIL>` : ''}<GSTREGISTRATIONTYPE>${gstin ? 'Regular' : 'Unregistered/Consumer'}</GSTREGISTRATIONTYPE>${gstin ? `<PARTYGSTIN>${x(gstin)}</PARTYGSTIN>` : ''}</LEDGER>`,
      );
    }),
  ];

  const vouchers: VoucherRow[] = [];
  for (const i of invs) {
    const total = paise(i.total_amount);
    if (!total) continue; // rule 9
    const guid = tallyGuid('sales', i.id);
    const p = party(partyOf(i.customer_name, i.customer));
    vouchers.push({
      guid, kind: 'sales', number: i.invoice_number, date: i.invoice_date, party: p, amountPaise: total,
      xml: itemVoucher(N, gst, stockName, 'Sales', guid, i.invoice_number, i.invoice_date, p, i, intra(i), total, `Invoice ${i.invoice_number}`, { name: i.invoice_number, type: 'New Ref', days: creditDays(i) }),
    });
  }
  for (const pay of paid) {
    const amount = paise(pay.amount);
    if (!amount) continue; // rule 9
    const guid = tallyGuid('receipt', pay.id);
    const p = party(partyOf(pay.customer_name, pay.customer));
    const number = `R-${pay.invoice_number}-${pay.sequence}`;
    const narration = `Paid by ${METHOD_WORDS[pay.payment_method ?? ''] ?? 'cash'} against ${pay.invoice_number}`;
    vouchers.push({ guid, kind: 'receipt', number, date: pay.payment_date, party: p, amountPaise: amount, xml: receiptVoucher(guid, number, pay.payment_date, p, PAY_LEDGER(N.L, pay.payment_method), amount, pay.invoice_number, narration) });
  }

  // "Already exported on [date]", per voucher.
  const exportedOn = new Map(data.exported.map((b) => [b.guid, b.first_exported_at]));
  const sales = vouchers.filter((v) => v.kind === 'sales');
  const receipts = vouchers.filter((v) => v.kind === 'receipt');
  const credit = vouchers.filter((v) => v.kind === 'creditnote');

  // The check summary, against Simplek's Reports for the same dates (B2).
  const totals = { taxable: 0, cgst: 0, sgst: 0, igst: 0, total: 0, quantity: 0 };
  for (const i of invs) {
    const l = invoiceLines(i, gst, intra(i));
    totals.taxable += l.items.reduce((a, it) => a + it.amount, 0);
    totals.cgst += l.items.reduce((a, it) => a + it.cgst, 0);
    totals.sgst += l.items.reduce((a, it) => a + it.sgst, 0);
    totals.igst += l.items.reduce((a, it) => a + it.igst, 0);
    totals.total += paise(i.total_amount);
    totals.quantity += i.items.reduce((a, it) => a + Number(it.quantity ?? 0), 0);
  }
  const r = data.report;
  const summary = {
    vouchers: { sales: sales.length, receipts: receipts.length, creditNotes: credit.length, total: vouchers.length },
    quantity: { sold: Number(totals.quantity.toFixed(3)), returned: 0 },
    taxablePaise: totals.taxable,
    cgstPaise: totals.cgst,
    sgstPaise: totals.sgst,
    igstPaise: totals.igst,
    totalPaise: totals.total,
    receiptsPaise: receipts.reduce((a, v) => a + v.amountPaise, 0),
    matchesReports: r && want('sales')
      ? Number(r.invoices) === invs.length &&
        paise(r.taxable) === totals.taxable &&
        paise(r.cgst) === totals.cgst &&
        paise(r.sgst) === totals.sgst &&
        paise(r.igst) === totals.igst &&
        paise(r.total) === totals.total
      : null,
    exportedThenDeleted: data.exported_then_deleted.map((i) => ({ number: i.number, issuedAt: i.invoice_date, exportedAt: i.exported_at })),
    list: vouchers.map((v) => ({ kind: v.kind, number: v.number, date: v.date, party: v.party, amountPaise: v.amountPaise, exportedAt: exportedOn.get(v.guid) ?? null })),
  };

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY>
<IMPORTDATA><REQUESTDESC><REPORTNAME>All Masters</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${x(company)}</SVCURRENTCOMPANY></STATICVARIABLES></REQUESTDESC><REQUESTDATA>
${masters.join('\n')}
</REQUESTDATA></IMPORTDATA>
<IMPORTDATA><REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${x(company)}</SVCURRENTCOMPANY></STATICVARIABLES></REQUESTDESC><REQUESTDATA>
${[...sales, ...receipts, ...credit].map((v) => v.xml).join('\n')}
</REQUESTDATA></IMPORTDATA>
</BODY></ENVELOPE>
`;
  return { xml, summary, vouchers, count: { sales: sales.length, creditNotes: credit.length } };
}

/** `Tally_<Business>_<from>_<to>.xml` (T4.1). */
export function tallyFileName(business: string, from: string, to: string) {
  const safe = business.replace(/[^A-Za-z0-9]+/g, '_').replace(/^_+|_+$/g, '') || 'Business';
  return `Tally_${safe}_${from}_${to}.xml`;
}
