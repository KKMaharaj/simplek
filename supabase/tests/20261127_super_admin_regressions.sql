-- Change request 26 Nov 2026, super admin panel. A non-admin (and an admin
-- without the two-step login) can call no admin function and read no admin
-- table; usage counts deleted invoices and not drafts; the limit is enforced
-- only while the platform switch is on; suspension, support view, plans and
-- masked secrets. Made-up logins, rolled back. Run as database owner.
begin;
do $$
declare
  admin_id uuid := gen_random_uuid();
  owner_id uuid := gen_random_uuid();
  newcomer uuid := gen_random_uuid();
  f text;
  failed boolean;
  n integer;
  usage jsonb;
  result jsonb;
  deleted_id uuid := gen_random_uuid();
  header jsonb := '{"customer_name":"SA customer","invoice_date":"2096-05-01",
    "subtotal":100,"tax_amount":0,"total_amount":100}';
  items jsonb := '[{"item_name":"SA item","quantity":1,"unit_price":100,
    "taxable_amount":100,"gst_rate":0,"tax_amount":0,"total_amount":100}]';
  admin_calls text[] := array[
    'select public.admin_dashboard(current_date - 30, current_date)',
    'select public.admin_businesses()',
    'select public.admin_business(''' || gen_random_uuid() || ''')',
    'select public.admin_change_plan(''' || gen_random_uuid() || ''', ''free'', null, null, 0, ''x'')',
    'select public.admin_add_note(''' || gen_random_uuid() || ''', ''x'')',
    'select public.admin_set_suspended(''' || gen_random_uuid() || ''', true, ''x'')',
    'select public.admin_start_deletion(''' || gen_random_uuid() || ''')',
    'select public.admin_export_business(''' || gen_random_uuid() || ''')',
    'select public.admin_users()',
    'select public.admin_plans()',
    'select public.admin_save_plan(''{"code":"x","name":"X"}'')',
    'select public.admin_settings()',
    'select public.admin_save_setting(''signups_open'', ''false'')',
    'select public.admin_integrations()',
    'select public.admin_save_integration(''email'', ''{}'', ''{}'')',
    'select public.admin_audit_log()',
    'select public.admin_log_event(''list_export'', null, ''{}'')',
    'select public.require_super_admin()'
  ];
  admin_tables text[] := array['super_admins', 'plans', 'business_plans', 'admin_notes',
    'platform_settings', 'account_flags', 'audit_log'];
begin
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
  values
    (admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'sa-admin-' || admin_id || '@example.com', now(), now()),
    (owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'sa-owner-' || owner_id || '@example.com', now() - interval '40 days', now()),
    (newcomer, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'sa-new-' || newcomer || '@example.com', now(), now());
  insert into public.super_admins (user_id) values (admin_id);
  insert into public.business_profiles (user_id, business_name, owner_name)
  values (owner_id, 'SA Traders', 'SA Owner');

  -- A new business gets the Free plan.
  if not exists (select 1 from public.business_plans bp join public.plans p on p.id = bp.plan_id
                 where bp.business_id = owner_id and p.code = 'free') then
    raise exception 'New business did not get the Free plan';
  end if;
  -- One business per owner.
  begin
    insert into public.business_profiles (user_id, business_name) values (owner_id, 'Second');
    raise exception 'A second business for the same owner was accepted';
  exception when unique_violation then null;
  end;

  set local role authenticated;

  -- The owner (even with aal2) and the admin without two-step: nothing.
  foreach f in array array[owner_id::text, admin_id::text] loop
    perform set_config('request.jwt.claim.sub', f, true);
    perform set_config('request.jwt.claims', json_build_object('sub', f,
      'aal', case when f = owner_id::text then 'aal2' else 'aal1' end)::text, true);
    for n in 1 .. array_length(admin_calls, 1) loop
      failed := false;
      begin
        execute admin_calls[n];
      exception when insufficient_privilege then failed := true;
      end;
      if not failed then raise exception 'Non-admin % ran: %', f, admin_calls[n]; end if;
    end loop;
    foreach result in array array[]::jsonb[] loop end loop;
    for n in 1 .. array_length(admin_tables, 1) loop
      failed := false;
      begin
        execute format('select 1 from public.%I limit 1', admin_tables[n]);
      exception when insufficient_privilege then failed := true;
      end;
      if not failed then raise exception 'Non-admin read %', admin_tables[n]; end if;
    end loop;
    failed := false;
    begin
      perform public.integration_config('email');
    exception when insufficient_privilege then failed := true;
    end;
    if not failed then raise exception 'The app could read integration secrets'; end if;
  end loop;
  if not public.is_super_admin_member() then raise exception 'Admin not listed'; end if;
  if public.is_super_admin() then raise exception 'Admin passed without two-step'; end if;

  -- The owner works: usage counts deleted invoices, not drafts.
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  perform public.save_invoice(gen_random_uuid(), header, items, false, 'QSA');
  perform public.save_invoice(gen_random_uuid(), header, items, false, 'QSA');
  perform public.save_invoice(deleted_id, header, items, false, 'QSA');
  perform public.delete_invoice(deleted_id);
  insert into public.invoices (user_id, invoice_number, customer_name, invoice_date, status)
    values (owner_id, 'QSA/DRAFT/1', 'Draft', '2096-05-01', 'draft');
  usage := public.my_plan();
  if (usage ->> 'used')::int <> 3 or (usage ->> 'allowed')::int <> 250
     or usage ->> 'plan_code' <> 'free' then
    raise exception 'Usage wrong: %', usage;
  end if;
  if (public.my_account_status() ->> 'suspended')::boolean then raise exception 'Suspended?'; end if;

  -- The admin with two-step.
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'aal', 'aal2')::text, true);
  if not public.is_super_admin() then raise exception 'Admin with aal2 refused'; end if;
  result := public.admin_dashboard(current_date - 30, current_date);
  if (result ->> 'enrolled')::int < 1 or jsonb_array_length(result -> 'invoices_by_month') <> 12 then
    raise exception 'Dashboard wrong: %', result - 'recently_active' - 'gone_quiet';
  end if;
  result := public.admin_businesses(p_search => 'sa traders');
  if (result ->> 'total')::int <> 1
     or result -> 'rows' -> 0 ->> 'email' <> 'sa-owner-' || owner_id || '@example.com'
     or (result -> 'rows' -> 0 ->> 'used')::int <> 3 then
    raise exception 'Business list wrong: %', result;
  end if;
  result := public.admin_business(owner_id);
  if (result -> 'totals' ->> 'deleted_invoices')::int <> 1 then
    raise exception 'Detail totals wrong: %', result -> 'totals';
  end if;
  if (public.admin_users(p_search => 'sa-owner-') ->> 'total')::int <> 1 then
    raise exception 'Users page did not find the owner';
  end if;

  -- Plan limit 3: not enforced while the switch is off.
  perform public.admin_save_plan(jsonb_build_object('code', 'free', 'name', 'Free',
    'invoice_limit', 3, 'limit_period', 'lifetime'));
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  perform public.save_invoice(gen_random_uuid(), header, items, false, 'QSA');
  -- Switch on: a new invoice is refused, an edit is not.
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'aal', 'aal2')::text, true);
  perform public.admin_save_setting('enforce_plan_limits', 'true');
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  failed := false;
  begin
    perform public.save_invoice(gen_random_uuid(), header, items, false, 'QSA');
  exception when raise_exception then
    if sqlerrm not like 'You''ve used all 3 free invoices%' then raise; end if;
    failed := true;
  end;
  if not failed then raise exception 'The limit was not enforced'; end if;
  perform public.save_invoice((select id from public.invoices where user_id = owner_id
    and status <> 'draft' and deleted_at is null limit 1), header, items, true, 'QSA');

  -- Usage is 4 (one made while the switch was off). Two extra invoices
  -- granted: the limit becomes 5, so exactly one more is allowed.
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'aal', 'aal2')::text, true);
  usage := public.admin_change_plan(owner_id, 'free', current_date, null, 2, 'Goodwill');
  if (usage ->> 'allowed')::int <> 5 then raise exception 'Extra invoices not added: %', usage; end if;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  perform public.save_invoice(gen_random_uuid(), header, items, false, 'QSA');

  -- Suspended: nothing can be saved; reactivated: saving works again.
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'aal', 'aal2')::text, true);
  perform public.admin_save_setting('enforce_plan_limits', 'false');
  perform public.admin_set_suspended(owner_id, true, 'Test');
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  if not (public.my_account_status() ->> 'suspended')::boolean then raise exception 'Not suspended'; end if;
  failed := false;
  begin
    perform public.save_invoice(gen_random_uuid(), header, items, false, 'QSA');
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then raise exception 'A suspended account saved an invoice'; end if;
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'aal', 'aal2')::text, true);
  perform public.admin_set_suspended(owner_id, false, 'Paid');

  -- Support view: read-only access to the business, logged.
  perform public.set_viewing_business(owner_id);
  if public.viewing_business() <> owner_id then raise exception 'Support view did not open'; end if;
  select count(*) into n from public.invoices where user_id = owner_id;
  if n < 3 then raise exception 'Support view sees % invoices', n; end if;
  if not exists (select 1 from public.shared_businesses() s
                 where s.owner_id = public.viewing_business() and s.support) then
    raise exception 'Support view missing from shared_businesses';
  end if;
  update public.customers set name = 'changed' where user_id = owner_id;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'Support view changed data'; end if;
  perform public.set_viewing_business(null);

  -- Integrations: secrets masked, never returned whole.
  perform public.admin_save_integration('email', '{"provider":"smtp","host":"smtp.example.com"}',
    '{"password":"very-secret-1234"}');
  result := public.admin_integrations();
  if result -> 'email' -> 'secrets' ->> 'password' <> '••••1234'
     or result::text like '%very-secret%' then
    raise exception 'Secret not masked: %', result -> 'email';
  end if;
  perform public.admin_add_note(owner_id, 'Called on 26 Nov; wants Tally help');
  perform public.admin_log_event('list_export', null, '{"rows": 1}');

  -- Every admin action is in the audit log.
  reset role;
  select count(*) into n from public.audit_log
   where actor_id = admin_id and action in ('plan_saved', 'setting_change', 'plan_change',
     'suspend', 'reactivate', 'support_view', 'integration_change', 'note_added', 'list_export');
  if n < 9 then raise exception 'Only % admin actions logged', n; end if;
  if exists (select 1 from public.audit_log where new_values::text like '%very-secret%') then
    raise exception 'A secret reached the audit log';
  end if;

  -- One email = one account: the check ignores case and spaces; anon may ask.
  set local role anon;
  if not public.email_registered('  SA-OWNER-' || upper(owner_id::text) || '@EXAMPLE.COM ') then
    raise exception 'Existing email not found';
  end if;
  if public.email_registered('nobody-' || gen_random_uuid() || '@example.com') then
    raise exception 'Unknown email reported as registered';
  end if;
  if not (public.platform_public_settings() ->> 'signups_open')::boolean then
    raise exception 'Sign-ups should be open';
  end if;
  reset role;

  raise notice 'Super admin regressions passed';
end;
$$;
select 'super admin regressions reached the end' as result;
rollback;
