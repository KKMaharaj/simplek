// Supabase Edge Function: the "Send test email", "Send test message" and
// "Test connection" buttons of the super admin Integrations page (S5).
// Nothing else is sent by these integrations yet.
//
// The caller must be a super admin with the two-step login (checked in the
// database with the caller's token). The saved settings and their secrets
// are read with the service role (integration_config); secrets never leave
// this function.
//
// Note: Supabase Edge Functions can't open SMTP port 587 (or 25). Use port
// 465 (SSL), or Brevo, which is sent over HTTPS.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import nodemailer from 'npm:nodemailer@6.9.16';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });
type Config = Record<string, string | number | boolean | null | undefined>;

async function testEmail(config: Config, to: string): Promise<string> {
  if (config.provider === 'brevo') {
    const response = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': String(config.password ?? ''), 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sender: { name: config.from_name || 'Simplek', email: config.from_address },
        to: [{ email: to }],
        replyTo: config.reply_to ? { email: config.reply_to } : undefined,
        subject: 'Simplek test email',
        textContent: 'This is a test email from the Simplek admin panel. It works.',
      }),
    });
    if (!response.ok) throw new Error(`Brevo: HTTP ${response.status} ${await response.text()}`);
    return 'Connected: Brevo accepted the test email.';
  }
  const transport = nodemailer.createTransport({
    host: String(config.host ?? ''),
    port: Number(config.port || 465),
    secure: config.security !== 'starttls',
    auth: { user: String(config.username ?? ''), pass: String(config.password ?? '') },
  });
  await transport.sendMail({
    from: `${config.from_name || 'Simplek'} <${config.from_address}>`,
    to,
    replyTo: config.reply_to ? String(config.reply_to) : undefined,
    subject: 'Simplek test email',
    text: 'This is a test email from the Simplek admin panel. It works.',
  });
  return `Connected: ${config.host} accepted the test email.`;
}

async function testWhatsApp(config: Config, to: string): Promise<string> {
  const response = await fetch(
    `https://graph.facebook.com/v21.0/${config.phone_number_id}/messages`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to: to.replace(/[^0-9]/g, ''),
        type: 'template',
        template: { name: 'hello_world', language: { code: 'en_US' } },
      }),
    },
  );
  const body = await response.text();
  if (!response.ok) throw new Error(`WhatsApp: HTTP ${response.status} ${body}`);
  return 'Connected: WhatsApp accepted the test message (template hello_world).';
}

async function testRazorpay(config: Config): Promise<string> {
  const live = config.mode === 'live';
  const keyId = String((live ? config.live_key_id : config.test_key_id) ?? '');
  const auth = btoa(`${keyId}:${config.key_secret ?? ''}`);
  // A Rs 1 order. Razorpay can't cancel an order; an unpaid one simply
  // expires, so nothing is ever charged.
  const response = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ amount: 100, currency: 'INR', receipt: `simplek-test-${Date.now()}` }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Razorpay: HTTP ${response.status} ${body?.error?.description ?? ''}`);
  }
  return `Connected (${live ? 'Live' : 'Test'} mode): Razorpay created test order ${body.id}; ` +
    'it is never paid and expires on its own.';
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL')!;
  const caller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: request.headers.get('Authorization') ?? '' } },
    auth: { persistSession: false },
  });
  if ((await caller.rpc('require_super_admin')).error) return reply({ error: 'Not found' }, 404);

  let kind = '';
  let to = '';
  try {
    const body = await request.json();
    kind = String(body.kind ?? '');
    to = String(body.to ?? '').trim();
  } catch {
    return reply({ error: 'Send kind and to.' }, 400);
  }
  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
  const saved = await admin.rpc('integration_config', { p_kind: kind });
  if (saved.error) return reply({ ok: false, message: saved.error.message });
  const config = (saved.data ?? {}) as Config;
  try {
    let message: string;
    if (kind === 'email') message = await testEmail(config, to);
    else if (kind === 'whatsapp') message = await testWhatsApp(config, to);
    else if (kind === 'razorpay') message = await testRazorpay(config);
    else throw new Error('Unknown integration');
    return reply({ ok: true, message });
  } catch (error) {
    // The exact error, so the admin can fix the setting.
    return reply({ ok: false, message: (error as Error).message });
  }
});
