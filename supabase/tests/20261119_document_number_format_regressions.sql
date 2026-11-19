-- Run as database owner with at least one user in auth.users.
-- Every change is rolled back.
begin;
do $$
declare
  owner_id uuid;
  n text;
begin
  select id into owner_id from auth.users order by id limit 1;
  if owner_id is null then raise exception 'Need an existing user'; end if;

  -- Old 4-digit and new 2-digit numbers in the same financial year.
  insert into public.invoices (user_id, invoice_number, customer_name, invoice_date)
    values (owner_id, 'QAN/2091-92/0022', 'Number fixture', '2091-05-01'),
           (owner_id, 'QAN/2091-92/24', 'Number fixture', '2091-06-01');

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);

  -- Continues after the highest serial, reading 0022 and 24 as numbers.
  n := public.next_invoice_number('QAN', '2091-07-01');
  if n <> 'QAN/2091-92/25' then raise exception 'Expected QAN/2091-92/25, got %', n; end if;

  -- Quotations and invoices use the same format and their own sequences.
  n := public.next_quotation_number('QAQ', '2091-07-01', '');
  if n <> 'QAQ/2091-92/01' then raise exception 'Expected QAQ/2091-92/01, got %', n; end if;

  -- Two digits up to 99, then plain numbers with no extra zeros.
  reset role;
  insert into public.invoices (user_id, invoice_number, customer_name, invoice_date)
    values (owner_id, 'QAN/2092-93/98', 'Number fixture', '2092-05-01');
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  n := public.next_invoice_number('QAN', '2092-07-01');
  if n <> 'QAN/2092-93/99' then raise exception 'Expected QAN/2092-93/99, got %', n; end if;
  n := public.next_invoice_number('QAN', '2092-07-01');
  if n <> 'QAN/2092-93/100' then raise exception 'Expected QAN/2092-93/100, got %', n; end if;

  -- A new financial year starts again at 01.
  n := public.next_invoice_number('QAN', '2093-04-01');
  if n <> 'QAN/2093-94/01' then raise exception 'Expected QAN/2093-94/01, got %', n; end if;

  -- 31 March and 1 April fall in different years.
  n := public.next_invoice_number('QAM', '2095-03-31');
  if n <> 'QAM/2094-95/01' then raise exception 'March boundary: got %', n; end if;
  n := public.next_invoice_number('QAM', '2095-04-01');
  if n <> 'QAM/2095-96/01' then raise exception 'April boundary: got %', n; end if;
  reset role;
end;
$$;
rollback;
select 'PASS: 2-digit serials, 0022 and 22 treated alike, 100 after 99, financial-year boundaries; all test writes rolled back' as result;
