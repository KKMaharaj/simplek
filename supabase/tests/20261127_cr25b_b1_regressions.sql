-- CR-25B B1 (25 Nov 2026): soft delete with Undo, numbers never reused, and
-- the audit log. Run as database owner with at least one user in
-- auth.users. Every change is rolled back.
begin;
do $$
declare
  owner_id uuid;
  stranger uuid := gen_random_uuid();
  first_id uuid := gen_random_uuid();
  second_id uuid := gen_random_uuid();
  inv public.invoices;
  first_number text;
  n integer;
  audit record;
  items jsonb := '[{"item_name":"Fixture item","quantity":1,"unit_price":100,
    "taxable_amount":100,"gst_rate":0,"tax_amount":0,"total_amount":100}]';
  header jsonb := '{"customer_name":"B1 fixture","invoice_date":"2091-06-01",
    "subtotal":100,"tax_amount":0,"total_amount":100,"terms":"t"}';
begin
  select id into owner_id from auth.users order by id limit 1;
  if owner_id is null then raise exception 'Need an existing user'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);

  inv := public.save_invoice(first_id, header, items, false, 'QBA');
  first_number := inv.invoice_number;
  perform public.record_invoice_payment(first_id, 40, 'cash', '2091-06-02');

  -- Someone else (an accountant's view included) can't delete it.
  perform set_config('request.jwt.claim.sub', stranger::text, true);
  begin
    perform public.delete_invoice(first_id);
    raise exception 'A stranger deleted the invoice';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);

  -- The old hard-delete route removes nothing.
  delete from public.invoices where id = first_id;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'A hard delete removed % invoice(s)', n; end if;

  -- Delete: gone from the app's reads, items with it.
  perform public.delete_invoice(first_id);
  select count(*) into n from public.invoices where id = first_id;
  if n <> 0 then raise exception 'A deleted invoice is still listed'; end if;
  select count(*) into n from public.invoice_items where invoice_id = first_id;
  if n <> 0 then raise exception 'A deleted invoice''s items are still listed'; end if;

  -- It can't be paid, edited or deleted again.
  begin
    perform public.record_invoice_payment(first_id, 10, 'cash', '2091-06-03');
    raise exception 'A deleted invoice took a payment';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;
  begin
    perform public.save_invoice(first_id, header, items, true, 'QBA');
    raise exception 'A deleted invoice was edited';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;
  begin
    perform public.delete_invoice(first_id);
    raise exception 'A deleted invoice was deleted twice';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;

  -- The next invoice gets the next number, not the deleted one.
  inv := public.save_invoice(second_id, header, items, false, 'QBA');
  if inv.invoice_number = first_number then
    raise exception 'The deleted number % was reused', first_number;
  end if;
  if substring(inv.invoice_number from '([0-9]+)$')::int
     <> substring(first_number from '([0-9]+)$')::int + 1 then
    raise exception 'Expected the number after %, got %', first_number, inv.invoice_number;
  end if;

  -- Undo brings it back with its payment.
  perform public.restore_invoice(first_id);
  select * into inv from public.invoices where id = first_id;
  if not found then raise exception 'Restore did not bring the invoice back'; end if;
  if inv.paid_amount <> 40 or inv.balance_amount <> 60 then
    raise exception 'Restore lost the payment: paid %, balance %', inv.paid_amount, inv.balance_amount;
  end if;
  begin
    perform public.restore_invoice(first_id);
    raise exception 'A live invoice was restored';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;

  -- An edit is logged too.
  perform public.save_invoice(first_id, header || '{"customer_name":"B1 edited"}', items, true, 'QBA');

  -- The app can't read or write the log.
  begin
    perform 1 from public.audit_log limit 1;
    raise exception 'The app could read the audit log';
  exception when insufficient_privilege then null;
  end;

  reset role;
  select string_agg(action, ',' order by id) as actions,
         bool_and(actor_id = owner_id and business_id = owner_id) as by_owner,
         min(old_values -> 'invoice' ->> 'customer_name') as old_name,
         max(jsonb_array_length(old_values -> 'payments')) as payments,
         max(jsonb_array_length(old_values -> 'items')) as item_rows
    into audit
    from public.audit_log where entity = 'invoice' and entity_id = first_id;
  if audit.actions is distinct from 'delete,restore,edit' then
    raise exception 'Expected delete,restore,edit in the log, got %', audit.actions;
  end if;
  if not audit.by_owner then raise exception 'Audit rows name the wrong person'; end if;
  if audit.old_name <> 'B1 fixture' then
    raise exception 'The edit did not log the old values: %', audit.old_name;
  end if;
  if audit.payments <> 1 or audit.item_rows <> 1 then
    raise exception 'Old values miss payments or items: % / %', audit.payments, audit.item_rows;
  end if;

  -- The deleted row is still in the database, with who deleted it.
  update public.invoices set deleted_at = now(), deleted_by = owner_id where id = second_id;
  select count(*) into n from public.invoices where id = second_id and deleted_by = owner_id;
  if n <> 1 then raise exception 'The deleted row is not kept'; end if;

  raise notice 'CR-25B B1 regressions passed';
end;
$$;
rollback;
