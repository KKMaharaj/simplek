-- Change request 26 Nov 2026, super admin panel: the data behind every admin
-- page (S1 dashboard, S2 businesses, S3 users, S4 plans, S5 integrations,
-- S6 settings and audit log). Every function is security definer and calls
-- require_super_admin() first, so a non-admin gets "Not found" (42501).
-- Integration secrets are stored in Supabase Vault and only ever returned
-- masked; the edge functions read them with the service role.
begin;

create table if not exists public.admin_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  note text not null check (char_length(btrim(note)) between 1 and 2000),
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists admin_notes_business_idx on public.admin_notes (business_id, created_at desc);
alter table public.admin_notes enable row level security;
revoke all on table public.admin_notes from anon, authenticated;

-- One row per business with everything the lists show.
create or replace function public.admin_business_rows()
returns table (
  user_id uuid, business_name text, owner_name text, email text, mobile text,
  gstin text, gst_registered boolean, city text, state text,
  plan_code text, plan_name text, used integer, allowed integer,
  last_invoice timestamptz, last_login timestamptz, joined timestamptz,
  status text, quiet boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select p.user_id, p.business_name, p.owner_name, lower(u.email),
         coalesce(nullif(p.phone, ''), u.raw_user_meta_data ->> 'mobile', ''),
         p.gstin, p.gst_registered, coalesce(p.city, ''), p.business_state,
         usage ->> 'plan_code', usage ->> 'plan_name',
         (usage ->> 'used')::int, (usage ->> 'allowed')::int,
         li.last_invoice, u.last_sign_in_at, p.created_at,
         case
           when f.suspended_at is not null then 'suspended'
           when d.user_id is not null then 'deletion_pending'
           else 'active'
         end,
         li.last_invoice is not null and li.last_invoice < now() - interval '30 days'
  from public.business_profiles p
  left join auth.users u on u.id = p.user_id
  left join public.account_flags f on f.user_id = p.user_id
  left join public.account_deletions d
    on d.user_id = p.user_id and d.cancelled_at is null and d.completed_at is null
  left join lateral (
    select max(i.created_at) as last_invoice from public.invoices i
    where i.user_id = p.user_id and i.status <> 'draft') li on true
  cross join lateral (select public.plan_usage(p.user_id) as usage) pu;
$$;
revoke all on function public.admin_business_rows() from public, anon, authenticated;

-- S1 dashboard.
create or replace function public.admin_dashboard(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.require_super_admin();
  with b as (select * from public.admin_business_rows()),
  months as (
    select date_trunc('month', (now() at time zone 'Asia/Kolkata')) - make_interval(months => g) as m
    from generate_series(11, 0, -1) g
  )
  select jsonb_build_object(
    'enrolled', (select count(*) from b),
    'enrolled_in_period', (select count(*) from b where joined::date between p_from and p_to),
    'active', (select count(distinct i.user_id) from public.invoices i
               where i.status <> 'draft' and i.created_at::date between p_from and p_to),
    'signups', (select count(*) from auth.users u where u.created_at::date between p_from and p_to),
    'invoices', (select count(*) from public.invoices i
                 where i.status <> 'draft' and i.created_at::date between p_from and p_to),
    'near_limit', (select count(*) from b where allowed is not null
                   and used >= ceil(allowed * 0.8) and used < allowed),
    'over_limit', (select count(*) from b where allowed is not null and used >= allowed),
    'by_plan', coalesce((select jsonb_agg(jsonb_build_object('plan', plan_name, 'count', n) order by n desc)
                         from (select plan_name, count(*) n from b group by plan_name) x), '[]'),
    -- Monthly recurring revenue needs plan payments, which don't exist yet.
    'mrr', 0,
    'signups_by_month', (select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'),
        'count', (select count(*) from auth.users u
                  where date_trunc('month', u.created_at at time zone 'Asia/Kolkata') = m)) order by m)
      from months),
    'invoices_by_month', (select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'),
        'count', (select count(*) from public.invoices i where i.status <> 'draft'
                  and date_trunc('month', i.created_at at time zone 'Asia/Kolkata') = m)) order by m)
      from months),
    'recently_active', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select * from b where last_invoice is not null order by last_invoice desc limit 10) r), '[]'),
    'gone_quiet', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select * from b where quiet order by last_invoice desc limit 20) r), '[]'),
    'needs_attention', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select * from b where allowed is not null and used >= allowed
        order by used desc limit 20) r), '[]')
  ) into result;
  return result;
end;
$$;

-- S2 businesses: one page, searched, filtered and sorted on the server.
create or replace function public.admin_businesses(
  p_search text default null,
  p_plan text default null,
  p_status text default null,
  p_gst text default null,
  p_quiet boolean default false,
  p_near_limit boolean default false,
  p_joined_from date default null,
  p_joined_to date default null,
  p_sort text default 'last_invoice',
  p_offset integer default 0,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  term text := nullif(lower(btrim(coalesce(p_search, ''))), '');
  result jsonb;
begin
  perform public.require_super_admin();
  with b as (
    select * from public.admin_business_rows() r
    where (term is null or lower(concat_ws(' ', r.business_name, r.owner_name, r.email,
             r.mobile, r.gstin, r.city, r.state)) like '%' || term || '%')
      and (p_plan is null or r.plan_code = p_plan)
      and (p_status is null or r.status = p_status)
      and (p_gst is null or r.gst_registered = (p_gst = 'yes'))
      and (not p_quiet or r.quiet or r.last_invoice is null)
      and (not p_near_limit or (r.allowed is not null and r.used >= ceil(r.allowed * 0.8)))
      and (p_joined_from is null or r.joined::date >= p_joined_from)
      and (p_joined_to is null or r.joined::date <= p_joined_to)
  ), page as (
    select * from b
    order by
      case when p_sort = 'name' then lower(business_name) end asc,
      case when p_sort = 'joined' then joined end desc,
      case when p_sort = 'used' then used end desc,
      case when p_sort = 'last_login' then last_login end desc nulls last,
      last_invoice desc nulls last, lower(business_name)
    offset greatest(coalesce(p_offset, 0), 0)
    limit least(greatest(coalesce(p_limit, 25), 1), 5000)
  )
  select jsonb_build_object(
    'total', (select count(*) from b),
    'rows', coalesce((select jsonb_agg(to_jsonb(page)) from page), '[]')
  ) into result;
  return result;
end;
$$;

-- S2 business detail.
create or replace function public.admin_business(p_business uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.require_super_admin();
  select jsonb_build_object(
    'row', (select to_jsonb(r) from public.admin_business_rows() r where r.user_id = p_business),
    'profile', (select to_jsonb(p) - 'bank_account' || jsonb_build_object(
        'bank_account_last4', right(p.bank_account, 4))
      from public.business_profiles p where p.user_id = p_business),
    'account', (select jsonb_build_object('email', lower(u.email), 'phone', u.phone,
        'name', u.raw_user_meta_data ->> 'full_name', 'mobile', u.raw_user_meta_data ->> 'mobile',
        'joined', u.created_at, 'last_login', u.last_sign_in_at,
        'email_confirmed', u.email_confirmed_at is not null)
      from auth.users u where u.id = p_business),
    'totals', jsonb_build_object(
      'invoices', (select count(*) from public.invoices where user_id = p_business),
      'deleted_invoices', (select count(*) from public.invoices
                           where user_id = p_business and deleted_at is not null),
      'customers', (select count(*) from public.customers where user_id = p_business),
      'items', (select count(*) from public.products where user_id = p_business)),
    'usage_by_month', (select jsonb_agg(jsonb_build_object('month', to_char(m, 'YYYY-MM'),
        'count', (select count(*) from public.invoices i where i.user_id = p_business
                  and i.status <> 'draft'
                  and date_trunc('month', i.created_at at time zone 'Asia/Kolkata') = m)) order by m)
      from (select date_trunc('month', (now() at time zone 'Asia/Kolkata')) - make_interval(months => g) m
            from generate_series(11, 0, -1) g) months),
    'people', coalesce((select jsonb_agg(jsonb_build_object('email', a.accountant_email,
        'given', a.created_at) order by a.created_at)
      from public.business_access a where a.owner_id = p_business), '[]'),
    'plan', public.plan_usage(p_business),
    'plan_history', coalesce((select jsonb_agg(jsonb_build_object('plan', pl.name,
        'starts_on', bp.starts_on, 'ends_on', bp.ends_on, 'extra_invoices', bp.extra_invoices,
        'reason', bp.reason, 'changed_at', bp.changed_at,
        'changed_by', (select lower(email) from auth.users where id = bp.changed_by))
        order by bp.changed_at desc)
      from public.business_plans bp join public.plans pl on pl.id = bp.plan_id
      where bp.business_id = p_business), '[]'),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('note', n.note, 'created_at', n.created_at,
        'by', (select lower(email) from auth.users where id = n.created_by)) order by n.created_at desc)
      from public.admin_notes n where n.business_id = p_business), '[]'),
    'suspended', exists (select 1 from public.account_flags
                         where user_id = p_business and suspended_at is not null),
    'deletion_due', (select scheduled_for from public.account_deletions
                     where user_id = p_business and cancelled_at is null and completed_at is null)
  ) into result;
  if result -> 'row' is null or result -> 'row' = 'null'::jsonb then
    raise exception 'Business not found';
  end if;
  return result;
end;
$$;

create or replace function public.admin_change_plan(
  p_business uuid,
  p_plan_code text,
  p_starts_on date,
  p_ends_on date,
  p_extra integer,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  before jsonb;
  plan_row public.plans;
begin
  perform public.require_super_admin();
  if coalesce(btrim(p_reason), '') = '' then raise exception 'A reason is required'; end if;
  select * into plan_row from public.plans where code = p_plan_code and active;
  if not found then raise exception 'Plan not found'; end if;
  if not exists (select 1 from public.business_profiles where user_id = p_business) then
    raise exception 'Business not found';
  end if;
  before := public.plan_usage(p_business);
  insert into public.business_plans (business_id, plan_id, starts_on, ends_on,
      extra_invoices, reason, changed_by)
  values (p_business, plan_row.id, coalesce(p_starts_on, current_date), p_ends_on,
          greatest(coalesce(p_extra, 0), 0), btrim(p_reason), auth.uid());
  perform public.admin_audit('plan_change', p_business, 'business_plan', before,
    jsonb_build_object('plan', plan_row.code, 'starts_on', coalesce(p_starts_on, current_date),
      'ends_on', p_ends_on, 'extra_invoices', coalesce(p_extra, 0), 'reason', btrim(p_reason)));
  return public.plan_usage(p_business);
end;
$$;

create or replace function public.admin_add_note(p_business uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_super_admin();
  insert into public.admin_notes (business_id, note, created_by)
  values (p_business, btrim(p_note), auth.uid());
  perform public.admin_audit('note_added', p_business, 'admin_note', null,
    jsonb_build_object('note', btrim(p_note)));
end;
$$;

create or replace function public.admin_set_suspended(p_business uuid, p_suspended boolean, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_super_admin();
  if p_suspended then
    insert into public.account_flags (user_id, suspended_at, suspended_by, reason)
    values (p_business, now(), auth.uid(), p_reason)
    on conflict (user_id) do update
      set suspended_at = now(), suspended_by = auth.uid(), reason = p_reason;
  else
    update public.account_flags set suspended_at = null, suspended_by = auth.uid(), reason = p_reason
    where user_id = p_business;
  end if;
  perform public.admin_audit(case when p_suspended then 'suspend' else 'reactivate' end,
    p_business, 'account', null, jsonb_build_object('reason', p_reason));
end;
$$;

-- Start the B4 30-day deletion for a business.
create or replace function public.admin_start_deletion(p_business uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  due timestamptz := now() + interval '30 days';
begin
  perform public.require_super_admin();
  insert into public.account_deletions (user_id, requested_at, scheduled_for)
  values (p_business, now(), due)
  on conflict (user_id) do update
    set requested_at = now(), scheduled_for = due, cancelled_at = null, completed_at = null;
  perform public.admin_audit('deletion_started', p_business, 'account', null,
    jsonb_build_object('scheduled_for', due));
  return due;
end;
$$;

-- The B4 export for any account; export_my_data uses it for the caller.
create or replace function public.export_account_data(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select p_user as id),
  my_invoices as (select i.* from public.invoices i, me where i.user_id = me.id),
  my_quotations as (select q.* from public.quotations q, me where q.user_id = me.id)
  select case when p_user is null then null else jsonb_build_object(
    'exported_at', now(),
    'account', (select jsonb_build_object(
        'id', u.id, 'email', u.email, 'phone', u.phone, 'created_at', u.created_at,
        'last_sign_in_at', u.last_sign_in_at, 'details', u.raw_user_meta_data)
      from auth.users u, me where u.id = me.id),
    'business_profile', (select to_jsonb(p) from public.business_profiles p, me where p.user_id = me.id),
    'customers', coalesce((select jsonb_agg(to_jsonb(c) order by c.name)
      from public.customers c, me where c.user_id = me.id), '[]'),
    'products', coalesce((select jsonb_agg(to_jsonb(p) order by p.name)
      from public.products p, me where p.user_id = me.id), '[]'),
    'invoices', coalesce((select jsonb_agg(to_jsonb(i) order by i.invoice_date, i.invoice_number)
      from my_invoices i), '[]'),
    'invoice_items', coalesce((select jsonb_agg(to_jsonb(it) || jsonb_build_object(
        'hsn_sac_code', pr.hsn_sac_code) order by it.invoice_id, it.id)
      from public.invoice_items it
      join my_invoices i on i.id = it.invoice_id
      left join public.products pr on pr.id = it.product_id), '[]'),
    'payments', coalesce((select jsonb_agg(to_jsonb(pm) order by pm.payment_date, pm.created_at)
      from public.payments pm join my_invoices i on i.id = pm.invoice_id), '[]'),
    'quotations', coalesce((select jsonb_agg(to_jsonb(q) order by q.quotation_date)
      from my_quotations q), '[]'),
    'quotation_items', coalesce((select jsonb_agg(to_jsonb(qi) order by qi.quotation_id, qi.id)
      from public.quotation_items qi join my_quotations q on q.id = qi.quotation_id), '[]'),
    'accountant_access', coalesce((select jsonb_agg(to_jsonb(a))
      from public.business_access a, me where a.owner_id = me.id), '[]'),
    'consents', coalesce((select jsonb_agg(to_jsonb(c) order by c.recorded_at)
      from public.consents c, me where c.user_id = me.id), '[]'),
    'nominee', (select to_jsonb(n) from public.privacy_nominees n, me where n.user_id = me.id),
    'privacy_requests', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at)
      from public.privacy_requests r, me where r.user_id = me.id), '[]'),
    'audit_log', coalesce((select jsonb_agg(to_jsonb(l) order by l.created_at)
      from public.audit_log l, me where l.business_id = me.id), '[]')
  ) end;
$$;
revoke all on function public.export_account_data(uuid) from public, anon, authenticated;

create or replace function public.export_my_data()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.export_account_data(auth.uid());
$$;

create or replace function public.admin_export_business(p_business uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_super_admin();
  perform public.admin_audit('data_export', p_business, 'account');
  return public.export_account_data(p_business);
end;
$$;

-- S3 users: every login email.
create or replace function public.admin_users(
  p_search text default null,
  p_role text default null,
  p_offset integer default 0,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  term text := nullif(lower(btrim(coalesce(p_search, ''))), '');
  result jsonb;
begin
  perform public.require_super_admin();
  with users as (
    select u.id, lower(u.email) as email,
           coalesce(u.raw_user_meta_data ->> 'full_name', '') as name,
           coalesce(u.raw_user_meta_data ->> 'mobile', '') as mobile,
           p.business_name as owns,
           (select string_agg(coalesce(nullif(bp.business_name, ''), 'Business'), ', ')
              from public.business_access a
              left join public.business_profiles bp on bp.user_id = a.owner_id
             where a.accountant_email = lower(u.email)) as accountant_for,
           u.created_at as joined,
           u.email_confirmed_at is not null as email_confirmed,
           u.last_sign_in_at as last_login,
           exists (select 1 from auth.mfa_factors m
                   where m.user_id = u.id and m.status = 'verified') as two_step,
           exists (select 1 from public.super_admins s where s.user_id = u.id) as super_admin,
           case when f.suspended_at is not null then 'suspended' else 'active' end as status
    from auth.users u
    left join public.business_profiles p on p.user_id = u.id
    left join public.account_flags f on f.user_id = u.id
  ), filtered as (
    select *, case when owns is not null then 'owner'
                   when accountant_for is not null then 'accountant'
                   else 'none' end as role
    from users
    where term is null or lower(concat_ws(' ', email, name, mobile, owns, accountant_for))
          like '%' || term || '%'
  ), chosen as (
    select * from filtered where p_role is null or role = p_role
  )
  select jsonb_build_object(
    'total', (select count(*) from chosen),
    'rows', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select * from chosen order by joined desc
        offset greatest(coalesce(p_offset, 0), 0)
        limit least(greatest(coalesce(p_limit, 25), 1), 5000)) r), '[]')
  ) into result;
  return result;
end;
$$;

-- S4 plans page.
create or replace function public.admin_plans()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.require_super_admin();
  select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('businesses',
      (select count(*) from public.admin_business_rows() r where r.plan_code = p.code))
      order by p.price_monthly, p.name), '[]')
  into result from public.plans p;
  return result;
end;
$$;

create or replace function public.admin_save_plan(p_plan jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  before jsonb;
begin
  perform public.require_super_admin();
  select to_jsonb(p) into before from public.plans p where p.code = p_plan ->> 'code';
  insert into public.plans (code, name, price_monthly, price_yearly, invoice_limit,
      limit_period, features, visible, active, updated_at)
  values (lower(btrim(p_plan ->> 'code')), btrim(p_plan ->> 'name'),
          coalesce((p_plan ->> 'price_monthly')::numeric, 0),
          coalesce((p_plan ->> 'price_yearly')::numeric, 0),
          nullif(p_plan ->> 'invoice_limit', '')::int,
          coalesce(p_plan ->> 'limit_period', 'none'),
          coalesce(p_plan -> 'features', '{}'::jsonb),
          coalesce((p_plan ->> 'visible')::boolean, true),
          coalesce((p_plan ->> 'active')::boolean, true), now())
  on conflict (code) do update set
    name = excluded.name, price_monthly = excluded.price_monthly,
    price_yearly = excluded.price_yearly, invoice_limit = excluded.invoice_limit,
    limit_period = excluded.limit_period, features = excluded.features,
    visible = excluded.visible, active = excluded.active, updated_at = now();
  perform public.admin_audit('plan_saved', null, 'plan', before, p_plan);
end;
$$;

-- S6 platform settings (not the integrations).
create or replace function public.admin_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  perform public.require_super_admin();
  select coalesce(jsonb_object_agg(key, value), '{}') into result
  from public.platform_settings where key not like 'integration_%';
  return result;
end;
$$;

create or replace function public.admin_save_setting(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  before jsonb;
begin
  perform public.require_super_admin();
  if p_key not in ('enforce_plan_limits', 'signups_open', 'notice_banner', 'support_contact') then
    raise exception 'Unknown setting';
  end if;
  select value into before from public.platform_settings where key = p_key;
  insert into public.platform_settings (key, value, updated_at, updated_by)
  values (p_key, p_value, now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(),
    updated_by = auth.uid();
  perform public.admin_audit('setting_change', null, p_key, before, p_value);
end;
$$;

-- S5 integrations. Secrets live in Vault as simplek.<kind>.<field>.
create or replace function public.integration_secret_names(p_kind text)
returns text[]
language sql
immutable
as $$
  select case p_kind
    when 'email' then array['password']
    when 'whatsapp' then array['access_token']
    when 'razorpay' then array['key_secret', 'webhook_secret']
    else array[]::text[] end;
$$;

create or replace function public.admin_integrations()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, vault
as $$
declare
  result jsonb := '{}'::jsonb;
  kind text;
  field text;
  masked jsonb;
  secret text;
begin
  perform public.require_super_admin();
  foreach kind in array array['email', 'whatsapp', 'razorpay'] loop
    masked := '{}'::jsonb;
    foreach field in array public.integration_secret_names(kind) loop
      select decrypted_secret into secret from vault.decrypted_secrets
      where name = 'simplek.' || kind || '.' || field;
      masked := masked || jsonb_build_object(field,
        case when coalesce(secret, '') = '' then null else '••••' || right(secret, 4) end);
    end loop;
    result := result || jsonb_build_object(kind, jsonb_build_object(
      'config', coalesce(public.platform_setting('integration_' || kind), '{}'::jsonb),
      'secrets', masked));
  end loop;
  return result;
end;
$$;

create or replace function public.admin_save_integration(p_kind text, p_config jsonb, p_secrets jsonb)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  field text;
  secret_id uuid;
  before jsonb;
  changed text[] := array[]::text[];
begin
  perform public.require_super_admin();
  if p_kind not in ('email', 'whatsapp', 'razorpay') then raise exception 'Unknown integration'; end if;
  before := public.platform_setting('integration_' || p_kind);
  insert into public.platform_settings (key, value, updated_at, updated_by)
  values ('integration_' || p_kind, coalesce(p_config, '{}'::jsonb), now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
  foreach field in array public.integration_secret_names(p_kind) loop
    if p_secrets ? field and coalesce(p_secrets ->> field, '') <> '' then
      select id into secret_id from vault.secrets where name = 'simplek.' || p_kind || '.' || field;
      if secret_id is null then
        perform vault.create_secret(p_secrets ->> field, 'simplek.' || p_kind || '.' || field,
          'Simplek ' || p_kind || ' ' || field);
      else
        perform vault.update_secret(secret_id, p_secrets ->> field);
      end if;
      changed := changed || field;
      secret_id := null;
    end if;
  end loop;
  -- Never the secrets themselves: only which were replaced.
  perform public.admin_audit('integration_change', null, 'integration_' || p_kind, before,
    coalesce(p_config, '{}'::jsonb) || jsonb_build_object('secrets_replaced', to_jsonb(changed)));
end;
$$;

-- For the admin edge functions (service role only): the config and the
-- decrypted secrets of one integration.
create or replace function public.integration_config(p_kind text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, vault
as $$
declare
  result jsonb;
  field text;
  secret text;
begin
  result := coalesce(public.platform_setting('integration_' || p_kind), '{}'::jsonb);
  foreach field in array public.integration_secret_names(p_kind) loop
    select decrypted_secret into secret from vault.decrypted_secrets
    where name = 'simplek.' || p_kind || '.' || field;
    result := result || jsonb_build_object(field, secret);
  end loop;
  return result;
end;
$$;
revoke all on function public.integration_config(text) from public, anon, authenticated;
grant execute on function public.integration_config(text) to service_role;

-- S6 audit log page.
create or replace function public.admin_audit_log(
  p_search text default null,
  p_action text default null,
  p_business uuid default null,
  p_from date default null,
  p_to date default null,
  p_offset integer default 0,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  term text := nullif(lower(btrim(coalesce(p_search, ''))), '');
  result jsonb;
begin
  perform public.require_super_admin();
  with rows as (
    select l.id, l.created_at, l.action, l.entity, l.entity_id, l.business_id,
           (select lower(email) from auth.users where id = l.actor_id) as actor,
           (select business_name from public.business_profiles where user_id = l.business_id) as business,
           l.old_values, l.new_values
    from public.audit_log l
    where (p_action is null or l.action = p_action)
      and (p_business is null or l.business_id = p_business)
      and (p_from is null or l.created_at::date >= p_from)
      and (p_to is null or l.created_at::date <= p_to)
  ), chosen as (
    select * from rows
    where term is null or lower(concat_ws(' ', actor, business, action, entity,
          old_values::text, new_values::text)) like '%' || term || '%'
  )
  select jsonb_build_object(
    'total', (select count(*) from chosen),
    'rows', coalesce((select jsonb_agg(to_jsonb(r)) from (
        select * from chosen order by created_at desc, id desc
        offset greatest(coalesce(p_offset, 0), 0)
        limit least(greatest(coalesce(p_limit, 25), 1), 5000)) r), '[]')
  ) into result;
  return result;
end;
$$;

-- Logs an admin event the app performs itself (list exports, S7).
create or replace function public.admin_log_event(p_action text, p_business uuid, p_details jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_super_admin();
  if p_action not in ('list_export', 'password_reset') then raise exception 'Unknown event'; end if;
  perform public.admin_audit(p_action, p_business, 'admin', null, p_details);
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'admin_dashboard(date,date)',
    'admin_businesses(text,text,text,text,boolean,boolean,date,date,text,integer,integer)',
    'admin_business(uuid)',
    'admin_change_plan(uuid,text,date,date,integer,text)',
    'admin_add_note(uuid,text)',
    'admin_set_suspended(uuid,boolean,text)',
    'admin_start_deletion(uuid)',
    'admin_export_business(uuid)',
    'admin_users(text,text,integer,integer)',
    'admin_plans()',
    'admin_save_plan(jsonb)',
    'admin_settings()',
    'admin_save_setting(text,jsonb)',
    'admin_integrations()',
    'admin_save_integration(text,jsonb,jsonb)',
    'admin_audit_log(text,text,uuid,date,date,integer,integer)',
    'admin_log_event(text,uuid,jsonb)',
    'export_my_data()'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
