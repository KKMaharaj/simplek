/**
 * Writes the sample Tally files in docs/tally-samples/ from the test
 * businesses in fixtures.ts (change request 26 Nov 2026, Done checklist).
 * Run from the project folder:
 *   node supabase/functions/tally-export/make_samples.ts
 * (or deno run --allow-write supabase/functions/tally-export/make_samples.ts)
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { gstBusiness, nonGstBusiness } from './fixtures.ts';
import { type ExportData, tallyExport } from './tally.ts';

const out = 'docs/tally-samples';
mkdirSync(out, { recursive: true });

const ledgerOnly = (): ExportData => ({ ...gstBusiness(), settings: { itemsAs: 'ledger' } });
const files: [string, ExportData, ('sales' | 'receipts')[]][] = [
  ['Simplek-GST-sales-and-receipts.xml', gstBusiness(), ['sales', 'receipts']],
  ['Simplek-GST-sales-only.xml', gstBusiness(), ['sales']],
  ['Simplek-GST-receipts-only.xml', gstBusiness(), ['receipts']],
  ['Simplek-GST-ledger-lines-only.xml', ledgerOnly(), ['sales', 'receipts']],
  ['Simplek-non-GST.xml', nonGstBusiness(), ['sales', 'receipts']],
];
for (const [name, data, kinds] of files) {
  const { xml, summary } = tallyExport(data, kinds);
  writeFileSync(`${out}/${name}`, xml);
  console.log(`${name}: ${summary.vouchers.total} vouchers, total ₹${(summary.totalPaise / 100).toFixed(2)}, receipts ₹${(summary.receiptsPaise / 100).toFixed(2)}`);
}
