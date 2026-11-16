-- Run as database owner with at least two users in auth.users.
-- Every change is rolled back.
begin;
do $$
declare
  owner_id uuid;
  accountant_id uuid;
  invitee text;
  inv uuid := gen_random_uuid();
  own_inv uuid := gen_random_uuid();
  owner_count integer;
  n integer;
begin
  select id into owner_id from auth.users order by id limit 1;
  select id, lower(email) into accountant_id, invitee
    from auth.users where id <> owner_id and email is not null order by id limit 1;
  if accountant_id is null then raise exception 'Need two existing users'; end if;
  update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now())
    where id = accountant_id;

  insert into public.invoices (id, user_id, invoice_number, customer_name, invoice_date, total_amount, balance_amount)
    values (inv, owner_id, 'QA/ACC/1', 'Access fixture', '2088-04-01', 100, 100),
           (own_inv, accountant_id, 'QA/ACC/2', 'Own fixture', '2088-04-01', 50, 50);
  select count(*) into owner_count from public.invoices where user_id = owner_id;

  if has_function_privilege('anon', 'public.viewing_business()', 'execute')
     or has_function_privilege('anon', 'public.set_viewing_business(uuid)', 'execute') then
    raise exception 'anon can use accountant functions';
  end if;

  -- Before any invite: no access, and switching is refused.
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', accountant_id::text, true);
  if exists (select 1 from public.invoices where id = inv) then
    raise exception 'Uninvited user can read another business';
  end if;
  begin
    perform public.set_viewing_business(owner_id);
    raise exception 'Uninvited switch was accepted';
  exception when raise_exception then
    if sqlerrm <> 'You do not have access to this business' then raise; end if;
  end;
  -- An accountant cannot invite themselves into someone else's business.
  begin
    insert into public.business_access (owner_id, accountant_email) values (owner_id, invitee);
    raise exception 'Self-granted access was accepted';
  exception when insufficient_privilege then null;
  end;

  -- Owner invites the accountant.
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  insert into public.business_access (accountant_email) values (invitee);
  begin
    insert into public.business_access (accountant_email) values (public.current_verified_email());
    raise exception 'Owner invited themselves';
  exception when insufficient_privilege then null;
  end;

  -- Accountant still sees their own business until they switch.
  perform set_config('request.jwt.claim.sub', accountant_id::text, true);
  if exists (select 1 from public.invoices where id = inv) then
    raise exception 'Invite alone exposed the business';
  end if;
  if (select count(*) from public.shared_businesses()) < 1 then
    raise exception 'Shared business is not listed';
  end if;
  perform public.set_viewing_business(owner_id);
  select count(*) into n from public.invoices;
  if n <> owner_count then
    raise exception 'Accountant sees % invoices, owner has %', n, owner_count;
  end if;
  if exists (select 1 from public.invoices where id = own_inv) then
    raise exception 'Businesses are mixed while viewing';
  end if;

  -- Read-only: no edits, deletes, inserts or payments on the owner's data.
  update public.invoices set customer_name = 'Tampered' where id = inv;
  delete from public.invoices where id = inv;
  begin
    insert into public.invoices (user_id, invoice_number, customer_name, invoice_date)
      values (owner_id, 'QA/ACC/3', 'Forged', '2088-04-01');
    raise exception 'Accountant created an invoice for the owner';
  exception when insufficient_privilege then null;
  end;
  -- Nor can anything be created in their own business while viewing another.
  begin
    insert into public.invoices (user_id, invoice_number, customer_name, invoice_date)
      values (accountant_id, 'QA/ACC/4', 'Misplaced', '2088-04-01');
    raise exception 'A record was created while viewing another business';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.record_invoice_payment(inv, 1, 'cash');
    raise exception 'Accountant recorded a payment';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;
  reset role;
  if (select customer_name from public.invoices where id = inv) <> 'Access fixture' then
    raise exception 'Accountant changed or deleted the invoice';
  end if;

  -- The owner is unaffected throughout.
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  select count(*) into n from public.invoices;
  if n <> owner_count then raise exception 'Owner lost sight of their invoices'; end if;

  -- An unconfirmed email never matches an invite.
  reset role;
  update auth.users set email_confirmed_at = null where id = accountant_id;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', accountant_id::text, true);
  if exists (select 1 from public.invoices where id = inv) then
    raise exception 'Unconfirmed email kept access';
  end if;
  reset role;
  update auth.users set email_confirmed_at = now() where id = accountant_id;

  -- Removing the invite ends access at once, without the accountant acting.
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', accountant_id::text, true);
  if not exists (select 1 from public.invoices where id = inv) then
    raise exception 'Access did not return after confirmation';
  end if;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  delete from public.business_access where accountant_email = invitee;
  perform set_config('request.jwt.claim.sub', accountant_id::text, true);
  if exists (select 1 from public.invoices where id = inv) then
    raise exception 'Access survived removal of the invite';
  end if;
  if not exists (select 1 from public.invoices where id = own_inv) then
    raise exception 'Accountant did not return to their own business';
  end if;
  reset role;
end;
$$;
rollback;
select 'PASS: invite required, verified email required, read-only, no mixing, owner unaffected, revocation immediate; all test writes rolled back' as result;
