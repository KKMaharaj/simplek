-- Payment ledger and atomic invoice-balance update.

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  payment_date date not null default current_date,
  amount numeric(14, 2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('cash', 'upi', 'bank_transfer', 'card', 'cheque')),
  reference_number text,
  notes text
);

create index if not exists payments_invoice_date_idx
  on public.payments (invoice_id, payment_date desc);

create or replace function public.record_invoice_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_payment_date date default current_date,
  p_reference_number text default null,
  p_notes text default null
)
returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  invoice_row public.invoices;
  payment_row public.payments;
  new_paid numeric(14, 2);
  new_balance numeric(14, 2);
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;
  if p_payment_method not in ('cash', 'upi', 'bank_transfer', 'card', 'cheque') then
    raise exception 'Select a valid payment method';
  end if;

  select * into invoice_row from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if invoice_row.status = 'cancelled' then raise exception 'Cancelled invoices cannot receive payments'; end if;
  if p_amount > invoice_row.balance_amount then raise exception 'Payment cannot exceed outstanding balance'; end if;

  new_paid := invoice_row.paid_amount + p_amount;
  new_balance := invoice_row.balance_amount - p_amount;
  update public.invoices
  set paid_amount = new_paid,
      balance_amount = new_balance,
      status = case when new_balance = 0 then 'paid' else 'partial' end
  where id = invoice_row.id;

  insert into public.payments (invoice_id, payment_date, amount, payment_method, reference_number, notes)
  values (p_invoice_id, coalesce(p_payment_date, current_date), p_amount, p_payment_method, p_reference_number, p_notes)
  returning * into payment_row;
  return payment_row;
end;
$$;

alter table public.payments enable row level security;
grant execute on function public.record_invoice_payment(uuid, numeric, text, date, text, text) to anon, authenticated;
