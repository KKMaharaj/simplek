describe('change 06.12: the Tally export', () => {
  /** Well-formed XML: every tag closes in order. */
  function wellFormed(xml: string) {
    const stack: string[] = [];
    for (const m of xml.replace(/<\?xml[^>]*\?>/, '').matchAll(/<(\/?)([A-Za-z][\w.:-]*)[^>]*?(\/?)>/g)) {
      if (m[3]) continue;
      if (!m[1]) stack.push(m[2]);
      else if (stack.pop() !== m[2]) return false;
    }
    return stack.length === 0;
  }
  /** The vouchers, each with the sum of its top-level ledger and inventory amounts (Tally needs zero). */
  function vouchers(xml: string) {
    return [...xml.matchAll(/<VOUCHER(?: REMOTEID="[^"]+")? VCHTYPE="([^"]+)"[\s\S]*?<\/VOUCHER>/g)].map((m) => {
      const body = m[0].replace(/<BILLALLOCATIONS\.LIST>[\s\S]*?<\/BILLALLOCATIONS\.LIST>/g, '').replace(/<ACCOUNTINGALLOCATIONS\.LIST>[\s\S]*?<\/ACCOUNTINGALLOCATIONS\.LIST>/g, '');
      const amounts = [...body.matchAll(/<AMOUNT>(-?[\d.]+)<\/AMOUNT>/g)].map((a) => Math.round(Number(a[1]) * 100));
      return { type: m[1], text: m[0], balance: amounts.reduce((a, b) => a + b, 0), number: /<VOUCHERNUMBER>([^<]+)</.exec(m[0])![1] };
    });
  }
  const today = () => isoDay(new Date()); // the IST day, as the reports use

  it('TL6: item invoices with quantity, discount %, the customer ledger and a New Ref bill; receipts against the bill; every voucher balances to the paisa', async () => {
    const pct = await offlineInvoice({ items: [{ productId: (await product()).id, quantity: 4, rate: 3333.33 }], discount: { type: 'percent', value: 10 }, paymentMode: null, customer: { name: 'Tally Percent', mobile: mobile(), email: 'tally@example.com', address: '5, Market Road, Shivamogga 577202' } });
    const amt = await offlineInvoice({ discount: { type: 'amount', value: 100 }, paymentMode: 'UPI' });
    const t = await accounts.get(`/api/staff/billing/tally?from=${today()}&to=${today()}`);
    expect(t.status).toBe(200);
    expect(t.headers['content-disposition']).toMatch(/Tally-All-/);
    expect(wellFormed(t.text)).toBe(true);
    const vs = vouchers(t.text);
    for (const v of vs) expect(v.balance, `${v.type} ${v.number}`).toBe(0);
    const sale = vs.find((v) => v.number === pct.invoiceNumber)!;
    expect(sale.text).toContain('OBJVIEW="Invoice Voucher View"');
    expect(sale.text).toMatch(/<STOCKITEMNAME>Rejwin, 1000 ml<\/STOCKITEMNAME>.*<RATE>3333\.33\/Nos<\/RATE><DISCOUNT>10<\/DISCOUNT>.*<ACTUALQTY> 4 Nos<\/ACTUALQTY><BILLEDQTY> 4 Nos<\/BILLEDQTY>/s);
    expect(sale.text).toContain('<PARTYLEDGERNAME>Tally Percent</PARTYLEDGERNAME>');
    expect(sale.text).toMatch(/<BILLTYPE>New Ref<\/BILLTYPE><BILLCREDITPERIOD>30 Days<\/BILLCREDITPERIOD>/);
    expect(t.text).toMatch(/<LEDGER NAME="Tally Percent" ACTION="Create"><NAME.LIST><NAME>Tally Percent<\/NAME><\/NAME.LIST><PARENT>Sundry Debtors<\/PARENT><ISBILLWISEON>Yes<\/ISBILLWISEON>/);
    expect(t.text).toMatch(/<STOCKITEM NAME="Rejwin, 1000 ml" ACTION="Create">.*<HSNCODE>30049011<\/HSNCODE>/s);
    // The unpaid invoice has no receipt; the UPI one has a receipt against its bill to the UPI ledger.
    expect(vs.some((v) => v.type === 'Receipt' && v.text.includes(pct.invoiceNumber))).toBe(false);
    const rcpt = vs.find((v) => v.type === 'Receipt' && v.text.includes(`<NAME>${amt.invoiceNumber}</NAME><BILLTYPE>Agst Ref</BILLTYPE>`))!;
    expect(rcpt.text).toContain('<LEDGERNAME>HDFC Bank (UPI)</LEDGERNAME>');
    // A rupee discount goes to Discount Allowed.
    expect(vs.find((v) => v.number === amt.invoiceNumber)!.text).toContain('<LEDGERNAME>Discount Allowed</LEDGERNAME>');
  });

  it('TL6: credit notes return quantity (no purchases: change 07.3); the summary equals the reports; exported-then-deleted invoices are listed', async () => {
    const p = await product();
    await accounts.post('/api/staff/billing/stock').send({ productId: p.id, quantity: 9, date: today(), purchaseInvoiceNumber: `TL6-${Date.now()}` });
    const { orderId, invoiceNumber } = await offlineInvoice();
    await admin.post(`/api/staff/orders/${orderId}/cancel`).send({ confirm: true, reason: 'Tally test' });
    // Change 07.3: purchases are never exported.
    const all = await accounts.get(`/api/staff/billing/tally?from=${today()}&to=${today()}`);
    expect(all.text).not.toContain('VCHTYPE="Purchase"');
    const cn = await accounts.get(`/api/staff/billing/tally?from=${today()}&to=${today()}&kinds=creditnotes`);
    expect(cn.text).toMatch(/<VOUCHER REMOTEID="[^"]+" VCHTYPE="Credit Note".*<ISDEEMEDPOSITIVE>Yes<\/ISDEEMEDPOSITIVE><RATE>[^<]+<\/RATE><AMOUNT>-[\d.]+<\/AMOUNT><ACTUALQTY> 2 Nos/s);
    const summary = (await accounts.get(`/api/staff/billing/tally/summary?from=${today()}&to=${today()}`)).body;
    expect(summary.matchesReports).toBe(true);
    expect(summary.vouchers.total).toBe(summary.vouchers.sales + summary.vouchers.receipts + summary.vouchers.creditNotes);
    // Exported, then deleted.
    const late = await offlineInvoice();
    await accounts.get(`/api/staff/billing/tally?from=${today()}&to=${today()}&kinds=sales`);
    await accounts.post(`/api/staff/deleted/invoice/${late.orderId}`).send({});
    const after = (await accounts.get(`/api/staff/billing/tally/summary?from=${today()}&to=${today()}`)).body;
    expect(after.exportedThenDeleted.map((i: { number: string }) => i.number)).toContain(late.invoiceNumber);
    expect((await accounts.get(`/api/staff/billing/tally?from=${today()}&to=${today()}&kinds=sales`)).text).not.toContain(`<VOUCHERNUMBER>${late.invoiceNumber}</VOUCHERNUMBER>`);
    void invoiceNumber;
  });

  it('TL6: ledger names are one shared, editable set; Reset to standard names; changes are logged', async () => {
    const r = await accounts.put('/api/staff/billing/tally-settings').send({ ledgers: { cash: 'Cash in Hand' } });
    expect(r.body.ledgers.cash).toBe('Cash in Hand');
    expect((await admin.get('/api/staff/billing/tally-settings')).body.ledgers.cash).toBe('Cash in Hand');
    const log = await prisma.auditLog.findFirstOrThrow({ where: { action: 'tally.ledgers_change' }, orderBy: { createdAt: 'desc' } });
    expect(JSON.stringify(log.detail)).toContain('Cash: Cash → Cash in Hand');
    const { defaults } = (await admin.get('/api/staff/billing/tally-settings')).body;
    await admin.put('/api/staff/billing/tally-settings').send({ ledgers: defaults });
    expect((await admin.get('/api/staff/billing/tally-settings')).body.ledgers.cash).toBe('Cash');
  });
});
