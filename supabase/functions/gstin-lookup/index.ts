// Supabase Edge Function: secure GSTIN verification through gstinapi.in.
// Set GSTINAPI_KEY as a Supabase secret; never put it in Flutter.

const gstinPattern = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

const messages: Record<number, string> = {
  400: 'Enter a valid GSTIN.',
  401: 'GST verification is not configured correctly.',
  402: 'GST verification credits are exhausted.',
  403: 'GST verification account is deactivated.',
  404: 'This GSTIN is not registered in the GST database.',
  429: 'GST verification is busy. Please try again shortly.',
  502: 'GST provider is temporarily unavailable. Please try again shortly.',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') {
    return Response.json({ success: false, error: 'Method not allowed' }, { status: 405, headers: corsHeaders });
  }

  const apiKey = Deno.env.get('GSTINAPI_KEY');
  if (!apiKey) {
    console.error('GSTINAPI_KEY is not configured');
    return Response.json({ success: false, error: messages[401] }, { status: 503, headers: corsHeaders });
  }

  let gstin = '';
  try {
    const body = await request.json();
    gstin = String(body.gstin ?? '').trim().toUpperCase();
  } catch {
    return Response.json({ success: false, error: 'Send a GSTIN in the request body.' }, { status: 400, headers: corsHeaders });
  }

  if (!gstinPattern.test(gstin)) {
    return Response.json({ success: false, error: messages[400] }, { status: 400, headers: corsHeaders });
  }

  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const upstream = await fetch(
        `https://www.gstinapi.in/v1/gstin/${encodeURIComponent(gstin)}?include=profile`,
        { headers: { 'x-api-key': apiKey } },
      );
      const result = await upstream.json().catch(() => ({}));
      if (typeof result.credits_remaining === 'number') {
        console.log(`GSTIN lookup credits remaining: ${result.credits_remaining}`);
      }

      if (upstream.ok && result.success === true) {
        return Response.json(result, { headers: corsHeaders });
      }

      if ((upstream.status === 429 || upstream.status === 502) && attempt < 2) {
        await new Promise((resolve) => setTimeout(resolve, 300 * 2 ** attempt));
        continue;
      }

      return Response.json(
        { success: false, error: messages[upstream.status] ?? result.error ?? 'GST verification failed.' },
        { status: upstream.status >= 400 ? upstream.status : 502, headers: corsHeaders },
      );
    } catch (error) {
      if (attempt < 2) {
        await new Promise((resolve) => setTimeout(resolve, 300 * 2 ** attempt));
        continue;
      }
      console.error('GSTIN lookup failed', error);
      return Response.json({ success: false, error: messages[502] }, { status: 502, headers: corsHeaders });
    }
  }

  return Response.json({ success: false, error: messages[502] }, { status: 502, headers: corsHeaders });
});
