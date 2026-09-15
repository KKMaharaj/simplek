-- Bring a pre-existing payments table up to the fields used by the app.
-- Existing payment records are retained.

alter table public.payments
  add column if not exists invoice_id uuid references public.invoices(id) on delete cascade,
  add column if not exists payment_date date not null default current_date,
  add column if not exists amount numeric(14, 2),
  add column if not exists payment_method text,
  add column if not exists reference_number text,
  add column if not exists notes text;

create index if not exists payments_invoice_date_idx
  on public.payments (invoice_id, payment_date desc);
