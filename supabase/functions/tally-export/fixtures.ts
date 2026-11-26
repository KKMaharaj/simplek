/**
 * Test businesses for the Tally export tests and the sample files in
 * docs/tally-samples/ (made by make_samples.ts). Shaped exactly like the
 * JSON tally_export_data returns.
 */
import type { ExportCustomer, ExportData, ExportInvoice, ExportItem, ExportPayment } from './tally.ts';

export const customer = (name: string, over: Partial<ExportCustomer> = {}): ExportCustomer => ({
  id: over.id ?? `cust-${name.toLowerCase().replace(/\W+/g, '-')}`,
  name,
  phone: '9876500001',
  email: null,
  address: '12, Main Road, Shivamogga, Karnataka 577201',
  gstin: null,
  state: 'Karnataka',
  ...over,
});

export const item = (over: Partial<ExportItem> & { taxable: number; rate?: number; intra?: boolean }): ExportItem => {
  const rate = over.rate ?? 18;
  const taxable = over.taxable;
  // In whole paise, as Simplek stores them (B3): CGST = half, half-up.
  const taxableP = Math.round(taxable * 100);
  const taxP = Math.round((taxableP * rate) / 100);
  const cgstP = Math.round(taxP / 2);
  const tax = taxP / 100;
  const cgst = cgstP / 100;
  const intra = over.intra ?? true;
  return {
    product_id: over.product_id ?? 'prod-chair',
    item_name: over.item_name ?? 'Steel Chair',
    quantity: over.quantity ?? 1,
    uqc_code: over.uqc_code ?? 'NOS',
    unit_price: over.unit_price ?? taxable / Number(over.quantity ?? 1),
    taxable_amount: taxable,
    gst_rate: rate,
    tax_amount: tax,
    cgst_amount: intra ? cgst : 0,
    sgst_amount: intra ? (taxP - cgstP) / 100 : 0,
    igst_amount: intra ? 0 : tax,
    product_type: over.product_type ?? 'product',
    hsn_sac_code: over.hsn_sac_code ?? '94017100',
    product_name: over.product_name ?? over.item_name ?? 'Steel Chair',
    product_uqc: over.product_uqc ?? 'NOS',
    product_gst_rate: over.product_gst_rate ?? rate,
  };
};

export function invoice(id: string, number: string, items: ExportItem[], over: Partial<ExportInvoice> = {}): ExportInvoice {
  const taxable = items.reduce((a, i) => a + Number(i.taxable_amount), 0);
  const tax = items.reduce((a, i) => a + Number(i.tax_amount), 0);
  return {
    id,
    invoice_number: number,
    invoice_date: '2026-11-20',
    due_date: '2026-11-27',
    customer_name: over.customer?.name ?? 'Kiran Traders',
    customer_gstin: null,
    place_of_supply: 'Karnataka',
    tax_type: 'cgst_sgst',
    total_amount: Math.round(taxable + tax),
    customer: customer(over.customer?.name ?? 'Kiran Traders'),
    items,
    ...over,
  };
}

export const payment = (id: string, inv: ExportInvoice, amount: number, sequence: number, method = 'upi'): ExportPayment => ({
  id,
  invoice_id: inv.id,
  invoice_number: inv.invoice_number,
  payment_date: '2026-11-22',
  amount,
  payment_method: method,
  sequence,
  customer_name: inv.customer_name,
  customer: inv.customer,
});

/** A GST business in Karnataka with every Simplek case. */
export function gstBusiness(): ExportData {
  const mixedRates = invoice('11111111-1111-1111-1111-111111111111', 'INV/2026-27/01', [
    item({ taxable: 1000, rate: 5, product_id: 'prod-tea', item_name: 'Tea 1 kg', hsn_sac_code: '0902', uqc_code: 'KGS', quantity: 2, unit_price: 500 }),
    item({ taxable: 2000, rate: 18, quantity: 4, unit_price: 500 }),
  ], { customer_gstin: '29AAGCB7383J1Z4', customer: customer('Kiran Traders', { gstin: '29AAGCB7383J1Z4' }) });
  const services = invoice('22222222-2222-2222-2222-222222222222', 'INV/2026-27/02', [
    item({ taxable: 1500, rate: 18, product_id: 'svc-install', item_name: 'Installation', product_type: 'service', hsn_sac_code: '998719', uqc_code: null }),
  ], { customer: customer('Asha Rao', { phone: '9876500002' }) });
  const mixed = invoice('33333333-3333-3333-3333-333333333333', 'INV/2026-27/03', [
    item({ taxable: 999.99, rate: 18, quantity: 3, unit_price: 333.33 }),
    item({ taxable: 500, rate: 18, product_id: 'svc-install', item_name: 'Installation', product_type: 'service', hsn_sac_code: '998719', uqc_code: null }),
  ], { customer: customer('Asha Rao', { id: 'cust-asha-2', phone: '9876500003' }) });
  const inter = invoice('44444444-4444-4444-4444-444444444444', 'INV/2026-27/04', [
    item({ taxable: 3000, rate: 12, product_id: 'prod-table', item_name: 'Table', hsn_sac_code: '94036000', intra: false, quantity: 1, unit_price: 3000 }),
  ], { tax_type: 'igst', place_of_supply: 'Kerala', customer: customer('Kochi Stores', { state: 'Kerala', address: '1, Road, Kochi, Kerala 682001', phone: '9876500004' }) });
  // 5% on ₹101: tax 5.05, total 106 (round off −0.05).
  const roundOff = invoice('55555555-5555-5555-5555-555555555555', 'INV/2026-27/05', [
    item({ taxable: 101, rate: 5, product_id: 'prod-tea', item_name: 'Tea 1 kg', hsn_sac_code: '0902', uqc_code: 'KGS', quantity: 1, unit_price: 101 }),
  ], { customer: customer('Kiran Traders', { gstin: '29AAGCB7383J1Z4' }), customer_gstin: '29AAGCB7383J1Z4', due_date: null });
  // Two products with the same name and different HSN.
  const sameName = invoice('66666666-6666-6666-6666-666666666666', 'INV/2026-27/06', [
    item({ taxable: 100, rate: 18, product_id: 'prod-bolt-a', item_name: 'Bolt', hsn_sac_code: '73181500' }),
    item({ taxable: 100, rate: 18, product_id: 'prod-bolt-b', item_name: 'Bolt', hsn_sac_code: '73181600' }),
  ], { customer: customer('Kiran Traders', { gstin: '29AAGCB7383J1Z4' }), customer_gstin: '29AAGCB7383J1Z4' });
  const invoices = [mixedRates, services, mixed, inter, roundOff, sameName];
  const total = (i: ExportInvoice) => Number(i.total_amount);
  return {
    company: 'Malnad Kitchen',
    gst: true,
    business_state: 'Karnataka',
    settings: null,
    invoices,
    payments: [
      // Two partial payments on one invoice.
      payment('aaaaaaa1-0000-0000-0000-000000000001', mixedRates, 1000, 1, 'cash'),
      payment('aaaaaaa1-0000-0000-0000-000000000002', mixedRates, total(mixedRates) - 1000, 2, 'upi'),
      payment('aaaaaaa1-0000-0000-0000-000000000003', inter, total(inter), 1, 'bank_transfer'),
    ],
    exported: [{ guid: 'simplek-sales-11111111-1111-1111-1111-111111111111', first_exported_at: '2026-11-21T05:00:00Z' }],
    exported_then_deleted: [{ number: 'INV/2026-27/00', invoice_date: '2026-11-19', exported_at: '2026-11-20T06:00:00Z' }],
    report: null,
  };
}

/** A business not registered under GST. */
export function nonGstBusiness(): ExportData {
  const inv = invoice('77777777-7777-7777-7777-777777777777', 'BILL/2026-27/01', [
    { ...item({ taxable: 1200, rate: 0, quantity: 2, unit_price: 600 }), gst_rate: 0, tax_amount: 0, cgst_amount: 0, sgst_amount: 0, igst_amount: 0, product_gst_rate: null },
    { ...item({ taxable: 300, rate: 0, product_id: 'svc-repair', item_name: 'Repair', product_type: 'service', hsn_sac_code: null, uqc_code: null }), gst_rate: 0, tax_amount: 0, cgst_amount: 0, sgst_amount: 0, igst_amount: 0 },
  ], { tax_type: 'none', place_of_supply: '', customer: customer('Walk-in Customer', { phone: '9876500009' }) });
  return {
    company: 'Ravi Repairs',
    gst: false,
    business_state: 'Karnataka',
    settings: null,
    invoices: [inv],
    payments: [payment('bbbbbbb1-0000-0000-0000-000000000001', inv, 1500, 1, 'cash')],
    exported: [],
    exported_then_deleted: [],
    report: null,
  };
}
