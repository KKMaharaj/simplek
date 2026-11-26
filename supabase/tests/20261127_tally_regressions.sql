-- Change request 26 Nov 2026, Tally. Who can export and save settings; what
-- the export data holds (no drafts, cancelled or deleted invoices; payment
-- numbering per invoice; Reports' totals); "Download" marks vouchers
-- exported; exported-then-deleted invoices are listed; renames are logged.
-- Made-up logins, rolled back. Run as database owner.
begin;
do $$
declare
  owner_id uuid := gen_random_uuid();
  accountant uuid := gen_random_uuid();
  stranger uuid := gen_random_uuid();
  cust uuid := gen_random_uuid();
  prod uuid := gen_random_uuid();
  inv_a uuid := gen_random_uuid();
  inv_b uuid := gen_random_uuid();
  inv_draft uuid := gen_random_uuid();
  inv_deleted uuid := gen_random_uuid();
  data jsonb;
  result jsonb;
  failed boolean;
  n integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
  values
    (owner_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'tl-owner-' || owner_id || '@example.com', now(), now(), now()),
    (accountant, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'tl-ca-' || accountant || '@example.com', now(), now(), now()),
    (stranger, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'tl-x-' || stranger || '@example.com', now(), now(), now());
  insert into public.business_profiles (user_id, business_name, owner_name, gst_registered, business_state)
  values (owner_id, 'TL Traders', 'TL Owner', true, 'Karnataka');
  insert into public.business_access (owner_id, accountant_email)
  values (owner_id, 'tl-ca-' || accountant || '@example.com');
  insert into public.customers (id, user_id, name, phone, state, is_active)
  values (cust, owner_id, 'TL Customer', '9876500001', 'Karnataka', true);
  insert into public.products (id, user_id, name, product_type, uqc_code, hsn_sac_code, gst_rate, selling_price, is_active)
  values (prod, owner_id, 'TL Chair', 'product', 'NOS', '94017100', 18, 500, true);

  insert into public.invoices (id, user_id, invoice_number, customer_id, customer_name, invoice_date,
    status, subtotal, tax_amount, cgst_amount, sgst_amount, igst_amount, total_amount, balance_amount, tax_type)
  values
    (inv_a, owner_id, 'TL/01', cust, 'TL Customer', '2097-04-02', 'sent', 1000, 180, 90, 90, 0, 1180, 1180, 'cgst_sgst'),
    (inv_b, owner_id, 'TL/02', null, 'tl customer', '2097-04-03', 'sent', 500, 25, 12.5, 12.5, 0, 525, 525, 'cgst_sgst'),
    (inv_draft, owner_id, 'TL/03', cust, 'TL Customer', '2097-04-04', 'draft', 100, 18, 9, 9, 0, 118, 118, 'cgst_sgst'),
    (inv_deleted, owner_id, 'TL/04', cust, 'TL Customer', '2097-04-05', 'sent', 200, 36, 18, 18, 0, 236, 236, 'cgst_sgst');
  insert into public.invoice_items (invoice_id, product_id, product_name, item_name, quantity, uqc_code, unit_price,
    taxable_amount, gst_rate, tax_amount, cgst_amount, sgst_amount, igst_amount, total_amount)
  values
    (inv_a, prod, 'TL Chair', 'TL Chair', 2, 'NOS', 500, 1000, 18, 180, 90, 90, 0, 1180),
    (inv_b, null, 'TL Tea', 'TL Tea', 1, 'KGS', 500, 500, 5, 25, 12.5, 12.5, 0, 525),
    (inv_draft, prod, 'TL Chair', 'TL Chair', 1, 'NOS', 100, 100, 18, 18, 9, 9, 0, 118),
    (inv_deleted, prod, 'TL Chair', 'TL Chair', 1, 'NOS', 200, 200, 18, 36, 18, 18, 0, 236);
  insert into public.payments (invoice_id, amount, payment_mode, payment_method, payment_date, created_at)
  values
    (inv_a, 500, 'cash', 'cash', '2097-04-06', now() - interval '2 minutes'),
    (inv_a, 680, 'upi', 'upi', '2097-04-07', now() - interval '1 minute'),
    (inv_b, 525, 'bank_transfer', 'bank_transfer', '2097-05-01', now());

  set local role authenticated;

  -- A stranger: nothing, whichever function.
  perform set_config('request.jwt.claim.sub', stranger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', stranger, 'aal', 'aal1')::text, true);
  for n in 1 .. 4 loop
    failed := false;
    begin
      case n
        when 1 then perform public.tally_export_data(owner_id, '2097-04-01', '2097-04-30');
        when 2 then perform public.tally_settings_get(owner_id);
        when 3 then perform public.tally_settings_save(owner_id, '{}', '[]');
        else perform public.tally_mark_exported(owner_id, '[{"guid":"simplek-sales-x","kind":"sales","number":"x"}]');
      end case;
    exception when insufficient_privilege then failed := true;
    end;
    if not failed then
      raise exception 'A stranger could call Tally function %', n;
    end if;
  end loop;
  -- Nobody reads the tables directly.
  foreach result in array array['"tally_exports"'::jsonb, '"tally_settings"'::jsonb] loop
    failed := false;
    begin
      execute format('select count(*) from public.%I', result #>> '{}');
    exception when insufficient_privilege then failed := true;
    end;
    if not failed then
      raise exception 'The app can read % directly', result #>> '{}';
    end if;
  end loop;

  -- The owner: two invoices (no draft), the deleted one excluded later.
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  data := public.tally_export_data(owner_id, '2097-04-01', '2097-04-30');
  if jsonb_array_length(data -> 'invoices') <> 3 then
    raise exception 'Expected 3 invoices (no draft), got %', jsonb_array_length(data -> 'invoices');
  end if;
  if data #>> '{invoices,0,invoice_number}' <> 'TL/01'
     or data #>> '{invoices,0,items,0,hsn_sac_code}' <> '94017100'
     or data #>> '{invoices,0,items,0,product_type}' <> 'product'
     or data #>> '{invoices,0,customer,phone}' <> '9876500001' then
    raise exception 'Invoice data is wrong: %', data -> 'invoices' -> 0;
  end if;
  -- An invoice with no customer link finds the customer by name.
  if data #>> '{invoices,1,customer,id}' <> cust::text then
    raise exception 'The customer was not matched by name: %', data #> '{invoices,1,customer}';
  end if;
  -- Payments in the dates only, numbered per invoice.
  if jsonb_array_length(data -> 'payments') <> 2
     or (data #>> '{payments,0,sequence}')::int <> 1
     or (data #>> '{payments,1,sequence}')::int <> 2
     or data #>> '{payments,1,payment_method}' <> 'upi' then
    raise exception 'Payments are wrong: %', data -> 'payments';
  end if;
  if (data #>> '{report,total}')::numeric <> 1941 or (data #>> '{report,invoices}')::int <> 3 then
    raise exception 'Report totals are wrong: %', data -> 'report';
  end if;
  if data ->> 'gst' <> 'true' or data ->> 'company' <> 'TL Traders' then
    raise exception 'Company data is wrong';
  end if;

  -- The accountant exports and marks; marking twice counts twice.
  perform set_config('request.jwt.claim.sub', accountant::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', accountant, 'aal', 'aal1')::text, true);
  perform public.tally_export_data(owner_id, '2097-04-01', '2097-04-30');
  perform public.tally_mark_exported(owner_id, jsonb_build_array(
    jsonb_build_object('guid', 'simplek-sales-' || inv_a, 'kind', 'sales', 'number', 'TL/01'),
    jsonb_build_object('guid', 'simplek-sales-' || inv_deleted, 'kind', 'sales', 'number', 'TL/04'),
    jsonb_build_object('guid', 'not-ours', 'kind', 'sales', 'number', 'x')));
  perform public.tally_mark_exported(owner_id, jsonb_build_array(
    jsonb_build_object('guid', 'simplek-sales-' || inv_a, 'kind', 'sales', 'number', 'TL/01')));
  result := public.tally_settings_save(owner_id,
    '{"company":"TL Traders Pvt Ltd","ledgers":{"sales":"Sales Accounts"}}',
    '[{"setting":"Company","from":"TL Traders","to":"TL Traders Pvt Ltd"},
      {"setting":"Sales","from":"Sales","to":"Sales Accounts"},
      {"setting":"Cash","from":"Cash","to":"Cash"}]');
  if jsonb_array_length(result -> 'renames') <> 2
     or result #>> '{settings,company}' <> 'TL Traders Pvt Ltd'
     or result #>> '{renames,0,by}' <> 'tl-ca-' || accountant || '@example.com' then
    raise exception 'Settings or renames are wrong: %', result;
  end if;
  if not (result -> 'rates') @> '[5, 18]'::jsonb or not (result -> 'units') @> '["NOS", "KGS"]'::jsonb then
    raise exception 'Rates or units used are wrong: % %', result -> 'rates', result -> 'units';
  end if;

  reset role;
  select count into n from public.tally_exports
   where business_id = owner_id and guid = 'simplek-sales-' || inv_a;
  if n <> 2 then
    raise exception 'Export count should be 2, got %', n;
  end if;
  if exists (select 1 from public.tally_exports where business_id = owner_id and guid = 'not-ours') then
    raise exception 'A non-Simplek GUID was recorded';
  end if;
  if (select count(*) from public.audit_log where business_id = owner_id and action = 'tally_export') <> 2 then
    raise exception 'Exports were not logged';
  end if;

  -- The owner deletes an exported invoice: it leaves the data and is listed.
  update public.invoices set deleted_at = now(), deleted_by = owner_id where id = inv_deleted;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', owner_id, 'aal', 'aal1')::text, true);
  data := public.tally_export_data(owner_id, '2097-04-01', '2097-04-30');
  if jsonb_array_length(data -> 'invoices') <> 2
     or (data #>> '{report,total}')::numeric <> 1705 then
    raise exception 'The deleted invoice was still exported';
  end if;
  if jsonb_array_length(data -> 'exported_then_deleted') <> 1
     or data #>> '{exported_then_deleted,0,number}' <> 'TL/04' then
    raise exception 'Exported-then-deleted is wrong: %', data -> 'exported_then_deleted';
  end if;
  if not exists (select 1 from jsonb_array_elements(data -> 'exported') e
                 where e ->> 'guid' = 'simplek-sales-' || inv_a) then
    raise exception 'Exported vouchers are missing';
  end if;
  if (data #>> '{settings,company}') <> 'TL Traders Pvt Ltd' then
    raise exception 'Saved settings are not in the export data';
  end if;
  reset role;
end;
$$;
select 'tally regressions reached the end' as result;
rollback;
