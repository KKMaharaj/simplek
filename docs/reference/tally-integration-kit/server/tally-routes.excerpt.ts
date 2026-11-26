/** Tally sales export for a date range: sales and credit notes, as Tally XML. */
const tallyQuery = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  kinds: z
    .string()
    .optional()
    .transform((v) => (v ? (v.split(',').filter((k) => (TALLY_KINDS as string[]).includes(k)) as TallyKind[]) : TALLY_KINDS)),
});
const TALLY_FILE: Record<string, string> = { sales: 'Sales', receipts: 'Receipts', creditnotes: 'CreditNotes' };

/** Change 06.12, 07.3: the Tally file (Sales, Receipts and Credit notes, separately or together; never purchases). */
billingRouter.get('/tally', ROLES.BILLING, async (req, res) => {
  const q = tallyQuery.parse(req.query);
  const { from, to } = rangeFrom(q);
  const out = await tallyExport(from, to, q.kinds, true);
  await audit({ type: 'staff', id: req.staff!.id }, 'report.tally', 'report', 'tally', { from: q.from, to: q.to, kinds: q.kinds, ...out.summary.vouchers });
  const label = q.kinds.length === 1 ? TALLY_FILE[q.kinds[0]] : q.kinds.length === TALLY_KINDS.length ? 'All' : q.kinds.map((k) => TALLY_FILE[k]).join('-');
  res.setHeader('Content-Type', 'application/xml; charset=utf-8');
  res.setHeader('Content-Disposition', disposition('attachment', `${rangeName(`Tally-${label}`, from, to)}.xml`));
  res.send(out.xml);
});

/** Change 06.12: the check summary for the same dates and kinds (vouchers, quantities, taxable value and tax, against the reports). */
billingRouter.get('/tally/summary', ROLES.BILLING, async (req, res) => {
  const q = tallyQuery.parse(req.query);
  const { from, to } = rangeFrom(q);
  res.json((await tallyExport(from, to, q.kinds, false)).summary);
});

/** Change 06.12: the Tally ledger names, one shared set (Business Profile and Settings, and Billing and Accounting > Settings). */
billingRouter.get('/tally-settings', ROLES.BILLING, async (_req, res) => {
  res.json({ ledgers: await tallyLedgers(), defaults: TALLY_DEFAULTS, labels: TALLY_LABELS, renames: await tallyRenames() });
});

billingRouter.put('/tally-settings', ROLES.BILLING, async (req, res) => {
  const shape = Object.fromEntries(Object.keys(TALLY_DEFAULTS).map((k) => [k, z.string().trim().min(1, 'Enter the name as in Tally').max(120)])) as Record<keyof typeof TALLY_DEFAULTS, z.ZodString>;
  const b = z.object(shape).partial().parse(req.body?.ledgers ?? {});
  res.json({ ledgers: await saveTallyLedgers(b, req.staff!.id), renames: await tallyRenames() });
});
