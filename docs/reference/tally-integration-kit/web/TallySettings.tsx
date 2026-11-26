'use client';

import { useEffect, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { Panel } from '@/components/ui/Card';
import { Input } from '@/components/ui/Field';
import { useToast } from '@/components/ui/Toast';
import { api, ApiError, formatDate } from '@/lib/api';

type Ledgers = Record<string, string>;
type Rename = { setting: string; from: string; to: string; at: string; by: string };

/**
 * Change 06.12: the Tally ledger names, one shared set shown in Business Profile
 * and Settings and in Billing and Accounting > Settings. Save changes at the top
 * and bottom; Reset to standard names; every change is logged.
 * Change 07.2: Accounts edits them as well as the admin; the log of renames (who,
 * when, the old and the new name) is shown under them; nothing about purchases.
 */
export function TallySettings() {
  const [data, setData] = useState<{ ledgers: Ledgers; defaults: Ledgers; labels: Record<string, string>; renames: Rename[] } | null>(null);
  const [form, setForm] = useState<Ledgers | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const toast = useToast();
  useEffect(() => {
    api<NonNullable<typeof data>>('/staff/billing/tally-settings').then((r) => {
      setData(r);
      setForm(r.ledgers);
    });
  }, []);
  if (!data || !form) return null;
  const save = async (ledgers: Ledgers) => {
    setBusy(true);
    setErrors({});
    try {
      const r = await api<{ ledgers: Ledgers; renames: Rename[] }>('/staff/billing/tally-settings', { method: 'PUT', json: { ledgers } });
      setForm(r.ledgers);
      setData({ ...data, ledgers: r.ledgers, renames: r.renames });
      toast.success('Saved');
    } catch (e) {
      if (e instanceof ApiError) setErrors(e.fields ?? {});
    } finally {
      setBusy(false);
    }
  };
  const dirty = Object.keys(form).some((k) => form[k] !== data.ledgers[k]);
  const buttons = (
    <div className="flex flex-wrap gap-2">
      <Button shape="staff" busy={busy} disabled={!dirty} onClick={() => save(form)}>
        Save changes
      </Button>
      <Button variant="secondary" shape="staff" disabled={busy} onClick={() => save(data.defaults)}>
        Reset to standard names
      </Button>
    </div>
  );
  return (
    <Panel title="Tally settings">
      <div className="flex flex-col gap-4" data-testid="tally-settings">
        <p className="m-0 text-[14px] font-bold text-purple">Type names exactly as in Tally.</p>
        {buttons}
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {Object.keys(data.defaults).map((k) => (
            <Input key={k} label={data.labels[k]} value={form[k] ?? ''} onChange={(e) => setForm({ ...form, [k]: e.target.value })} error={errors[k]} hint={form[k] !== data.defaults[k] ? `Standard: ${data.defaults[k]}` : undefined} />
          ))}
        </div>
        {buttons}
        <div className="flex flex-col gap-2" data-testid="tally-renames">
          <h3 className="m-0 text-[15px] font-bold">Changes</h3>
          {data.renames.length ? (
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-[14px]">
                <thead>
                  <tr className="text-left text-ink-muted">
                    <th className="py-1.5 pr-3 font-medium">When</th>
                    <th className="py-1.5 pr-3 font-medium">Who</th>
                    <th className="py-1.5 pr-3 font-medium">Setting</th>
                    <th className="py-1.5 pr-3 font-medium">Old name</th>
                    <th className="py-1.5 font-medium">New name</th>
                  </tr>
                </thead>
                <tbody>
                  {data.renames.map((r, i) => (
                    <tr key={i} className="border-t border-line-soft" data-testid="tally-rename">
                      <td className="py-1.5 pr-3 whitespace-nowrap">
                        {formatDate(r.at)} {new Date(r.at).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', timeZone: 'Asia/Kolkata' })}
                      </td>
                      <td className="py-1.5 pr-3">{r.by}</td>
                      <td className="py-1.5 pr-3">{r.setting}</td>
                      <td className="py-1.5 pr-3">{r.from}</td>
                      <td className="py-1.5">{r.to}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : (
            <p className="m-0 text-[14px] text-ink-muted">No names changed yet.</p>
          )}
        </div>
      </div>
    </Panel>
  );
}
