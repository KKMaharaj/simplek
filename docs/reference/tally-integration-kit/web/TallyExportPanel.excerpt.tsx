
const a = (p: number) => (p ? (p / 100).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : '');

/** Change 06.12, 07.3: what the Tally file can carry, separately or together. Never purchases. */
const TALLY_KINDS = [
  ['sales', 'Sales'],
  ['receipts', 'Receipts'],
  ['creditnotes', 'Credit notes'],
] as const;
interface TallySummary {
  vouchers: { sales: number; receipts: number; creditNotes: number; total: number };
  quantity: { sold: number; returned: number };
  taxablePaise: number;
  cgstPaise: number;
  sgstPaise: number;
  igstPaise: number;
  totalPaise: number;
  matchesReports: boolean | null;
  exportedThenDeleted: { number: string }[];
  list: { kind: 'sales' | 'receipt' | 'creditnote'; number: string; date: string; party: string; amountPaise: number; exportedAt: string | null }[];
}
const VOUCHER_KIND = { sales: 'Sales', receipt: 'Receipt', creditnote: 'Credit note' } as const;

// ... inside the component ...
  const [tFrom, setTFrom] = useState(`${month}-01`);
  const [tTo, setTTo] = useState(todayIso());
  const [tKinds, setTKinds] = useState<string[]>(TALLY_KINDS.map(([k]) => k));
  const [tSummary, setTSummary] = useState<TallySummary | null>(null);
  // Change 07.3: the vouchers for these dates, each with "already exported on [date]", before and after exporting.
  const tallyQs = `from=${tFrom}&to=${tTo}&kinds=${tKinds.join(',')}`;
  const loadTally = useCallback(() => {
    if (!tFrom || !tTo || !tKinds.length) return setTSummary(null);
    void api<TallySummary>(`/staff/billing/tally/summary?${tallyQs}`).then(setTSummary);
  }, [tallyQs, tFrom, tTo, tKinds.length]);
  useEffect(() => {
    if (tab !== 'tally') return;
    const t = window.setTimeout(loadTally, 250);
    return () => window.clearTimeout(t);
  }, [tab, loadTally]);
// ... in the JSX ...
        <Panel title="Tally export" className={cx('min-w-0 flex-[1_1_380px]', tab === 'tally' && 'border-purple')}>
          <div className="flex flex-col gap-4" data-testid="tally-export">
            {/* Change 06.12 */}
            <p className="m-0 text-ink-muted">
              For TallyPrime (Import &gt; Transactions, with masters): item invoices with stock, customer ledgers with their bills, receipts and credit
              notes. Purchases are entered directly in Tally. Importing the same voucher again updates it. Ledger names are in{' '}
              <a href="/staff/billing/settings" className="text-purple underline underline-offset-2">
                Settings
              </a>
              .
            </p>
            <fieldset className="m-0 flex flex-wrap gap-x-5 gap-y-2 border-0 p-0">
              <legend className="mb-1 text-[13px] font-medium">Export</legend>
              {TALLY_KINDS.map(([k, l]) => (
                <label key={k} className="inline-flex min-h-[32px] items-center gap-2 text-[15px]">
                  <input type="checkbox" className="h-5 w-5 accent-purple" checked={tKinds.includes(k)} onChange={(e) => setTKinds(e.target.checked ? [...tKinds, k] : tKinds.filter((x) => x !== k))} />
                  {l}
                </label>
              ))}
            </fieldset>
            <div className="flex flex-wrap gap-3">
              <label className="flex flex-col gap-1 text-[13px] font-medium">
                From
                <input type="date" value={tFrom} onChange={(e) => setTFrom(e.target.value)} className="h-11 min-w-0 max-w-full rounded-[6px] border border-field px-2.5 text-[15px]" />
              </label>
              <label className="flex flex-col gap-1 text-[13px] font-medium">
                To
                <input type="date" value={tTo} onChange={(e) => setTTo(e.target.value)} className="h-11 min-w-0 max-w-full rounded-[6px] border border-field px-2.5 text-[15px]" />
              </label>
            </div>
            <DownloadButton
              href={`/api/staff/billing/tally?from=${tFrom}&to=${tTo}&kinds=${tKinds.join(',')}`}
              shape="staff"
              className="self-start"
              done="File ready"
              onDone={loadTally}
            >
              Export for Tally
            </DownloadButton>
            {tSummary ? (
              <div className="flex flex-col gap-2 rounded-staff border border-line bg-ground p-4 text-[14px]" data-testid="tally-summary">
                <div className="font-bold">Check before importing</div>
                <div>
                  {tSummary.vouchers.total} vouchers: {tSummary.vouchers.sales} sales, {tSummary.vouchers.receipts} receipts, {tSummary.vouchers.creditNotes} credit notes
                </div>
                <div>
                  Quantity: {tSummary.quantity.sold} sold, {tSummary.quantity.returned} returned
                </div>
                <div>
                  Taxable {rupees(tSummary.taxablePaise)} · CGST {rupees(tSummary.cgstPaise)} · SGST {rupees(tSummary.sgstPaise)} · IGST {rupees(tSummary.igstPaise)} · Total{' '}
                  {rupees(tSummary.totalPaise)}
                </div>
                {tSummary.matchesReports != null ? (
                  <div className={tSummary.matchesReports ? 'font-bold text-mint-ink' : 'font-bold text-red'}>
                    {tSummary.matchesReports ? 'Equal to the sales report for these dates.' : 'Different from the sales report for these dates: check before importing.'}
                  </div>
                ) : null}
                {tSummary.exportedThenDeleted.length ? (
                  <div className="rounded-[8px] border border-red bg-red-soft p-3 text-red" role="alert" data-testid="tally-deleted-warning">
                    <div className="font-bold">Exported, then deleted: cancel these in Tally</div>
                    {tSummary.exportedThenDeleted.map((i) => (
                      <div key={i.number}>{i.number}</div>
                    ))}
                  </div>
                ) : null}
                {tSummary.list.length ? (
                  <div className="max-h-[320px] overflow-auto" data-testid="tally-vouchers">
                    <table className="w-full border-collapse text-[13px]">
                      <thead>
                        <tr className="text-left text-ink-muted">
                          <th className="py-1 pr-2 font-medium">Voucher</th>
                          <th className="py-1 pr-2 font-medium">Party</th>
                          <th className="py-1 pr-2 text-right font-medium">Amount</th>
                          <th className="py-1 font-medium">Tally</th>
                        </tr>
                      </thead>
                      <tbody>
                        {tSummary.list.map((v) => (
                          <tr key={`${v.kind}-${v.number}`} className="border-t border-line-soft" data-testid="tally-voucher">
                            <td className="py-1 pr-2">
                              {VOUCHER_KIND[v.kind]} {v.number}
                            </td>
                            <td className="py-1 pr-2">{v.party}</td>
                            <td className="py-1 pr-2 text-right tabular-nums">{rupees(v.amountPaise)}</td>
                            <td className="py-1">{v.exportedAt ? `Already exported on ${formatDate(v.exportedAt)}` : 'New'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                ) : (
                  <div className="text-ink-muted">No vouchers for these dates.</div>
                )}
              </div>
            ) : null}
          </div>
        </Panel>
