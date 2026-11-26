-- CR-25B B2 (25 Nov 2026): totals, reports and lists use all the data.
--
-- Every total the app shows is worked out here, over all matching invoices,
-- instead of adding up the rows the app happened to load (Home used the
-- newest 100, Reports the newest 500). The app only displays the results.
--
-- All functions are security definer, read the business being viewed
-- (viewing_business(): the caller's own, or one shared with an accountant)
-- and return nothing without a login. They leave out deleted invoices (B1),
-- drafts and cancelled invoices.
--
-- Indexes support the server-side pages, search and filters the lists now
-- use (PostgREST range + count), so page 13 or a search over 600+ invoices
-- stays quick.
begin;

-- Already installed on the live project (in public); unqualified names
-- below resolve through the search path wherever it lives.
create extension if not exists pg_trgm;

-- Lists: newest first per business, and search by number, customer, GSTIN.
create index if not exists invoices_live_by_user_number_idx
  on public.invoices (user_id, invoice_number)
  where deleted_at is null;
create index if not exists invoices_customer_name_trgm_idx
  on public.invoices using gin (customer_name gin_trgm_ops);
create index if not exists invoices_number_trgm_idx
  on public.invoices using gin (invoice_number gin_trgm_ops);
create index if not exists quotations_by_user_date_idx
  on public.quotations (user_id, quotation_date desc);
create index if not exists customers_by_user_name_idx
  on public.customers (user_id, name);
create index if not exists products_by_user_name_idx
  on public.products (user_id, name);
create index if not exists invoice_items_invoice_idx
  on public.invoice_items (invoice_id);

-- The invoices every total counts: the viewed business's, not deleted, not
-- a draft, not cancelled, within the dates (either end may be open).
create or replace function public.counted_invoices(p_from date, p_to date)
returns setof public.invoices
language sql
stable
security definer
set search_path = public
as $$
  select i.*
  from public.invoices i
  where auth.uid() is not null
    and i.user_id = public.viewing_business()
    and i.deleted_at is null
    and i.status not in ('draft', 'cancelled')
    and (p_from is null or i.invoice_date >= p_from)
    and (p_to is null or i.invoice_date <= p_to);
$$;
revoke all on function public.counted_invoices(date, date) from public, anon, authenticated;

-- Home, the invoice list's tiles and a customer's history.
create or replace function public.dashboard_totals(
  p_from date default null,
  p_to date default null,
  p_customer text default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'total_sales', coalesce(sum(total_amount), 0),
    'collected', coalesce(sum(paid_amount), 0),
    'to_collect', coalesce(sum(balance_amount), 0),
    'invoice_count', count(*),
    'unpaid_count', count(*) filter (where balance_amount > 0),
    'partly_paid_count', count(*) filter (where status = 'partial'),
    'paid_count', count(*) filter (where status = 'paid')
  )
  from public.counted_invoices(p_from, p_to)
  where p_customer is null or customer_name = p_customer;
$$;

-- Reports: the tiles, payment status, GSTR-1 summary, B2B/B2C counts and the
-- four-week sales chart (weeks ending on the latest invoice date counted).
create or replace function public.report_summary(
  p_from date default null,
  p_to date default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with counted as (select * from public.counted_invoices(p_from, p_to)),
  latest as (select max(invoice_date) as day from counted),
  weeks as (
    select w, l.day - (w * 7 + 6) as starts, l.day - (w * 7) as ends
    from latest l, generate_series(3, 0, -1) as w
    where l.day is not null
  )
  select jsonb_build_object(
    'sales', coalesce(sum(total_amount), 0),
    'collected', coalesce(sum(paid_amount), 0),
    'outstanding', coalesce(sum(balance_amount), 0),
    'invoice_count', count(*),
    'paid_count', count(*) filter (where status = 'paid'),
    'pending_count', count(*) filter (where status in ('sent', 'partial', 'overdue')),
    'taxable', coalesce(sum(subtotal), 0),
    'cgst', coalesce(sum(cgst_amount), 0),
    'sgst', coalesce(sum(sgst_amount), 0),
    'igst', coalesce(sum(igst_amount), 0),
    'tax', coalesce(sum(tax_amount), 0),
    'b2b_count', count(*) filter (where btrim(customer_gstin) <> ''),
    'b2b_total', coalesce(sum(total_amount) filter (where btrim(customer_gstin) <> ''), 0),
    'b2c_count', count(*) filter (where btrim(customer_gstin) = ''),
    'b2c_total', coalesce(sum(total_amount) filter (where btrim(customer_gstin) = ''), 0),
    'weeks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', wk.starts,
        'end', wk.ends,
        'sales', coalesce((select sum(c.total_amount) from counted c
                           where c.invoice_date between wk.starts and wk.ends), 0)
      ) order by wk.w desc)
      from weeks wk), '[]'::jsonb)
  )
  from counted;
$$;

-- Customer-wise report, biggest sales first.
create or replace function public.report_customers(
  p_from date default null,
  p_to date default null
)
returns table (
  customer text,
  invoice_count bigint,
  sales numeric,
  tax numeric,
  outstanding numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(customer_name), ''), 'Unnamed customer'),
         count(*), sum(total_amount), sum(tax_amount), sum(balance_amount)
  from public.counted_invoices(p_from, p_to)
  group by 1
  order by 3 desc, 1;
$$;

-- Item-wise report, biggest sales first.
create or replace function public.report_items(
  p_from date default null,
  p_to date default null
)
returns table (
  item text,
  quantity numeric,
  taxable numeric,
  tax numeric,
  sales numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(nullif(btrim(it.item_name), ''), 'Unnamed item'),
         sum(it.quantity), sum(coalesce(it.taxable_amount, 0)),
         sum(coalesce(it.tax_amount, 0)), sum(coalesce(it.total_amount, 0))
  from public.counted_invoices(p_from, p_to) i
  join public.invoice_items it on it.invoice_id = i.id
  group by 1
  order by 5 desc, 1;
$$;

-- GSTR-1 checks: every counted invoice with something to fix.
create or replace function public.report_gstr1_issues(
  p_from date default null,
  p_to date default null
)
returns table (
  id uuid,
  invoice_number text,
  invoice_date date,
  customer_name text,
  total_amount numeric,
  issues text[]
)
language sql
stable
security definer
set search_path = public
as $$
  select * from (
    select i.id, i.invoice_number, i.invoice_date, i.customer_name, i.total_amount,
      array_remove(array[
        case when btrim(coalesce(i.invoice_number, '')) = '' then 'Missing invoice number' end,
        case when btrim(i.customer_gstin) <> ''
              and upper(btrim(i.customer_gstin)) !~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$'
             then 'Invalid customer GSTIN' end,
        case when i.tax_amount > 0 and btrim(i.place_of_supply) = ''
             then 'Missing place of supply' end,
        case when abs(i.tax_amount - (i.cgst_amount + i.sgst_amount + i.igst_amount)) > 0.02
             then 'GST components do not match total tax' end,
        case when i.igst_amount > 0 and (i.cgst_amount > 0 or i.sgst_amount > 0)
             then 'Invoice mixes IGST and CGST/SGST' end,
        case when abs(i.cgst_amount - i.sgst_amount) > 0.02 and i.igst_amount = 0
             then 'CGST and SGST are not equal' end
      ], null) as issues
    from public.counted_invoices(p_from, p_to) i
  ) checked
  where cardinality(issues) > 0
  order by invoice_date desc, invoice_number;
$$;

-- What each named customer still owes, for the customers on a list page.
-- Names match ignoring case and outer spaces (invoices store the name as
-- typed); the result names are lower-case.
create or replace function public.customer_balances(p_names text[])
returns table (customer_name text, due numeric)
language sql
stable
security definer
set search_path = public
as $
  select lower(btrim(i.customer_name)), sum(i.balance_amount)
  from public.counted_invoices(null, null) i
  where lower(btrim(i.customer_name)) = any(
    select lower(btrim(n)) from unnest(p_names) as n)
  group by 1;
$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'dashboard_totals(date,date,text)',
    'report_summary(date,date)',
    'report_customers(date,date)',
    'report_items(date,date)',
    'report_gstr1_issues(date,date)',
    'customer_balances(text[])'
  ] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
