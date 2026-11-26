-- CR-25B B4 (25 Nov 2026): privacy under the DPDP Act 2023 and Rules 2025.
--
-- * consents: each acceptance of the Privacy Notice and Terms (user, when,
--   notice version, web or Android, IP and device). Written only by
--   record_consent, which reads the IP from the request headers.
-- * privacy_nominees: the person who can use the owner's rights.
-- * privacy_requests: "Raise a concern"; due in 30 days; the user sees the
--   status but cannot change it.
-- * account_deletions: "Delete my account", after typing the business name;
--   30 days' grace, and any login in that time cancels it (the app calls
--   cancel_account_deletion when a session starts).
-- * data-exports bucket: "Download my data" ZIPs, each user's own folder,
--   private, shared through expiring signed links.
-- * Daily clean-up (privacy-daily edge function, scheduled separately):
--   privacy_due_accounts lists accounts on day 31; purge_account deletes all
--   their data and the login (storage files are removed by the function);
--   privacy_cleanup removes sign-ups never completed after 30 days and
--   anonymises audit entries a year after the account was deleted. These
--   three are for the service role only.
begin;

-- Consents -----------------------------------------------------------------
create table if not exists public.consents (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  notice_version text not null,
  consented_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  source text not null check (source in ('web', 'android', 'ios', 'other')),
  ip text,
  device text
);
create index if not exists consents_user_idx on public.consents (user_id, notice_version);
alter table public.consents enable row level security;
revoke all on table public.consents from anon, authenticated;
grant select on table public.consents to authenticated;
drop policy if exists "Read own consents" on public.consents;
create policy "Read own consents" on public.consents
  for select to authenticated using (user_id = auth.uid());

-- The caller's IP as the API saw it (first address of X-Forwarded-For).
create or replace function public.request_ip()
returns text
language sql
stable
set search_path = public
as $$
  select nullif(btrim(split_part(coalesce(
    current_setting('request.headers', true)::json ->> 'cf-connecting-ip',
    current_setting('request.headers', true)::json ->> 'x-forwarded-for',
    ''), ',', 1)), '');
$$;
revoke all on function public.request_ip() from public, anon, authenticated;

create or replace function public.record_consent(
  p_version text,
  p_source text,
  p_device text default null,
  p_consented_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(btrim(p_version), '') = '' then raise exception 'Notice version is required'; end if;
  if exists (select 1 from public.consents
             where user_id = owner and notice_version = p_version) then
    return;
  end if;
  insert into public.consents (user_id, notice_version, consented_at, source, ip, device)
  values (
    owner,
    p_version,
    -- The tick at sign-up may be a little earlier; never in the future.
    least(coalesce(p_consented_at, now()), now()),
    case when p_source in ('web', 'android', 'ios') then p_source else 'other' end,
    public.request_ip(),
    left(p_device, 200)
  );
end;
$$;

create or replace function public.consent_needed(p_version text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and not exists (
    select 1 from public.consents
    where user_id = auth.uid() and notice_version = p_version);
$$;

-- Nominee ------------------------------------------------------------------
create table if not exists public.privacy_nominees (
  user_id uuid primary key default auth.uid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  relation text not null check (char_length(btrim(relation)) between 1 and 60),
  contact text not null check (char_length(btrim(contact)) between 3 and 120),
  updated_at timestamptz not null default now()
);
alter table public.privacy_nominees enable row level security;
revoke all on table public.privacy_nominees from anon;
grant select, insert, update, delete on table public.privacy_nominees to authenticated;
drop policy if exists "Own nominee" on public.privacy_nominees;
create policy "Own nominee" on public.privacy_nominees
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Requests ("Raise a concern") ---------------------------------------------
create table if not exists public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  kind text not null default 'concern'
    check (kind in ('concern', 'access', 'correction', 'deletion', 'nominee', 'other')),
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  due_at timestamptz not null default (now() + interval '30 days'),
  answer text,
  answered_at timestamptz
);
create index if not exists privacy_requests_user_idx
  on public.privacy_requests (user_id, created_at desc);
alter table public.privacy_requests enable row level security;
revoke all on table public.privacy_requests from anon, authenticated;
grant select, insert on table public.privacy_requests to authenticated;
drop policy if exists "Read own requests" on public.privacy_requests;
create policy "Read own requests" on public.privacy_requests
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "Raise own requests" on public.privacy_requests;
create policy "Raise own requests" on public.privacy_requests
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'open' and answer is null
              and answered_at is null);

-- A new request always gets the server's dates.
create or replace function public.privacy_request_dates()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.created_at := now();
  new.due_at := now() + interval '30 days';
  return new;
end;
$$;
drop trigger if exists privacy_request_dates on public.privacy_requests;
create trigger privacy_request_dates before insert on public.privacy_requests
  for each row execute function public.privacy_request_dates();

-- Account deletion -----------------------------------------------------------
create table if not exists public.account_deletions (
  user_id uuid primary key,
  requested_at timestamptz not null default now(),
  scheduled_for timestamptz not null,
  cancelled_at timestamptz,
  completed_at timestamptz
);
alter table public.account_deletions enable row level security;
revoke all on table public.account_deletions from anon, authenticated;

-- "Delete my account": the business name (or, without a business, the login
-- email) must be typed exactly, ignoring case and outer spaces. Returns the
-- day the deletion happens.
create or replace function public.request_account_deletion(p_business_name text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
  saved_name text;
  due timestamptz := now() + interval '30 days';
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  -- The business name, or the login email for an account without a business.
  select coalesce(
    (select nullif(btrim(business_name), '') from public.business_profiles where user_id = owner),
    (select email from auth.users where id = owner))
    into saved_name;
  if lower(btrim(coalesce(saved_name, ''))) <> lower(btrim(coalesce(p_business_name, '')))
     or btrim(coalesce(p_business_name, '')) = '' then
    raise exception 'Type the business name exactly as it is in your profile'
      using errcode = '22000';
  end if;
  insert into public.account_deletions (user_id, requested_at, scheduled_for)
  values (owner, now(), due)
  on conflict (user_id) do update
    set requested_at = now(), scheduled_for = due, cancelled_at = null, completed_at = null;
  return due;
end;
$$;

-- Called when a session starts: a login within the 30 days cancels the
-- deletion. Returns the day it was due, or null if none was pending.
create or replace function public.cancel_account_deletion()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  due timestamptz;
begin
  update public.account_deletions
    set cancelled_at = now()
    where user_id = auth.uid() and cancelled_at is null and completed_at is null
    returning scheduled_for into due;
  return due;
end;
$$;

create or replace function public.account_deletion_due()
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select scheduled_for from public.account_deletions
  where user_id = auth.uid() and cancelled_at is null and completed_at is null;
$$;

-- "Download my data" files ---------------------------------------------------
insert into storage.buckets (id, name, public)
values ('data-exports', 'data-exports', false)
on conflict (id) do update set public = false;

drop policy if exists "Own data exports read" on storage.objects;
create policy "Own data exports read" on storage.objects
  for select to authenticated
  using (bucket_id = 'data-exports' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Own data exports write" on storage.objects;
create policy "Own data exports write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'data-exports' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Own data exports remove" on storage.objects;
create policy "Own data exports remove" on storage.objects
  for delete to authenticated
  using (bucket_id = 'data-exports' and (storage.foldername(name))[1] = auth.uid()::text);

-- "Download my data": everything the caller's own account holds, as JSON,
-- including deleted invoices and payments the app can't otherwise read.
-- (An accountant gets their own account's data, never a shared business.)
create or replace function public.export_my_data()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with me as (select auth.uid() as id),
  my_invoices as (select i.* from public.invoices i, me where i.user_id = me.id),
  my_quotations as (select q.* from public.quotations q, me where q.user_id = me.id)
  select case when (select id from me) is null then null else jsonb_build_object(
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

-- Retention (service role only) ---------------------------------------------
alter table public.audit_log alter column business_id drop not null;
alter table public.audit_log add column if not exists subject_deleted_at timestamptz;

-- Accounts whose 30 days have passed.
create or replace function public.privacy_due_accounts(p_now timestamptz default now())
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select user_id from public.account_deletions
  where cancelled_at is null and completed_at is null and scheduled_for <= p_now;
$$;

-- Deletes everything an account owns, then the login. Storage files are
-- removed by the caller first (the Storage API, not SQL).
create or replace function public.purge_account(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  email text;
begin
  select u.email into email from auth.users u where u.id = p_user;
  delete from public.payments where invoice_id in
    (select id from public.invoices where user_id = p_user);
  delete from public.invoice_items where invoice_id in
    (select id from public.invoices where user_id = p_user);
  -- Quotations point at invoices they were converted to.
  delete from public.quotation_items where quotation_id in
    (select id from public.quotations where user_id = p_user);
  delete from public.quotations where user_id = p_user;
  delete from public.invoices where user_id = p_user;
  delete from public.customers where user_id = p_user;
  delete from public.products where user_id = p_user;
  delete from public.business_document_counters where user_id = p_user;
  delete from public.business_viewing where user_id = p_user or owner_id = p_user;
  delete from public.business_access where owner_id = p_user
    or (email is not null and accountant_email = lower(email));
  delete from public.business_profiles where user_id = p_user;
  delete from public.privacy_nominees where user_id = p_user;
  delete from public.privacy_requests where user_id = p_user;
  delete from public.consents where user_id = p_user;
  -- Security log entries stay for a year, then privacy_cleanup anonymises them.
  update public.audit_log set subject_deleted_at = now()
    where (business_id = p_user or actor_id = p_user) and subject_deleted_at is null;
  update public.account_deletions set completed_at = now() where user_id = p_user;
  delete from auth.users where id = p_user;
end;
$$;

-- Sign-ups never completed (no business profile, not an invited accountant,
-- no deletion pending) for 30 days, and audit entries of accounts deleted a
-- year ago. Returns the logins it removed, so the caller can tidy storage.
create or replace function public.privacy_cleanup(p_now timestamptz default now())
returns setof uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  stale uuid;
begin
  update public.audit_log
    set old_values = null, actor_id = null, business_id = null
    where subject_deleted_at is not null
      and subject_deleted_at <= p_now - interval '1 year'
      and (old_values is not null or actor_id is not null or business_id is not null);
  for stale in
    select u.id from auth.users u
    where u.created_at <= p_now - interval '30 days'
      and not exists (select 1 from public.business_profiles p where p.user_id = u.id)
      and not exists (select 1 from public.business_access a
                      where a.accountant_email = lower(u.email))
      and not exists (select 1 from public.account_deletions d where d.user_id = u.id)
  loop
    delete from public.consents where user_id = stale;
    delete from auth.users where id = stale;
    return next stale;
  end loop;
end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'record_consent(text,text,text,timestamptz)',
    'consent_needed(text)',
    'request_account_deletion(text)',
    'cancel_account_deletion()',
    'account_deletion_due()',
    'export_my_data()'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array[
    'privacy_due_accounts(timestamptz)',
    'purge_account(uuid)',
    'privacy_cleanup(timestamptz)'
  ] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
