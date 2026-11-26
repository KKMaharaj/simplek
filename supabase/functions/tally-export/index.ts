// Supabase Edge Function: "Export for Tally" (change request 26 Nov 2026, T1).
//
// POST { business_id?, from: 'YYYY-MM-DD', to: 'YYYY-MM-DD',
//        kinds?: ['sales', 'receipts'], download?: boolean }
// returns { xml, summary, filename }.
//
// Everything runs with the caller's own token: tally_export_data checks that
// the caller owns the business or is an accountant with view access (or a
// super admin in support view, read-only) and returns that business's data
// only. With download: true the vouchers are marked exported
// (tally_mark_exported), which only the owner or an accountant may do.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { type ExportData, TALLY_KINDS, type TallyKind, tallyExport, tallyFileName } from './tally.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });
const isDate = (v: unknown): v is string => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return reply({ error: 'Send from and to.' }, 400);
  }
  const { from, to } = body;
  if (!isDate(from) || !isDate(to) || from > to) return reply({ error: 'Choose a valid date range.' }, 400);
  const business = typeof body.business_id === 'string' && /^[0-9a-f-]{36}$/i.test(body.business_id)
    ? body.business_id
    : null;
  const asked = Array.isArray(body.kinds) ? body.kinds.filter((k): k is TallyKind => TALLY_KINDS.includes(k as TallyKind)) : TALLY_KINDS;
  if (asked.length === 0) return reply({ error: 'Tick Sales or Receipts.' }, 400);

  const caller = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: request.headers.get('Authorization') ?? '' } },
    auth: { persistSession: false },
  });
  const found = await caller.rpc('tally_export_data', { p_business: business, p_from: from, p_to: to });
  if (found.error) {
    const denied = found.error.code === '42501' || found.error.code === '28000';
    return reply({ error: denied ? 'Business not found' : found.error.message }, denied ? 404 : 500);
  }
  const data = found.data as ExportData;
  const result = tallyExport(data, asked);

  if (body.download === true && result.vouchers.length > 0) {
    const marked = await caller.rpc('tally_mark_exported', {
      p_business: business,
      p_rows: result.vouchers.map((v) => ({ guid: v.guid, kind: v.kind, number: v.number })),
    });
    if (marked.error) {
      const denied = marked.error.code === '42501';
      return reply({ error: denied ? 'Only the owner or an accountant can download for Tally.' : marked.error.message }, denied ? 403 : 500);
    }
  }

  return reply({
    xml: result.xml,
    summary: result.summary,
    filename: tallyFileName((data.settings?.company || data.company || 'Business').trim(), from, to),
  });
});
