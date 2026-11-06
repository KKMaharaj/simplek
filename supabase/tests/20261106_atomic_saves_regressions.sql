-- Run as database owner with at least two users in auth.users.
-- Every fixture and counter change is rolled back.
begin;
do $$
declare
  owners uuid[];
  invoice_a uuid := gen_random_uuid();
  retry_id uuid := gen_random_uuid();
  request_id uuid := gen_random_uuid();
  quotation_a uuid := gen_random_uuid();
  header jsonb := jsonb_build_object(
    'customer_name', 'Regression fixture', 'invoice_date', '2088-04-01',
    'subtotal', 100, 'tax_amount', 18, 'total_amount', 118,
    'tax_type', 'igst', 'igst_amount', 18, 'place_of_supply', 'Kerala');
  items jsonb := jsonb_build_array(jsonb_build_object(
    'item_name', 'Widget', 'quantity', 1, 'unit_price', 100, 'taxable_amount', 100,
    'gst_rate', 18, 'tax_amount', 18, 'igst_amount', 18, 'total_amount', 118));
  bad_items jsonb := jsonb_build_array(jsonb_build_object(
    'item_name', 'Widget', 'quantity', 'not-a-number', 'unit_price', 100,
    'taxable_amount', 100, 'gst_rate', 18, 'tax_amount', 18, 'total_amount', 118));
  saved public.invoices;
  again public.invoices;
  paid public.payments;
  paid_again public.payments;
  counter_before bigint;
  counter_after bigint;
  n integer;
begin
  select array_agg(id order by id) into owners from auth.users;
  if cardinality(owners) < 2 then raise exception 'Need two existing users'; end if;

  -- Privileges
  if has_function_privilege('anon', 'public.record_invoice_payment(uuid,numeric,text,date,text,text,uuid)', 'execute') then
    raise exception 'anon can record payments';
  end if;
  if has_function_privilege('anon', 'public.save_invoice(uuid,jsonb,jsonb,boolean,text)', 'execute') then
    raise exception 'anon can save invoices';
  end if;
  if to_regprocedure('public.record_invoice_payment(uuid,numeric,text,date,text,text)') is not null then
    raise exception 'Old unprotected payment function still exists';
  end if;

  set local role authenticated;

  -- Create, then retry with the same id: one invoice and one number
  perform set_config('request.jwt.claim.sub', owners[1]::text, true);
  saved := public.save_invoice(invoice_a, header, items, false, 'QA');
  if saved.status <> 'sent' or saved.balance_amount <> 118 or saved.user_id <> owners[1] then
    raise exception 'Create produced wrong header: % % %', saved.status, saved.balance_amount, saved.user_id;
  end if;
  again := public.save_invoice(invoice_a, header, items, false, 'QA');
  if again.invoice_number <> saved.invoice_number then raise exception 'Retry changed the number'; end if;
  select count(*) into n from public.invoice_items where invoice_id = invoice_a;
  if n <> 1 then raise exception 'Retry duplicated items: %', n; end if;

  -- Failed create leaves nothing behind, including the number counter
  reset role;
  select last_number into counter_before from public.business_document_counters
    where user_id = owners[1] and document_type = 'invoice' and financial_year = 2088;
  set local role authenticated;
  begin
    perform public.save_invoice(retry_id, header, bad_items, false, 'QA');
    raise exception 'Bad item was accepted';
  exception when invalid_text_representation then null;
  end;
  if exists (select 1 from public.invoices where id = retry_id) then
    raise exception 'Failed create left a header behind';
  end if;
  reset role;
  select last_number into counter_after from public.business_document_counters
    where user_id = owners[1] and document_type = 'invoice' and financial_year = 2088;
  set local role authenticated;
  if counter_after is distinct from counter_before then raise exception 'Failed create used a number'; end if;

  -- Failed edit keeps the original header and items
  begin
    perform public.save_invoice(invoice_a, header || '{"customer_name":"Changed"}', bad_items, true);
    raise exception 'Bad edit was accepted';
  exception when invalid_text_representation then null;
  end;
  select count(*) into n from public.invoice_items where invoice_id = invoice_a;
  if n <> 1 then raise exception 'Failed edit lost line items'; end if;
  if (select customer_name from public.invoices where id = invoice_a) <> 'Regression fixture' then
    raise exception 'Failed edit changed the header';
  end if;

  -- A header stranded without items by an older app version gets completed,
  -- keeping its number. Older clients may also omit the payment request id.
  insert into public.invoices (id, user_id, invoice_number, customer_name, invoice_date, status, total_amount, balance_amount)
    values (retry_id, owners[1], 'QA/STRANDED', 'Regression fixture', '2088-04-01', 'draft', 118, 118);
  saved := public.save_invoice(retry_id, header, items, false, 'QA');
  if saved.invoice_number <> 'QA/STRANDED' or saved.status <> 'sent' then
    raise exception 'Stranded header was not completed: % %', saved.invoice_number, saved.status;
  end if;
  select count(*) into n from public.invoice_items where invoice_id = retry_id;
  if n <> 1 then raise exception 'Stranded header has % items', n; end if;
  paid := public.record_invoice_payment(retry_id, 1, 'cash');
  if paid.amount <> 1 or paid.client_request_id is not null then
    raise exception 'Payment without a request id failed';
  end if;

  -- Another business cannot touch the invoice
  perform set_config('request.jwt.claim.sub', owners[2]::text, true);
  begin
    perform public.record_invoice_payment(invoice_a, 1, 'cash');
    raise exception 'Cross-business payment was accepted';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;
  begin
    perform public.save_invoice(invoice_a, header, items, true);
    raise exception 'Cross-business edit was accepted';
  exception when raise_exception then
    if sqlerrm <> 'Invoice not found' then raise; end if;
  end;

  -- No session cannot pay
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.record_invoice_payment(invoice_a, 1, 'cash');
    raise exception 'Unauthenticated payment was accepted';
  exception when invalid_authorization_specification then null;
  end;

  -- A repeated request records one payment, even once fully paid
  perform set_config('request.jwt.claim.sub', owners[1]::text, true);
  paid := public.record_invoice_payment(invoice_a, 118, 'upi', '2088-04-02', null, null, request_id);
  paid_again := public.record_invoice_payment(invoice_a, 118, 'upi', '2088-04-02', null, null, request_id);
  if paid.id <> paid_again.id then raise exception 'Retry recorded a second payment'; end if;
  select * into saved from public.invoices where id = invoice_a;
  if saved.paid_amount <> 118 or saved.balance_amount <> 0 or saved.status <> 'paid' then
    raise exception 'Retry changed balances: % % %', saved.paid_amount, saved.balance_amount, saved.status;
  end if;
  if paid.payment_date <> '2088-04-02' then raise exception 'Payment date was not kept'; end if;

  -- Editing a paid invoice keeps the server's paid amount
  saved := public.save_invoice(invoice_a, header || '{"total_amount":200}', items, true);
  if saved.paid_amount <> 118 or saved.balance_amount <> 82 or saved.status <> 'partial' then
    raise exception 'Edit miscalculated balance: % % %', saved.paid_amount, saved.balance_amount, saved.status;
  end if;

  -- Conversion is complete, linked and repeatable
  insert into public.quotations (id, user_id, quotation_number, customer_name, quotation_date, status, total_amount)
    values (quotation_a, owners[1], 'QA/Q/1', 'Regression fixture', '2088-04-01', 'sent', 118);
  insert into public.quotation_items (quotation_id, item_name, quantity, unit_price, taxable_amount, gst_rate, tax_amount, total_amount)
    values (quotation_a, 'Widget', 1, 100, 100, 18, 18, 118);
  saved := public.convert_quotation_to_invoice(quotation_a, '2088-04-03', 'QA');
  again := public.convert_quotation_to_invoice(quotation_a, '2088-04-03', 'QA');
  if saved.id <> again.id then raise exception 'Second conversion made another invoice'; end if;
  if saved.subtotal <> 100 or saved.tax_amount <> 18 or saved.total_amount <> 118 then
    raise exception 'Conversion totals are wrong';
  end if;
  select count(*) into n from public.invoice_items where invoice_id = saved.id;
  if n <> 1 then raise exception 'Conversion item count is %', n; end if;
  if (select status from public.quotations where id = quotation_a) <> 'accepted' then
    raise exception 'Quotation was not marked accepted';
  end if;

  perform set_config('request.jwt.claim.sub', owners[2]::text, true);
  begin
    perform public.convert_quotation_to_invoice(quotation_a, '2088-04-03', 'QA');
    raise exception 'Cross-business conversion was accepted';
  exception when raise_exception then
    if sqlerrm <> 'Quotation not found' then raise; end if;
  end;

  reset role;
end;
$$;
rollback;
select 'PASS: payment ownership, idempotent payments and creates, atomic rollback, conversion; all test writes rolled back' as result;
