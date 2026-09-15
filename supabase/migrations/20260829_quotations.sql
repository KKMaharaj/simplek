-- Quotations and quotation line items for the current single-business app.
-- This migration intentionally does not enable RLS on quotations because the
-- app currently has no Supabase Auth/user ownership model. Add per-business
-- RLS policies when authentication is introduced.

create table if not exists public.quotation_number_sequences (
  sequence_key text primary key check (sequence_key = 'quotation'),
  next_number bigint not null default 1 check (next_number > 0)
);

insert into public.quotation_number_sequences (sequence_key, next_number)
values ('quotation', 1)
on conflict (sequence_key) do nothing;

create table if not exists public.quotations (
  id uuid primary key default gen_random_uuid(),
  quotation_number text not null unique,
  customer_name text not null,
  quotation_date date not null default current_date,
  valid_until date,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'accepted', 'rejected', 'expired')),
  subtotal numeric(14, 2) not null default 0 check (subtotal >= 0),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14, 2) not null default 0 check (total_amount >= 0),
  notes text,
  terms text,
  converted_invoice_id uuid references public.invoices(id),
  created_at timestamptz not null default now()
);

create index if not exists quotations_date_idx
  on public.quotations (quotation_date desc);

create index if not exists quotations_customer_idx
  on public.quotations (customer_name);

create table if not exists public.quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.quotations(id) on delete cascade,
  product_id uuid references public.products(id),
  item_name text not null,
  quantity numeric(14, 3) not null check (quantity > 0),
  uqc_code text references public.uqc_master(code),
  unit_price numeric(14, 2) not null check (unit_price >= 0),
  taxable_amount numeric(14, 2) not null default 0 check (taxable_amount >= 0),
  gst_rate numeric(5, 2) not null default 0 check (gst_rate >= 0 and gst_rate <= 100),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  total_amount numeric(14, 2) not null default 0 check (total_amount >= 0)
);

create index if not exists quotation_items_quotation_idx
  on public.quotation_items (quotation_id);

create or replace function public.next_quotation_number(
  p_quotation_date date default current_date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  allocated_number bigint;
  financial_year_start integer;
  financial_year_label text;
begin
  financial_year_start := case
    when extract(month from p_quotation_date) >= 4 then extract(year from p_quotation_date)::integer
    else extract(year from p_quotation_date)::integer - 1
  end;
  financial_year_label := format('%s-%s', financial_year_start, right((financial_year_start + 1)::text, 2));

  update public.quotation_number_sequences
  set next_number = next_number + 1
  where sequence_key = 'quotation'
  returning next_number - 1 into allocated_number;

  return format('QTN/%s/%s', financial_year_label, lpad(allocated_number::text, 4, '0'));
end;
$$;

alter table public.quotation_number_sequences enable row level security;
revoke all on table public.quotation_number_sequences from anon, authenticated;
grant execute on function public.next_quotation_number(date) to anon, authenticated;
