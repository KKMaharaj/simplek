-- Preserve existing records and numbers. New businesses start at 01; existing
-- businesses continue after their highest number in that financial year.
begin;

alter table public.customers add column if not exists is_active boolean not null default true;

create or replace function public.document_financial_year(d date)
returns integer language sql immutable strict set search_path = public as $$
  select extract(year from d)::integer - case when extract(month from d) < 4 then 1 else 0 end;
$$;

-- Build the replacement protection BEFORE removing the old global protection.
create unique index if not exists invoices_business_year_number_uidx
  on public.invoices(user_id, public.document_financial_year(invoice_date), upper(btrim(invoice_number)));
create unique index if not exists quotations_business_year_number_uidx
  on public.quotations(user_id, public.document_financial_year(quotation_date), upper(btrim(quotation_number)));
alter table public.invoices drop constraint if exists invoices_invoice_number_key;
drop index if exists public.invoices_invoice_number_unique_idx;
alter table public.quotations drop constraint if exists quotations_quotation_number_key;

create table if not exists public.business_document_counters (
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null check (document_type in ('invoice','quotation')),
  financial_year integer not null,
  last_number bigint not null check (last_number > 0),
  primary key(user_id, document_type, financial_year)
);
alter table public.business_document_counters enable row level security;
revoke all on public.business_document_counters from public, anon, authenticated;

create or replace function public.allocate_business_document_number(kind text, prefix text, dated date)
returns text language plpgsql security definer set search_path = public as $$
declare
  owner uuid := auth.uid();
  fy integer := public.document_financial_year(dated);
  clean_prefix text := upper(btrim(prefix));
  highest numeric;
  allocated bigint;
begin
  if owner is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if fy is null or clean_prefix is null or clean_prefix !~ '^[A-Z0-9-]{1,20}$' then
    raise exception 'Invalid document date or prefix';
  end if;
  if kind = 'invoice' then
    select coalesce(max(substring(invoice_number from '([0-9]+)$')::numeric),0)
      into highest from public.invoices
      where user_id = owner and public.document_financial_year(invoice_date) = fy;
  elsif kind = 'quotation' then
    select coalesce(max(substring(quotation_number from '([0-9]+)$')::numeric),0)
      into highest from public.quotations
      where user_id = owner and public.document_financial_year(quotation_date) = fy;
  else raise exception 'Invalid document type';
  end if;
  if highest >= 9223372036854775806 then raise exception 'Document number range exceeded'; end if;
  insert into public.business_document_counters(user_id,document_type,financial_year,last_number)
    values(owner,kind,fy,highest::bigint+1)
    on conflict(user_id,document_type,financial_year) do update
      set last_number = greatest(business_document_counters.last_number+1, excluded.last_number)
    returning last_number into allocated;
  return clean_prefix || '/' || fy::text || '-' || right((fy+1)::text,2) || '/' ||
    case when allocated < 10 then '0' || allocated::text else allocated::text end;
end;
$$;
revoke all on function public.allocate_business_document_number(text,text,date) from public, anon, authenticated;

-- Keep all deployed RPC signatures compatible, but never use global counters.
create or replace function public.next_invoice_number(p_prefix text,p_invoice_date date,p_financial_year text)
returns text language sql security definer set search_path = public as $$
  select public.allocate_business_document_number('invoice',p_prefix,p_invoice_date);
$$;
create or replace function public.next_invoice_number(p_prefix text default 'INV',p_invoice_date date default current_date)
returns text language sql security definer set search_path = public as $$
  select public.allocate_business_document_number('invoice',p_prefix,p_invoice_date);
$$;
create or replace function public.next_quotation_number(p_prefix text,p_quotation_date date,p_financial_year text)
returns text language sql security definer set search_path = public as $$
  select public.allocate_business_document_number('quotation',p_prefix,p_quotation_date);
$$;
create or replace function public.next_quotation_number(p_quotation_date date default current_date)
returns text language sql security definer set search_path = public as $$
  select public.allocate_business_document_number('quotation','QTN',p_quotation_date);
$$;
revoke all on function public.next_invoice_number(text,date,text) from public, anon;
revoke all on function public.next_invoice_number(text,date) from public, anon;
revoke all on function public.next_quotation_number(text,date,text) from public, anon;
revoke all on function public.next_quotation_number(date) from public, anon;
grant execute on function public.next_invoice_number(text,date,text) to authenticated;
grant execute on function public.next_invoice_number(text,date) to authenticated;
grant execute on function public.next_quotation_number(text,date,text) to authenticated;
grant execute on function public.next_quotation_number(date) to authenticated;

notify pgrst, 'reload schema';
commit;
