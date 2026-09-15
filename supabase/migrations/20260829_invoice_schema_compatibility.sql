-- Bring pre-existing invoice tables up to the fields used by the billing app.
-- All additions are nullable or have defaults so existing records are retained.

alter table public.invoices
  add column if not exists invoice_number text,
  add column if not exists customer_name text,
  add column if not exists invoice_date date not null default current_date,
  add column if not exists due_date date,
  add column if not exists status text not null default 'draft',
  add column if not exists subtotal numeric(14, 2) not null default 0,
  add column if not exists tax_amount numeric(14, 2) not null default 0,
  add column if not exists discount_amount numeric(14, 2) not null default 0,
  add column if not exists total_amount numeric(14, 2) not null default 0,
  add column if not exists paid_amount numeric(14, 2) not null default 0,
  add column if not exists balance_amount numeric(14, 2) not null default 0,
  add column if not exists notes text,
  add column if not exists terms text;

create unique index if not exists invoices_invoice_number_unique_idx
  on public.invoices (invoice_number)
  where invoice_number is not null;

alter table public.invoice_items
  add column if not exists invoice_id uuid references public.invoices(id) on delete cascade,
  add column if not exists product_id uuid references public.products(id),
  add column if not exists item_name text,
  add column if not exists quantity numeric(14, 3),
  add column if not exists uqc_code text references public.uqc_master(code),
  add column if not exists unit_price numeric(14, 2),
  add column if not exists taxable_amount numeric(14, 2),
  add column if not exists gst_rate numeric(5, 2),
  add column if not exists tax_amount numeric(14, 2),
  add column if not exists total_amount numeric(14, 2),
  add column if not exists discount_amount numeric(14, 2) not null default 0;

create index if not exists invoice_items_invoice_id_idx
  on public.invoice_items (invoice_id);
