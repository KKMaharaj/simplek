-- CR-25 (25 Nov 2026): description on invoices and quotations, State and
-- District master data, and the business address fields.
-- Run as database owner with at least one user in auth.users.
-- Every change is rolled back.
begin;
do $$
declare
  owner_id uuid;
  invoice_id uuid := gen_random_uuid();
  quote_id uuid;
  inv public.invoices;
  n integer;
  long_text text := repeat('x', 301);
  items jsonb := '[{"item_name":"Fixture item","quantity":1,"unit_price":100,
    "taxable_amount":100,"gst_rate":0,"tax_amount":0,"total_amount":100}]';
  header jsonb := '{"customer_name":"CR25 fixture","invoice_date":"2091-05-01",
    "subtotal":100,"tax_amount":0,"total_amount":100,"terms":"t"}';
begin
  select id into owner_id from auth.users order by id limit 1;
  if owner_id is null then raise exception 'Need an existing user'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);

  -- Description: saved, kept when an older app sends none, cleared by ''.
  inv := public.save_invoice(invoice_id, header, items, false, 'QCR', 'Valid 2 years');
  if inv.description is distinct from 'Valid 2 years' then
    raise exception 'Description not saved: %', inv.description;
  end if;
  inv := public.save_invoice(invoice_id, header, items, true, 'QCR');
  if inv.description is distinct from 'Valid 2 years' then
    raise exception 'An edit without p_description lost it: %', inv.description;
  end if;
  inv := public.save_invoice(invoice_id, header, items, true, 'QCR', '');
  if inv.description is not null then
    raise exception 'Empty description should clear it: %', inv.description;
  end if;
  begin
    perform public.save_invoice(gen_random_uuid(), header, items, false, 'QCR', long_text);
    raise exception 'A 301-character description was accepted';
  exception when check_violation then null;
  end;

  -- Conversion copies the quotation's description.
  insert into public.quotations (user_id, quotation_number, customer_name, quotation_date,
      valid_until, subtotal, tax_amount, total_amount, status, description)
    values (owner_id, 'QCRQ/2091-92/01', 'CR25 fixture', '2091-05-01', '2091-05-31',
      100, 0, 100, 'draft', 'From the quotation')
    returning id into quote_id;
  insert into public.quotation_items (quotation_id, item_name, quantity, unit_price,
      taxable_amount, gst_rate, tax_amount, total_amount)
    values (quote_id, 'Fixture item', 1, 100, 100, 0, 0, 100);
  inv := public.convert_quotation_to_invoice(quote_id, '2091-05-02', 'QCR');
  if inv.description is distinct from 'From the quotation' then
    raise exception 'Conversion lost the description: %', inv.description;
  end if;

  -- States: every signed-in user can read all 36; nobody can write.
  select count(*) into n from public.states;
  if n <> 36 then raise exception 'Expected 36 states and UTs, got %', n; end if;
  select count(*) into n from public.states where type = 'UT';
  if n <> 8 then raise exception 'Expected 8 UTs, got %', n; end if;
  if (select name from public.states where gst_state_code = '29') <> 'Karnataka'
     or (select name from public.states where gst_state_code = '32') <> 'Kerala'
     or (select gst_state_code from public.states where name = 'Andhra Pradesh') <> '37' then
    raise exception 'GST state codes are wrong';
  end if;
  select count(*) into n from public.districts;
  if n < 700 then raise exception 'Expected the LGD district list (790), got %', n; end if;
  if not exists (select 1 from public.districts d join public.states s on s.id = d.state_id
                 where s.name = 'Karnataka' and d.name = 'Shivamogga') then
    raise exception 'Shivamogga is not listed under Karnataka';
  end if;
  if exists (select 1 from public.states s where not exists
             (select 1 from public.districts d where d.state_id = s.id)) then
    raise exception 'A state or UT has no districts';
  end if;
  begin
    insert into public.states (lgd_code, name, gst_state_code, type) values (99, 'X', '99', 'UT');
    raise exception 'A signed-in user could add a state';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.districts (lgd_code, name, state_id)
      values (99999, 'X', (select id from public.states limit 1));
    raise exception 'A signed-in user could add a district';
  exception when insufficient_privilege then null;
  end;

  reset role;
  set local role anon;
  begin
    perform 1 from public.states limit 1;
    raise exception 'Anonymous users could read states';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- Business address: the old address was copied into line 1; PIN format.
  select count(*) into n from public.business_profiles
    where coalesce(btrim(address), '') <> '' and coalesce(btrim(address_line1), '') = '';
  if n <> 0 then raise exception '% businesses have an address but no line 1', n; end if;
  begin
    update public.business_profiles set pincode = '077201' where user_id = owner_id;
    if found then raise exception 'PIN 077201 was accepted'; end if;
  exception when check_violation then null;
  end;
end;
$$;
rollback;
select 'PASS: description saved, kept, cleared, length-checked and converted; 36 states and the LGD districts readable, not writable, not public; old addresses copied; PIN format checked; all test writes rolled back' as result;
