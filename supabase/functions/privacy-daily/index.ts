// Supabase Edge Function: the daily privacy clean-up (CR-25B B4).
//
// Run once a day by pg_cron (see migration 20261127000004). It only does work
// that is already due, so being called again early does no harm, and it
// needs no secret from the caller: it uses this project's own service-role
// key, which Supabase gives every function.
//
// 1. Accounts on day 31 of "Delete my account": their files in Storage are
//    removed (logo, signature, QR, data exports), then purge_account deletes
//    every row and the login.
// 2. privacy_cleanup: sign-ups never completed after 30 days, and audit
//    entries anonymised a year after the account was deleted.
// 3. "Download my data" ZIPs older than 7 days are removed.
import { createClient } from 'jsr:@supabase/supabase-js@2';

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

const exportDays = 7;

/** Every file under `folder` in `bucket`, folders included (paths). */
async function filesUnder(bucket: string, folder: string): Promise<string[]> {
  const found: string[] = [];
  const pending = [folder];
  while (pending.length) {
    const current = pending.pop()!;
    for (let offset = 0; ; offset += 100) {
      const { data, error } = await admin.storage.from(bucket).list(current, { limit: 100, offset });
      if (error) throw error;
      for (const entry of data ?? []) {
        const path = current ? `${current}/${entry.name}` : entry.name;
        // Folders have no id.
        if (entry.id == null) pending.push(path);
        else found.push(path);
      }
      if (!data || data.length < 100) break;
    }
  }
  return found;
}

async function removeFiles(bucket: string, paths: string[]) {
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
    if (error) throw error;
  }
}

Deno.serve(async () => {
  const report = { accountsDeleted: 0, signupsRemoved: 0, exportsRemoved: 0, errors: [] as string[] };

  // 1. Accounts whose 30 days have passed.
  const due = await admin.rpc('privacy_due_accounts');
  if (due.error) return Response.json({ ...report, errors: [due.error.message] }, { status: 500 });
  for (const userId of (due.data ?? []) as string[]) {
    try {
      for (const bucket of ['business-media', 'data-exports']) {
        await removeFiles(bucket, await filesUnder(bucket, userId));
      }
      const purged = await admin.rpc('purge_account', { p_user: userId });
      if (purged.error) throw purged.error;
      report.accountsDeleted++;
    } catch (error) {
      // The account stays due and is tried again tomorrow.
      report.errors.push(`account ${userId}: ${(error as Error).message}`);
    }
  }

  // 2. Sign-ups never completed, and old audit entries.
  const cleaned = await admin.rpc('privacy_cleanup');
  if (cleaned.error) report.errors.push(`cleanup: ${cleaned.error.message}`);
  else report.signupsRemoved = (cleaned.data ?? []).length;

  // 3. Data exports older than a week.
  try {
    const cutoff = Date.now() - exportDays * 24 * 60 * 60 * 1000;
    const { data: folders, error } = await admin.storage.from('data-exports').list('', { limit: 1000 });
    if (error) throw error;
    for (const folder of folders ?? []) {
      const { data: files, error: listError } = await admin.storage
        .from('data-exports').list(folder.name, { limit: 1000 });
      if (listError) throw listError;
      const old = (files ?? [])
        .filter((file) => file.id != null && Date.parse(file.created_at ?? '') < cutoff)
        .map((file) => `${folder.name}/${file.name}`);
      await removeFiles('data-exports', old);
      report.exportsRemoved += old.length;
    }
  } catch (error) {
    report.errors.push(`exports: ${(error as Error).message}`);
  }

  return Response.json(report, { status: report.errors.length ? 207 : 200 });
});
