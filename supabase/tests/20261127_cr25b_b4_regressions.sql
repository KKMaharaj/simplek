-- CR-25B B4 (25 Nov 2026): consents, nominee, privacy requests, account
-- deletion with 30 days' grace, and the clean-up. Uses made-up logins
-- created inside this transaction; the clock is moved with p_now, so no
-- real account is touched. Run as database owner. Everything is rolled back.
begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  stale_id uuid := gen_random_uuid();
  fresh_id uuid := gen_random_uuid();
  other_id uuid := gen_random_uuid();
  due timestamptz;
  n integer;
  failed boolean;
  request public.privacy_requests;
  items jsonb := '[{"item_name":"B4 item","quantity":1,"unit_price":100,
    "taxable_amount":100,"gst_rate":0,"tax_amount":0,"total_amount":100}]';
  header jsonb := '{"customer_name":"B4 customer","invoice_date":"2094-05-01",
    "subtotal":100,"tax_amount":0,"total_amount":100}';
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'b4-owner-' || owner_id || '@example.com', now(), now()),
    (stale_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'b4-stale-' || stale_id || '@example.com', now() - interval '45 days', now()),
    (fresh_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'b4-fresh-' || fresh_id || '@example.com', now() - interval '5 days', now()),
    (other_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'b4-other-' || other_id || '@example.com', now() - interval '45 days', now());
  insert into public.business_profiles (user_id, business_name, owner_name)
  values (owner_id, 'B4 Test Traders', 'B4 Owner'), (other_id, 'B4 Other', 'Other');

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.7, 10.0.0.1"}', true);

  -- Consent: needed, recorded once with the IP, then not needed.
  if not public.consent_needed('2026-11-27') then raise exception 'Consent should be needed'; end if;
  perform public.record_consent('2026-11-27', 'web', 'Chrome 131', now() + interval '1 day');
  perform public.record_consent('2026-11-27', 'web', 'Chrome 131');
  select count(*) into n from public.consents
    where user_id = owner_id and ip = '203.0.113.7' and consented_at <= now();
  if n <> 1 then raise exception 'Expected one consent with the IP, got %', n; end if;
  if public.consent_needed('2026-11-27') then raise exception 'Consent still needed'; end if;
  if not public.consent_needed('2027-01-01') then raise exception 'A new version needs consent'; end if;
  failed := false;
  begin
    insert into public.consents (user_id, notice_version, consented_at, source)
      values (owner_id, 'forged', now(), 'web');
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'The app could write consents directly'; end if;

  -- Nominee: own row only.
  insert into public.privacy_nominees (name, relation, contact)
    values ('Asha', 'Sister', '9876543210');
  begin
    insert into public.privacy_nominees (user_id, name, relation, contact)
      values (other_id, 'X', 'Y', 'zzz');
    raise exception 'Set a nominee for someone else';
  exception when insufficient_privilege or check_violation then null;
  end;

  -- Raise a concern: open, due in 30 days; the status can't be set or changed.
  insert into public.privacy_requests (message, due_at, created_at)
    values ('Please tell me what you store', now() + interval '1 year', now() - interval '1 year')
    returning * into request;
  if request.status <> 'open' or request.due_at > now() + interval '30 days 1 minute'
     or request.due_at < now() + interval '29 days 23 hours' then
    raise exception 'Request dates or status wrong: % %', request.status, request.due_at;
  end if;
  failed := false;
  begin
    insert into public.privacy_requests (message, status) values ('x', 'closed');
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'A request was raised already closed'; end if;
  failed := false;
  begin
    update public.privacy_requests set status = 'closed' where id = request.id;
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'The user could change a request status'; end if;

  -- Some business data to delete later.
  perform public.save_invoice(gen_random_uuid(), header, items, false, 'QB4');
  insert into public.customers (user_id, name) values (owner_id, 'B4 customer');

  -- Download my data: everything of this account, deleted invoices included.
  declare
    exported jsonb;
    deleted_id uuid := gen_random_uuid();
  begin
    perform public.save_invoice(deleted_id, header || '{"invoice_date":"2094-05-02"}', items, false, 'QB4');
    perform public.record_invoice_payment(deleted_id, 40, 'cash', '2094-05-03');
    perform public.delete_invoice(deleted_id);
    exported := public.export_my_data();
    if jsonb_array_length(exported -> 'invoices') <> 2
       or jsonb_array_length(exported -> 'invoice_items') <> 2
       or jsonb_array_length(exported -> 'payments') <> 1
       or jsonb_array_length(exported -> 'customers') <> 1
       or jsonb_array_length(exported -> 'consents') <> 1
       or exported -> 'nominee' ->> 'name' <> 'Asha'
       or exported -> 'business_profile' ->> 'business_name' <> 'B4 Test Traders'
       or exported -> 'account' ->> 'email' not like 'b4-owner-%' then
      raise exception 'Export is incomplete: %', exported - 'account';
    end if;
    perform set_config('request.jwt.claim.sub', other_id::text, true);
    if jsonb_array_length(public.export_my_data() -> 'invoices') <> 0 then
      raise exception 'Another login exported this account''s invoices';
    end if;
    perform set_config('request.jwt.claim.sub', owner_id::text, true);
  end;

  -- Deletion needs the exact business name.
  failed := false;
  begin
    perform public.request_account_deletion('B4 Test');
  exception when sqlstate '22000' then failed := true;
  end;
  if not failed then raise exception 'Deletion accepted a wrong business name'; end if;
  due := public.request_account_deletion('  b4 test traders ');
  if due < now() + interval '29 days 23 hours' then raise exception 'Grace period too short: %', due; end if;
  if public.account_deletion_due() is distinct from due then raise exception 'Deletion not pending'; end if;

  -- A login within the 30 days cancels it.
  if public.cancel_account_deletion() is distinct from due then raise exception 'Cancel did not report the date'; end if;
  if public.account_deletion_due() is not null then raise exception 'Deletion still pending after login'; end if;
  if public.cancel_account_deletion() is not null then raise exception 'Cancelled twice'; end if;

  -- Asked again, and this time no login: due on day 31.
  due := public.request_account_deletion('B4 Test Traders');

  -- The app can't run the clean-up.
  failed := false;
  begin
    perform public.purge_account(owner_id);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'The app could purge an account'; end if;

  reset role;
  set local role service_role;
  if exists (select 1 from public.privacy_due_accounts(now() + interval '29 days') d where d = owner_id) then
    raise exception 'Due before day 31';
  end if;
  if not exists (select 1 from public.privacy_due_accounts(now() + interval '31 days') d where d = owner_id) then
    raise exception 'Not due on day 31';
  end if;
  perform public.purge_account(owner_id);
  reset role;

  if exists (select 1 from auth.users where id = owner_id) then raise exception 'Login not deleted'; end if;
  select count(*) into n from (
    select 1 from public.invoices where user_id = owner_id
    union all select 1 from public.customers where user_id = owner_id
    union all select 1 from public.business_profiles where user_id = owner_id
    union all select 1 from public.consents where user_id = owner_id
    union all select 1 from public.privacy_nominees where user_id = owner_id
    union all select 1 from public.privacy_requests where user_id = owner_id) left_over;
  if n <> 0 then raise exception '% rows of the deleted account are left', n; end if;
  if (select completed_at from public.account_deletions where user_id = owner_id) is null then
    raise exception 'Deletion not marked complete';
  end if;

  -- Audit entries stay a year, then lose their personal data.
  insert into public.audit_log (business_id, actor_id, action, entity, old_values, subject_deleted_at)
    values (stale_id, stale_id, 'edit', 'invoice', '{"invoice":{"customer_name":"x"}}', now() - interval '13 months'),
           (fresh_id, fresh_id, 'edit', 'invoice', '{"invoice":{"customer_name":"y"}}', now() - interval '2 months');

  -- Clean-up: the 45-day-old sign-up without a business goes; the 5-day-old
  -- one and the 45-day-old one with a business stay.
  set local role service_role;
  select count(*) into n from public.privacy_cleanup() c where c in (stale_id, fresh_id, other_id);
  reset role;
  if n <> 1 then raise exception 'Clean-up removed % test sign-ups, expected 1', n; end if;
  if exists (select 1 from auth.users where id = stale_id) then raise exception 'Stale sign-up kept'; end if;
  if not exists (select 1 from auth.users where id = fresh_id) then raise exception 'Recent sign-up removed'; end if;
  if not exists (select 1 from auth.users where id = other_id) then raise exception 'Account with a business removed'; end if;
  if exists (select 1 from public.audit_log where old_values ->> 'invoice' like '%"x"%') then
    raise exception 'Year-old audit entry not anonymised';
  end if;
  if not exists (select 1 from public.audit_log where business_id = fresh_id and old_values is not null) then
    raise exception 'Recent audit entry anonymised too early';
  end if;

  raise notice 'CR-25B B4 regressions passed';
end;
$$;
select 'B4 regressions reached the end' as result;
rollback;
