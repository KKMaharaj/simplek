// Supabase Edge Function: PIN code -> post offices, district and state,
// through India Post's public API (https://api.postalpincode.in). Runs on our
// server so the app has one place to add caching or a fallback later
// (BUILD-STANDARDS section 2 and 8.2 "Lookups").

const pinPattern = /^[1-9][0-9]{5}$/;
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};
const notFound = "We couldn't find this PIN code; please check it.";

function reply(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return reply({ success: false, error: 'Method not allowed' }, 405);

  let pincode = '';
  try {
    const body = await request.json();
    pincode = String(body.pincode ?? '').trim();
  } catch {
    return reply({ success: false, error: 'Send a PIN code in the request body.' }, 400);
  }
  if (!pinPattern.test(pincode)) {
    return reply({ success: false, error: 'Enter a 6-digit PIN code that does not start with 0.' }, 400);
  }

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const upstream = await fetch(`https://api.postalpincode.in/pincode/${pincode}`, {
        signal: AbortSignal.timeout(6000),
      });
      const result = await upstream.json().catch(() => null);
      const first = Array.isArray(result) ? result[0] : null;
      if (!upstream.ok || !first) throw new Error(`India Post returned ${upstream.status}`);
      const offices = Array.isArray(first.PostOffice) ? first.PostOffice : [];
      if (first.Status !== 'Success' || offices.length === 0) {
        return reply({ success: false, error: notFound }, 404);
      }
      return reply({
        success: true,
        pincode,
        offices: offices.map((office: Record<string, unknown>) => ({
          name: String(office.Name ?? ''),
          block: String(office.Block ?? ''),
          district: String(office.District ?? ''),
          state: String(office.State ?? ''),
        })),
      });
    } catch (error) {
      if (attempt === 0) {
        await new Promise((resolve) => setTimeout(resolve, 400));
        continue;
      }
      console.error('PIN code lookup failed', error);
    }
  }
  return reply({ success: false, error: 'The PIN code service is not answering. Tap Retry, or fill the address by hand.' }, 502);
});
