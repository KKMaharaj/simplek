-- CR-25B B2 (25 Nov 2026): server totals over all the data. Builds a
-- 650-invoice business inside this transaction, then checks every total
-- against a direct SQL sum, that drafts, cancelled and deleted invoices are
-- left out, that another login sees none of it, and that a deep page and a
-- search stay quick. Run as database owner with at least one user in
-- auth.users. Everything is rolled back.
begin;
do $$
declare
  owner_id uuid;
  stranger uuid := gen_random_uuid();
  totals jsonb;
  summary jsonb;
  expected record;
  n integer;
  started timestamptz;
  page_ids uuid[];
  found_id uuid;
  target_number text;
begin
  select id into owner_id from auth.users order by id limit 1;
  if owner_id is null then raise exception 'Need an existing user'; end if;

  -- 650 counted invoices in 2095 (mixed GST, customers, payments), plus a
  -- draft, a cancelled and a deleted one that must not count.
  insert into public.invoices (user_id, invoice_number, customer_name, customer_gstin,
      invoice_date, status, subtotal, tax_amount, cgst_amount, sgst_amount, igst_amount,
      total_amount, paid_amount, balance_amount, tax_type, place_of_supply)
  select owner_id, 'QB2/2095-96/' || g, 'B2 customer ' || (g % 37),
      case when g % 3 = 0 then '29AAGCB7383J1Z4' else '' end,
      date '2095-04-01' + (g % 300),
      case when g % 5 = 0 then 'paid' when g % 5 = 1 then 'partial' else 'sent' end,
      100 + g, round((100 + g) * 0.18, 2),
      case when g % 2 = 0 then round((100 + g) * 0.09, 2) else 0 end,
      case when g % 2 = 0 then round((100 + g) * 0.18, 2) - round((100 + g) * 0.09, 2) else 0 end,
      case when g % 2 = 1 then round((100 + g) * 0.18, 2) else 0 end,
      round((100 + g) * 1.18, 0),
      case when g % 5 = 0 then round((100 + g) * 1.18, 0) when g % 5 = 1 then 50 else 0 end,
      case when g % 5 = 0 then 0 when g % 5 = 1 then round((100 + g) * 1.18, 0) - 50
           else round((100 + g) * 1.18, 0) end,
      case when g % 2 = 0 then 'cgst_sgst' else 'igst' end,
      'Karnataka'
  from generate_series(1, 650) g;
  insert into public.invoice_items (invoice_id, product_name, item_name, quantity,
      unit_price, taxable_amount, gst_rate, tax_amount, total_amount)
  select id, 'B2 item ' || (row_number() over (order by id) % 7),
      'B2 item ' || (row_number() over (order by id) % 7), 1,
      subtotal, subtotal, 18, tax_amount, subtotal + tax_amount
  from public.invoices where user_id = owner_id and invoice_number like 'QB2/%';
  insert into public.invoices (user_id, invoice_number, customer_name, invoice_date,
      status, subtotal, total_amount, balance_amount, deleted_at)
  values
    (owner_id, 'QB2/X/1', 'B2 draft', '2095-05-01', 'draft', 999, 999, 999, null),
    (owner_id, 'QB2/X/2', 'B2 cancelled', '2095-05-01', 'cancelled', 999, 999, 999, null),
    (owner_id, 'QB2/X/3', 'B2 deleted', '2095-05-01', 'sent', 999, 999, 999, now());

  select sum(total_amount) as sales, sum(paid_amount) as collected,
         sum(balance_amount) as due, count(*) as cnt,
         count(*) filter (where balance_amount > 0) as unpaid,
         count(*) filter (where status = 'partial') as partial,
         sum(subtotal) as taxable, sum(cgst_amount) as cgst, sum(sgst_amount) as sgst,
         sum(igst_amount) as igst,
         count(*) filter (where customer_gstin <> '') as b2b
    into expected
    from public.invoices
   where user_id = owner_id and invoice_number like 'QB2/2095-96/%';

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', owner_id::text, true);

  totals := public.dashboard_totals('2095-01-01', '2096-12-31');
  if (totals->>'total_sales')::numeric <> expected.sales
     or (totals->>'collected')::numeric <> expected.collected
     or (totals->>'to_collect')::numeric <> expected.due
     or (totals->>'invoice_count')::int <> expected.cnt
     or (totals->>'unpaid_count')::int <> expected.unpaid
     or (totals->>'partly_paid_count')::int <> expected.partial then
    raise exception 'Home totals % differ from SQL sums %', totals, row_to_json(expected);
  end if;
  if expected.cnt <> 650 then raise exception 'Fixture has % invoices', expected.cnt; end if;

  -- One customer's history.
  totals := public.dashboard_totals('2095-01-01', '2096-12-31', 'B2 customer 5');
  select count(*) into n from public.invoices
    where user_id = owner_id and invoice_number like 'QB2/2095-96/%'
      and customer_name = 'B2 customer 5';
  if (totals->>'invoice_count')::int <> n then
    raise exception 'Customer totals count % <> %', totals->>'invoice_count', n;
  end if;

  summary := public.report_summary('2095-01-01', '2096-12-31');
  if (summary->>'sales')::numeric <> expected.sales
     or (summary->>'taxable')::numeric <> expected.taxable
     or (summary->>'cgst')::numeric <> expected.cgst
     or (summary->>'sgst')::numeric <> expected.sgst
     or (summary->>'igst')::numeric <> expected.igst
     or (summary->>'b2b_count')::int <> expected.b2b
     or (summary->>'b2b_count')::int + (summary->>'b2c_count')::int <> 650
     or jsonb_array_length(summary->'weeks') <> 4 then
    raise exception 'Report summary % differs from SQL sums %', summary, row_to_json(expected);
  end if;

  select count(*) into n from public.report_customers('2095-01-01', '2096-12-31');
  if n <> 37 then raise exception 'Expected 37 customers, got %', n; end if;
  if (select sum(sales) from public.report_customers('2095-01-01', '2096-12-31')) <> expected.sales then
    raise exception 'Customer-wise sales do not add up to the total';
  end if;
  if (select sum(taxable) from public.report_items('2095-01-01', '2096-12-31')) <> expected.taxable then
    raise exception 'Item-wise taxable value does not add up';
  end if;
  select count(*) into n from public.report_gstr1_issues('2095-01-01', '2096-12-31');
  if n <> 0 then raise exception 'Expected no GSTR-1 issues, got %', n; end if;
  if (select sum(due) from public.customer_balances(array['B2 customer 1', 'B2 customer 2']))
     <> (select sum(balance_amount) from public.invoices
          where user_id = owner_id and invoice_number like 'QB2/2095-96/%'
            and customer_name in ('B2 customer 1', 'B2 customer 2')) then
    raise exception 'Customer balances are wrong';
  end if;

  -- Page 13 of 25 (rows 301–325) and a search for an invoice from page 20,
  -- the way the app asks for them, stay quick.
  started := clock_timestamp();
  select array_agg(id) into page_ids from (
    select id from public.invoices
    where invoice_number like 'QB2/2095-96/%'
    order by invoice_date desc, invoice_number desc
    offset 300 limit 25) p;
  if cardinality(page_ids) <> 25 then raise exception 'Page 13 has % rows', cardinality(page_ids); end if;
  select invoice_number into target_number from public.invoices
    where invoice_number like 'QB2/2095-96/%'
    order by invoice_date desc, invoice_number desc offset 480 limit 1;
  select id into found_id from public.invoices
    where invoice_number ilike '%' || target_number || '%' limit 1;
  if found_id is null then raise exception 'Search did not find %', target_number; end if;
  if clock_timestamp() - started > interval '2 seconds' then
    raise exception 'Page 13 and the search took %', clock_timestamp() - started;
  end if;

  -- Another login sees nothing; without a login nothing at all.
  perform set_config('request.jwt.claim.sub', stranger::text, true);
  totals := public.dashboard_totals('2095-01-01', '2096-12-31');
  if (totals->>'invoice_count')::int <> 0 then
    raise exception 'A stranger saw % invoices', totals->>'invoice_count';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  totals := public.dashboard_totals();
  if (totals->>'invoice_count')::int <> 0 then raise exception 'No login saw invoices'; end if;

  reset role;
  if has_function_privilege('anon', 'public.dashboard_totals(date,date,text)', 'execute')
     or has_function_privilege('authenticated', 'public.counted_invoices(date,date)', 'execute') then
    raise exception 'Totals functions are exposed too widely';
  end if;

  raise notice 'CR-25B B2 regressions passed';
end;
$$;
select 'B2 regressions reached the end' as result;
rollback;
