export interface ReportFilters {
  from: Date;
  to: Date; // exclusive
  q?: string;
  productId?: string;
  type?: 'online' | 'offline';
  gst?: 'with' | 'without';
}

export function rangeFrom(q: { period?: string; from?: string; to?: string }) {
  if (q.from && q.to) return { from: parseIsoDay(q.from), to: addDays(parseIsoDay(q.to), 1) };
  const p = resolvePeriod(q.period ?? 'month', q.from, q.to);
  return { from: p.from, to: p.to };
}

/** Invoices issued in the range, with their snapshot (what was invoiced) and credit notes. */
export async function invoicesIn(f: ReportFilters) {
  const orderWhere: Prisma.OrderWhereInput = {
    ...(f.type ? { type: f.type } : {}),
    ...(f.gst === 'with' ? { gstin: { not: null } } : f.gst === 'without' ? { gstin: null } : {}),
    ...(f.productId ? { items: { some: { productId: f.productId } } } : {}),
    ...(f.q ? { customer: { name: { contains: f.q, mode: 'insensitive' } } } : {}),
  };
  const list = await prisma.invoice.findMany({
    where: { issuedAt: { gte: f.from, lt: f.to }, order: { ...orderWhere, deletedAt: null } },
    include: { creditNotes: true, order: { include: { items: true, customer: { select: { name: true } } } } },
    orderBy: { issuedAt: 'asc' },
  });
  // Every real invoice carries its snapshot; skip any malformed row rather than fail the report.
  return list.filter((i) => (i.snapshot as { totals?: unknown } | null)?.totals);
}

/** Credit notes issued in the range (refunds), with the invoice they reverse. */
export async function creditNotesIn(f: ReportFilters) {
  const orderWhere: Prisma.OrderWhereInput = {
    ...(f.type ? { type: f.type } : {}),
    ...(f.gst === 'with' ? { gstin: { not: null } } : f.gst === 'without' ? { gstin: null } : {}),
    ...(f.q ? { customer: { name: { contains: f.q, mode: 'insensitive' } } } : {}),
  };
  const list = await prisma.creditNote.findMany({
    where: { createdAt: { gte: f.from, lt: f.to }, invoice: { order: { ...orderWhere, deletedAt: null } } },
    include: { invoice: { include: { order: true } } },
    orderBy: { createdAt: 'asc' },
  });
  return list.filter((c) => (c.invoice.snapshot as { totals?: unknown } | null)?.totals);
}

type Inv = Awaited<ReturnType<typeof invoicesIn>>[number];
