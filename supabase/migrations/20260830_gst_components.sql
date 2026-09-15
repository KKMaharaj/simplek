alter table public.invoices
  add column if not exists place_of_supply text not null default '',
  add column if not exists tax_type text not null default 'none' check (tax_type in ('none','cgst_sgst','igst')),
  add column if not exists cgst_amount numeric(14,2) not null default 0,
  add column if not exists sgst_amount numeric(14,2) not null default 0,
  add column if not exists igst_amount numeric(14,2) not null default 0;
alter table public.invoice_items
  add column if not exists cgst_amount numeric(14,2) not null default 0,
  add column if not exists sgst_amount numeric(14,2) not null default 0,
  add column if not exists igst_amount numeric(14,2) not null default 0;
alter table public.quotations
  add column if not exists place_of_supply text not null default '',
  add column if not exists tax_type text not null default 'none' check (tax_type in ('none','cgst_sgst','igst')),
  add column if not exists cgst_amount numeric(14,2) not null default 0,
  add column if not exists sgst_amount numeric(14,2) not null default 0,
  add column if not exists igst_amount numeric(14,2) not null default 0;
alter table public.quotation_items
  add column if not exists cgst_amount numeric(14,2) not null default 0,
  add column if not exists sgst_amount numeric(14,2) not null default 0,
  add column if not exists igst_amount numeric(14,2) not null default 0;
