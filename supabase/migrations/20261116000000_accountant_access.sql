-- Accountant access: a business owner can let another Simplek account (by
-- email) view the business's documents and reports, read-only.
--
-- How it works: every signed-in user "views" exactly one business at a time,
-- their own by default. An invited accountant can switch to a business shared
-- with them; read policies follow public.viewing_business(). Write policies
-- are unchanged (auth.uid() = user_id), so an accountant can never create,
-- edit or delete another business's rows, and record_invoice_payment still
-- checks ownership. Removing the invite ends access immediately.
begin;

create table if not exists public.business_access (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  accountant_email text not null
    check (accountant_email = lower(btrim(accountant_email)) and accountant_email like '%_@_%'),
  created_at timestamptz not null default now(),
  unique (owner_id, accountant_email)
);
create index if not exists business_access_email_idx
  on public.business_access (accountant_email);

-- Which shared business a user is currently viewing; no row means their own.
create table if not exists public.business_viewing (
  user_id uuid primary key references auth.users(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade
);

alter table public.business_access enable row level security;
alter table public.business_viewing enable row level security;
revoke all on public.business_viewing from public, anon, authenticated;
revoke all on public.business_access from public, anon;
grant select, insert, delete on public.business_access to authenticated;

-- The caller's email, only once it has been confirmed. An unconfirmed address
-- must never match an invite, or anyone could claim an accountant's email.
create or replace function public.current_verified_email()
returns text language sql stable security definer set search_path = public as $$
  select lower(u.email) from auth.users u
  where u.id = auth.uid() and u.email_confirmed_at is not null;
$$;

create or replace function public.viewing_business()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select v.owner_id
       from public.business_viewing v
      where v.user_id = auth.uid()
        and exists (
          select 1 from public.business_access a
          where a.owner_id = v.owner_id
            and a.accountant_email = public.current_verified_email()
        )),
    auth.uid()
  );
$$;

-- Switch to a shared business, or back to your own with null.
create or replace function public.set_viewing_business(p_owner_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
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
    raise exception 'You do not have access to this business';
  end if;
  insert into public.business_viewing (user_id, owner_id)
    values (auth.uid(), p_owner_id)
    on conflict (user_id) do update set owner_id = excluded.owner_id;
  return p_owner_id;
end;
$$;

-- Businesses shared with the caller.
create or replace function public.shared_businesses()
returns table (owner_id uuid, business_name text, viewing boolean)
language sql stable security definer set search_path = public as $$
  select a.owner_id,
         coalesce(nullif(btrim(p.business_name), ''), 'Business'),
         a.owner_id = public.viewing_business()
  from public.business_access a
  left join public.business_profiles p on p.user_id = a.owner_id
  where a.accountant_email = public.current_verified_email()
  order by 2;
$$;

revoke all on function public.current_verified_email() from public, anon;
revoke all on function public.viewing_business() from public, anon;
revoke all on function public.set_viewing_business(uuid) from public, anon;
revoke all on function public.shared_businesses() from public, anon;
grant execute on function public.current_verified_email() to authenticated;
grant execute on function public.viewing_business() to authenticated;
grant execute on function public.set_viewing_business(uuid) to authenticated;
grant execute on function public.shared_businesses() to authenticated;

-- Invites: owners manage their own; an accountant can see invites to them.
drop policy if exists "Owners read their invites" on public.business_access;
create policy "Owners read their invites" on public.business_access
  for select to authenticated
  using (owner_id = auth.uid()
         or accountant_email = (select public.current_verified_email()));

drop policy if exists "Owners create invites" on public.business_access;
create policy "Owners create invites" on public.business_access
  for insert to authenticated
  with check (owner_id = auth.uid()
              and accountant_email is distinct from (select public.current_verified_email()));

drop policy if exists "Owners remove invites" on public.business_access;
create policy "Owners remove invites" on public.business_access
  for delete to authenticated
  using (owner_id = auth.uid());

-- Read policies now follow the business being viewed.
drop policy if exists "Users read own invoices" on public.invoices;
drop policy if exists "Read the business being viewed" on public.invoices;
create policy "Read the business being viewed" on public.invoices
  for select to authenticated
  using (user_id = (select public.viewing_business()));

drop policy if exists "Users read own invoice items" on public.invoice_items;
drop policy if exists "Read the business being viewed" on public.invoice_items;
create policy "Read the business being viewed" on public.invoice_items
  for select to authenticated
  using (exists (
    select 1 from public.invoices i
    where i.id = invoice_id and i.user_id = (select public.viewing_business())
  ));

drop policy if exists "Users read own quotations" on public.quotations;
drop policy if exists "Read the business being viewed" on public.quotations;
create policy "Read the business being viewed" on public.quotations
  for select to authenticated
  using (user_id = (select public.viewing_business()));

drop policy if exists "Users read own quotation items" on public.quotation_items;
drop policy if exists "Read the business being viewed" on public.quotation_items;
create policy "Read the business being viewed" on public.quotation_items
  for select to authenticated
  using (exists (
    select 1 from public.quotations q
    where q.id = quotation_id and q.user_id = (select public.viewing_business())
  ));

drop policy if exists "Users can read their customers" on public.customers;
drop policy if exists "Read the business being viewed" on public.customers;
create policy "Read the business being viewed" on public.customers
  for select to authenticated
  using (user_id = (select public.viewing_business()));

drop policy if exists "Users can read their products" on public.products;
drop policy if exists "Read the business being viewed" on public.products;
create policy "Read the business being viewed" on public.products
  for select to authenticated
  using (user_id = (select public.viewing_business()));

drop policy if exists "Users can read their business profile" on public.business_profiles;
drop policy if exists "Read the business being viewed" on public.business_profiles;
create policy "Read the business being viewed" on public.business_profiles
  for select to authenticated
  using (user_id = (select public.viewing_business()));

-- While viewing another business, nothing new can be created at all. Without
-- this, a record made by an accountant in view mode would be saved into the
-- accountant's own business, where they could not see it.
do $$
declare
  t text;
begin
  foreach t in array array['invoices', 'quotations', 'customers', 'products', 'business_profiles'] loop
    execute format('drop policy if exists "No new records while viewing another business" on public.%I', t);
    execute format(
      'create policy "No new records while viewing another business" on public.%I '
      'as restrictive for insert to authenticated '
      'with check ((select public.viewing_business()) = auth.uid())', t);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
