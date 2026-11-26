-- Change request 26 Nov 2026, super admin panel: S0 (who can open it),
-- S3 (one email = one account), S6 (platform settings) and the account
-- status the app checks at every login (suspended, forced password change,
-- the notice banner).
--
-- * super_admins: the only people who can use any admin_* function. The
--   first row is added by the owner (NOTES.md: "Replace before launch").
-- * is_super_admin(): true only for a listed user whose session passed the
--   two-step login (Supabase Auth TOTP, aal2). Every admin function and the
--   admin edge functions call it first; no admin table has an app policy.
-- * audit_log gains new_values and the admin actions.
-- * Support view: a super admin can open a business read-only through the
--   same "viewing" mechanism accountants use; writes stay owner-only.
-- * account_flags: suspended businesses (data untouched).
-- * platform_settings: enforce plan limits (off), new sign-ups open, a
--   notice banner, the support contact. Integration settings live here too
--   (non-secret parts); secrets are in Supabase Vault.
begin;

create table if not exists public.super_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  added_at timestamptz not null default now(),
  added_by uuid
);
alter table public.super_admins enable row level security;
revoke all on table public.super_admins from anon, authenticated;

-- Listed, whatever the session's login level (the app uses this to offer
-- the two-step set-up).
create or replace function public.is_super_admin_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and exists (select 1 from public.super_admins where user_id = auth.uid());
$$;

-- Listed AND signed in with the two-step login.
create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_super_admin_member()
     and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2';
$$;

-- Raises the same error a missing page would, for anyone else.
create or replace function public.require_super_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Not found' using errcode = '42501';
  end if;
end;
$$;

-- Audit log: admin actions with old and new values.
alter table public.audit_log add column if not exists new_values jsonb;
alter table public.audit_log drop constraint if exists audit_log_action_check;
alter table public.audit_log add constraint audit_log_action_check check (action in (
  'edit', 'delete', 'restore',
  'plan_change', 'password_reset', 'suspend', 'reactivate', 'setting_change',
  'integration_change', 'support_view', 'note_added', 'deletion_started',
  'data_export', 'list_export', 'plan_saved', 'access_given', 'access_removed'
));

-- Writes one admin entry (for admin functions and admin edge functions).
create or replace function public.admin_audit(
  p_action text,
  p_business uuid,
  p_entity text,
  p_old jsonb default null,
  p_new jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (business_id, actor_id, action, entity, entity_id,
      old_values, new_values)
  values (p_business, auth.uid(), p_action, p_entity, p_business, p_old, p_new);
end;
$$;
revoke all on function public.admin_audit(text, uuid, text, jsonb, jsonb) from public, anon, authenticated;

-- Accountant access given or removed is a key user event (S6 audit log).
create or replace function public.audit_business_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.audit_log (business_id, actor_id, action, entity, new_values)
    values (new.owner_id, auth.uid(), 'access_given', 'business_access',
            jsonb_build_object('accountant_email', new.accountant_email));
    return new;
  end if;
  insert into public.audit_log (business_id, actor_id, action, entity, old_values)
  values (old.owner_id, auth.uid(), 'access_removed', 'business_access',
          jsonb_build_object('accountant_email', old.accountant_email));
  return old;
end;
$$;
drop trigger if exists audit_business_access on public.business_access;
create trigger audit_business_access after insert or delete on public.business_access
  for each row execute function public.audit_business_access();

-- Support view: the same "viewing" a shared accountant uses, for a super
-- admin. Reads follow viewing_business(); every write policy still needs
-- auth.uid() = user_id, so the view is read-only.
create or replace function public.viewing_business()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select v.owner_id
       from public.business_viewing v
      where v.user_id = auth.uid()
        and (exists (
              select 1 from public.business_access a
              where a.owner_id = v.owner_id
                and a.accountant_email = public.current_verified_email())
             or public.is_super_admin())),
    auth.uid()
  );
$$;

create or replace function public.set_viewing_business(p_owner_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  support boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_owner_id is null or p_owner_id = auth.uid() then
    delete from public.business_viewing where user_id = auth.uid();
    return auth.uid();
  end if;
  if not exists (
    select 1 from public.business_access a
    where a.owner_id = p_owner_id
      and a.accountant_email = public.current_verified_email()
  ) then
    if not public.is_super_admin() then
      raise exception 'You do not have access to this business';
    end if;
    support := true;
  end if;
  insert into public.business_viewing (user_id, owner_id)
    values (auth.uid(), p_owner_id)
    on conflict (user_id) do update set owner_id = excluded.owner_id;
  if support then
    perform public.admin_audit('support_view', p_owner_id, 'business');
  end if;
  return p_owner_id;
end;
$$;

-- Businesses shared with the caller, plus a super admin's support view.
drop function if exists public.shared_businesses();
create function public.shared_businesses()
returns table (owner_id uuid, business_name text, viewing boolean, support boolean)
language sql stable security definer set search_path = public as $$
  select a.owner_id,
         coalesce(nullif(btrim(p.business_name), ''), 'Business'),
         a.owner_id = public.viewing_business(),
         false
  from public.business_access a
  left join public.business_profiles p on p.user_id = a.owner_id
  where a.accountant_email = public.current_verified_email()
  union all
  select v.owner_id,
         coalesce(nullif(btrim(p.business_name), ''), 'Business'),
         true,
         true
  from public.business_viewing v
  left join public.business_profiles p on p.user_id = v.owner_id
  where v.user_id = auth.uid()
    and public.is_super_admin()
    and not exists (select 1 from public.business_access a
                    where a.owner_id = v.owner_id
                      and a.accountant_email = public.current_verified_email())
  order by 2;
$$;
revoke all on function public.shared_businesses() from public, anon;
grant execute on function public.shared_businesses() to authenticated;

-- Suspended businesses ------------------------------------------------------
create table if not exists public.account_flags (
  user_id uuid primary key,
  suspended_at timestamptz,
  suspended_by uuid,
  reason text
);
alter table public.account_flags enable row level security;
revoke all on table public.account_flags from anon, authenticated;

-- Platform settings -----------------------------------------------------------
create table if not exists public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.platform_settings enable row level security;
revoke all on table public.platform_settings from anon, authenticated;
insert into public.platform_settings (key, value) values
  ('enforce_plan_limits', 'false'),
  ('signups_open', 'true'),
  ('notice_banner', '{"text": "", "colour": "sky", "starts_at": null, "ends_at": null}'),
  ('support_contact', '{"whatsapp": "", "email": ""}')
on conflict (key) do nothing;

create or replace function public.platform_setting(p_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select value from public.platform_settings where key = p_key;
$$;
revoke all on function public.platform_setting(text) from public, anon, authenticated;

-- What any visitor may know: whether sign-ups are open, the current notice
-- banner (only while it is due) and the support contact.
create or replace function public.platform_public_settings()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'signups_open', coalesce((public.platform_setting('signups_open'))::boolean, true),
    'support_contact', coalesce(public.platform_setting('support_contact'), '{}'::jsonb),
    'notice_banner', (
      select case
        when coalesce(b ->> 'text', '') = '' then null
        when b ->> 'starts_at' is not null and (b ->> 'starts_at')::timestamptz > now() then null
        when b ->> 'ends_at' is not null and (b ->> 'ends_at')::timestamptz < now() then null
        else b
      end
      from (select public.platform_setting('notice_banner') as b) s)
  );
$$;

-- S3: "This email already has an account. Log in instead." Emails are
-- compared lower-case and trimmed.
create or replace function public.email_registered(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from auth.users
    where lower(btrim(email)) = lower(btrim(coalesce(p_email, '')))
  );
$$;

-- What the app checks at each login: suspended, the forced password change
-- after an admin reset, and the public settings.
create or replace function public.my_account_status()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'suspended', exists (select 1 from public.account_flags f
                         where f.user_id = auth.uid() and f.suspended_at is not null),
    'must_change_password', coalesce(
      (select (u.raw_user_meta_data ->> 'must_change_password')::boolean
       from auth.users u where u.id = auth.uid()), false),
    'super_admin', public.is_super_admin_member(),
    'settings', public.platform_public_settings()
  ) end;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'is_super_admin_member()', 'is_super_admin()', 'require_super_admin()',
    'my_account_status()'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  foreach f in array array['platform_public_settings()', 'email_registered(text)'] loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
