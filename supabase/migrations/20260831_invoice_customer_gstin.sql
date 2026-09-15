-- Snapshot the buyer GSTIN on each invoice for statutory reporting. Keeping the
-- value on the invoice preserves filing history if the customer profile changes.

alter table public.invoices
  add column if not exists customer_gstin text not null default '';

create index if not exists invoices_customer_gstin_idx
  on public.invoices (customer_gstin)
  where customer_gstin <> '';
