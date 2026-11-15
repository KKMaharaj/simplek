-- Invoice headers and line items for Simplek.
-- Customer names are stored directly on an invoice so an invoice does not
-- require a customer record.  No created_at or updated_at columns are used.

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  customer_name text not null,
  invoice_date date not null default current_date,
  due_date date,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'paid', 'partial', 'overdue', 'cancelled')),
  subtotal numeric(14, 2) not null default 0 check (subtotal >= 0),
  tax_amount numeric(14, 2) not null default 0 check (tax_amount >= 0),
  discount_amount numeric(14, 2) not null default 0 check (discount_amount >= 0),
  total_amount numeric(14, 2) not null default 0 check (total_amount >= 0),
  paid_amount numeric(14, 2) not null default 0 check (paid_amount >= 0),
  balance_amount numeric(14, 2) not null default 0 check (balance_amount >= 0),
  notes text,
  terms text
);

create index if not exists invoices_customer_name_idx
  on public.invoices (customer_name);

create index if not exists invoices_invoice_date_idx
  on public.invoices (invoice_date desc);

alter table public.invoice_items
  add column if not exists invoice_id uuid references public.invoices(id) on delete cascade,
  add column if not exists item_name text,
  add column if not exists discount_amount numeric(14, 2) not null default 0;

create index if not exists invoice_items_invoice_id_idx
  on public.invoice_items (invoice_id);
