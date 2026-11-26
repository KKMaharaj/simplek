-- Change request 26 Nov 2026, Tally (T3): the kit's export record and
-- Simplek's per-business Tally settings, and the data the tally-export edge
-- function turns into the kit's XML.
--
-- * tally_exports: each exported voucher (business, GUID, kind, number,
--   first and last export, count). The kit's TallyExport table, per
--   business; the kit's INSERT of old Rejwin data is left out.
-- * tally_settings: the company name in Tally, ledger names (fixed and per
--   GST rate), the units mapping and the "Export items as" switch.
-- * The owner and accountants with view access can use both (accountants
--   are the main users); renames go to audit_log (who, when, old, new).
-- * tally_export_data: the business's invoices (not deleted, not drafts or
--   cancelled) and payments in the dates, with items, products, customers,
--   what was exported before, exported-then-deleted invoices, and Simplek's
--   report totals for the "matches Reports" check.
begin;

create table if not exists public.tally_exports (
  business_id uuid not null,
  guid text not null,
  kind text not null check (kind in ('sales', 'receipt', 'creditnote')),
  number text not null,
  first_exported_at timestamptz not null default now(),
  last_exported_at timestamptz not null default now(),
  count integer not null default 1,
  primary key (business_id, guid)
);
alter table public.tally_exports enable row level security;
revoke all on table public.tally_exports from anon, authenticated;

create table if not exists public.tally_settings (
  business_id uuid primary key,
  settings jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.tally_settings enable row level security;
revoke all on table public.tally_settings from anon, authenticated;

alter table public.audit_log drop constraint if exists audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action in (
  'edit', 'delete', 'restore',
  'plan_change', 'password_reset', 'suspend', 'reactivate', 'setting_change',
  'integration_change', 'support_view', 'note_added', 'deletion_started',
  'data_export', 'list_export', 'plan_saved', 'access_given', 'access_removed',
  'tally_rename', 'tally_export'
));

-- The business a Tally call is for: the one asked for, or the one on screen;
-- only its owner or an accountant with view access. A super admin (support
-- view) may read but not save settings or mark vouchers exported.
create or replace function public.tally_business(p_business uuid, p_write boolean default false)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  business uuid := coalesce(p_business, public.viewing_business());
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if business = auth.uid()
     or exists (select 1 from public.business_access a
                where a.owner_id = business
                  and a.accountant_email = public.current_verified_email())
     or (not p_write and public.is_super_admin()) then
    return business;
  end if;
  raise exception 'Business not found' using errcode = '42501';
end;
$$;
revoke all on function public.tally_business(uuid, boolean) from public, anon, authenticated;

-- Tally settings, the GST rates and units the business uses, and the
-- rename log (newest first).
create or replace function public.tally_settings_get(p_business uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  business uuid := public.tally_business(p_business);
  result jsonb;
begin
  select jsonb_build_object(
    'business_id', business,
    'business_name', (select business_name from public.business_profiles where user_id = business),
    'gst', coalesce((select gst_registered from public.business_profiles where user_id = business), false),
    'settings', coalesce((select settings from public.tally_settings where business_id = business), '{}'::jsonb),
    'rates', coalesce((select jsonb_agg(r order by r) from (
        select distinct gst_rate::numeric as r from public.invoice_items it
          join public.invoices i on i.id = it.invoice_id
          where i.user_id = business and it.gst_rate is not null
        union
        select distinct gst_rate::numeric from public.products
          where user_id = business and gst_rate is not null) rr), '[]'::jsonb),
    'units', coalesce((select jsonb_agg(distinct upper(u)) from (
        select uqc_code as u from public.products where user_id = business and uqc_code is not null
        union
        select it.uqc_code from public.invoice_items it join public.invoices i on i.id = it.invoice_id
          where i.user_id = business and it.uqc_code is not null) uu), '[]'::jsonb),
    'renames', coalesce((select jsonb_agg(jsonb_build_object(
        'setting', l.new_values ->> 'setting', 'from', l.new_values ->> 'from',
        'to', l.new_values ->> 'to', 'at', l.created_at,
        'by', (select lower(email) from auth.users where id = l.actor_id)) order by l.created_at desc, l.id desc)
      from (select * from public.audit_log
            where business_id = business and action = 'tally_rename'
            order by created_at desc, id desc limit 100) l), '[]'::jsonb)
  ) into result;
  return result;
end;
$$;

-- Saves the settings; every changed name is logged (the kit's rename log).
-- p_changes is the list the screen worked out: [{setting, from, to}].
create or replace function public.tally_settings_save(
  p_business uuid,
  p_settings jsonb,
  p_changes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  business uuid := public.tally_business(p_business, true);
  change jsonb;
begin
  insert into public.tally_settings (business_id, settings, updated_at, updated_by)
  values (business, coalesce(p_settings, '{}'::jsonb), now(), auth.uid())
  on conflict (business_id) do update
    set settings = excluded.settings, updated_at = now(), updated_by = auth.uid();
  for change in select * from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) loop
    if coalesce(change ->> 'from', '') is distinct from coalesce(change ->> 'to', '') then
      insert into public.audit_log (business_id, actor_id, action, entity, new_values)
      values (business, auth.uid(), 'tally_rename', 'tally_settings',
              jsonb_build_object('setting', change ->> 'setting', 'from', change ->> 'from',
                                 'to', change ->> 'to'));
    end if;
  end loop;
  return public.tally_settings_get(business);
end;
$$;

-- Everything one export needs.
create or replace function public.tally_export_data(
  p_business uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  business uuid := public.tally_business(p_business);
  result jsonb;
begin
  with profile as (select * from public.business_profiles where user_id = business),
  invs as (
    select i.* from public.invoices i
    where i.user_id = business and i.deleted_at is null
      and i.status not in ('draft', 'cancelled')
      and i.invoice_date between p_from and p_to
  ),
  customer_of as (
    -- The customer record: the linked one, else the first with that name.
    select i.id as invoice_id, c.*
    from public.invoices i
    left join lateral (
      select c.id, c.name, c.phone, c.email, c.address, c.gstin, c.state
      from public.customers c
      where c.user_id = business
        and (c.id = i.customer_id or (i.customer_id is null and lower(btrim(c.name)) = lower(btrim(i.customer_name))))
      order by (c.id = i.customer_id) desc, c.is_active desc, c.created_at
      limit 1) c on true
    where i.user_id = business
  ),
  pays as (
    select p.*, i.invoice_number, i.customer_name,
           row_number() over (partition by p.invoice_id order by p.created_at, p.id) as sequence
    from public.payments p
    join public.invoices i on i.id = p.invoice_id
    where i.user_id = business and i.deleted_at is null
  )
  select jsonb_build_object(
    'company', coalesce((select business_name from profile), ''),
    'gst', coalesce((select gst_registered from profile), false),
    'business_state', (select business_state from profile),
    'settings', (select settings from public.tally_settings where business_id = business),
    'invoices', coalesce((select jsonb_agg(jsonb_build_object(
        'id', i.id, 'invoice_number', i.invoice_number, 'invoice_date', i.invoice_date,
        'due_date', i.due_date, 'customer_name', i.customer_name,
        'customer_gstin', i.customer_gstin, 'place_of_supply', i.place_of_supply,
        'tax_type', i.tax_type, 'total_amount', i.total_amount,
        'customer', (select case when co.id is null then null else jsonb_build_object(
            'id', co.id, 'name', co.name, 'phone', co.phone, 'email', co.email,
            'address', co.address, 'gstin', co.gstin, 'state', co.state) end
          from customer_of co where co.invoice_id = i.id),
        'items', coalesce((select jsonb_agg(jsonb_build_object(
            'product_id', it.product_id, 'item_name', coalesce(nullif(btrim(it.item_name), ''), it.product_name), 'quantity', it.quantity,
            'uqc_code', it.uqc_code, 'unit_price', it.unit_price,
            'taxable_amount', it.taxable_amount, 'gst_rate', it.gst_rate,
            'tax_amount', it.tax_amount, 'cgst_amount', it.cgst_amount,
            'sgst_amount', it.sgst_amount, 'igst_amount', it.igst_amount,
            'product_type', pr.product_type, 'hsn_sac_code', pr.hsn_sac_code,
            'product_name', pr.name, 'product_uqc', pr.uqc_code,
            'product_gst_rate', pr.gst_rate) order by it.created_at, it.id)
          from public.invoice_items it
          left join public.products pr on pr.id = it.product_id
          where it.invoice_id = i.id), '[]'::jsonb)
      ) order by i.invoice_date, i.invoice_number) from invs i), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'invoice_id', p.invoice_id, 'invoice_number', p.invoice_number,
        'payment_date', p.payment_date, 'amount', p.amount,
        'payment_method', coalesce(p.payment_method, p.payment_mode), 'sequence', p.sequence,
        'customer_name', p.customer_name,
        'customer', (select case when co.id is null then null else jsonb_build_object(
            'id', co.id, 'name', co.name, 'phone', co.phone, 'email', co.email,
            'address', co.address, 'gstin', co.gstin, 'state', co.state) end
          from customer_of co where co.invoice_id = p.invoice_id)
      ) order by p.payment_date, p.invoice_number, p.sequence)
      from pays p where p.payment_date between p_from and p_to), '[]'::jsonb),
    'exported', coalesce((select jsonb_agg(jsonb_build_object('guid', e.guid,
        'first_exported_at', e.first_exported_at))
      from public.tally_exports e where e.business_id = business), '[]'::jsonb),
    'exported_then_deleted', coalesce((select jsonb_agg(jsonb_build_object(
        'number', i.invoice_number, 'invoice_date', i.invoice_date,
        'exported_at', e.first_exported_at) order by i.invoice_date)
      from public.tally_exports e
      join public.invoices i on e.guid = 'simplek-sales-' || i.id
      where e.business_id = business and i.user_id = business and i.deleted_at is not null), '[]'::jsonb),
    'report', (select jsonb_build_object('invoices', count(*), 'taxable', coalesce(sum(subtotal), 0),
        'cgst', coalesce(sum(cgst_amount), 0), 'sgst', coalesce(sum(sgst_amount), 0),
        'igst', coalesce(sum(igst_amount), 0), 'total', coalesce(sum(total_amount), 0)) from invs)
  ) into result;
  return result;
end;
$$;

-- "Download for Tally": marks the vouchers exported (first and last date,
-- count). p_rows: [{guid, kind, number}].
create or replace function public.tally_mark_exported(p_business uuid, p_rows jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  business uuid := public.tally_business(p_business, true);
begin
  insert into public.tally_exports (business_id, guid, kind, number)
  select business, r ->> 'guid', r ->> 'kind', r ->> 'number'
  from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
  where coalesce(r ->> 'guid', '') like 'simplek-%'
  on conflict (business_id, guid) do update
    set number = excluded.number, last_exported_at = now(),
        count = public.tally_exports.count + 1;
  insert into public.audit_log (business_id, actor_id, action, entity, new_values)
  values (business, auth.uid(), 'tally_export', 'tally_exports',
          jsonb_build_object('vouchers', jsonb_array_length(coalesce(p_rows, '[]'::jsonb))));
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'tally_settings_get(uuid)',
    'tally_settings_save(uuid,jsonb,jsonb)',
    'tally_export_data(uuid,date,date)',
    'tally_mark_exported(uuid,jsonb)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
