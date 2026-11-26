// Supabase Edge Function: super admin "Reset password" (super admin S3).
//
// Passwords can never be shown: Supabase keeps only a one-way hash. Instead
// this sets a temporary password, returns it ONCE for the admin to pass on by
// phone or WhatsApp, and sets must_change_password in the user's metadata, so
// the app asks for a new password at the next login. Logged in audit_log.
//
// The caller must be a super admin signed in with the two-step login: the
// check runs in the database (require_super_admin) with the caller's own
// token, before the service role is used.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

// No look-alike characters (0/O, 1/l/I), easy to read out on the phone.
const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
function temporaryPassword(length = 12): string {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  let text = '';
  for (const byte of bytes) text += alphabet[byte % alphabet.length];
  // At least one digit (the password rule asks for a letter and a number).
  return /\d/.test(text) ? text : text.slice(0, -1) + '7';
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

  let userId = '';
  try {
    userId = String((await request.json()).user_id ?? '');
  } catch {
    return reply({ error: 'Send user_id.' }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(userId)) return reply({ error: 'Send user_id.' }, 400);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
  const found = await admin.auth.admin.getUserById(userId);
  if (found.error || !found.data.user) return reply({ error: 'User not found' }, 404);
  const password = temporaryPassword();
  const updated = await admin.auth.admin.updateUserById(userId, {
    password,
    user_metadata: { ...found.data.user.user_metadata, must_change_password: true },
  });
  if (updated.error) return reply({ error: updated.error.message }, 500);

  // Who reset whose password, never the password itself.
  await caller.rpc('admin_log_event', {
    p_action: 'password_reset',
    p_business: userId,
    p_details: { email: found.data.user.email },
  });
  return reply({ temporary_password: password, email: found.data.user.email });
});
