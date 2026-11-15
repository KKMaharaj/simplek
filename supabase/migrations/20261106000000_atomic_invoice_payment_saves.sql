-- Close the payment authorisation hole and make multi-step document writes
-- atomic. Existing data is not modified. Apply BEFORE shipping the app version
-- that calls save_invoice and convert_quotation_to_invoice. Older app versions
-- keep working: new parameters have defaults and no table access is removed.
begin;

-- Payments ---------------------------------------------------------------
alter table public.payments add column if not exists client_request_id uuid;
create unique index if not exists payments_client_request_id_uidx
  on public.payments (client_request_id)
  where client_request_id is not null;

drop function if exists public.record_invoice_payment(uuid, numeric, text, date, text, text);

-- SECURITY DEFINER is needed because payments has no client-facing policies,
-- so ownership must be enforced here. A repeated client_request_id returns the
-- original payment instead of recording it twice.
create or replace function public.record_invoice_payment(
  p_invoice_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_payment_date date default current_date,
  p_reference_number text default null,
  p_notes text default null,
  p_client_request_id uuid default null
)
returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
  invoice_row public.invoices;
  payment_row public.payments;
  new_paid numeric(14, 2);
  new_balance numeric(14, 2);
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'Payment amount must be greater than zero';
  end if;
  if p_payment_method is null
     or p_payment_method not in ('cash', 'upi', 'bank_transfer', 'card', 'cheque') then
    raise exception 'Select a valid payment method';
  end if;

  -- Someone else's invoice is reported exactly like a missing one.
  select * into invoice_row from public.invoices
    where id = p_invoice_id and user_id = owner
    for update;
  if not found then raise exception 'Invoice not found'; end if;

  -- Checked before the balance: a retry of a payment that settled the invoice
  -- must return that payment, not fail with "exceeds outstanding balance".
  if p_client_request_id is not null then
    select * into payment_row from public.payments
      where client_request_id = p_client_request_id and invoice_id = p_invoice_id;
    if found then return payment_row; end if;
  end if;

  if invoice_row.status = 'cancelled' then
    raise exception 'Cancelled invoices cannot receive payments';
  end if;
  if p_amount > invoice_row.balance_amount then
    raise exception 'Payment cannot exceed outstanding balance';
  end if;

  new_paid := invoice_row.paid_amount + p_amount;
  new_balance := invoice_row.balance_amount - p_amount;
  update public.invoices
  set paid_amount = new_paid,
      balance_amount = new_balance,
      status = case when new_balance = 0 then 'paid' else 'partial' end
  where id = invoice_row.id;

  insert into public.payments (
    invoice_id, payment_date, amount, payment_method,
    reference_number, notes, client_request_id
  )
  values (
    p_invoice_id, coalesce(p_payment_date, current_date), p_amount, p_payment_method,
    p_reference_number, p_notes, p_client_request_id
  )
  returning * into payment_row;
  return payment_row;
end;
$$;

revoke all on function public.record_invoice_payment(uuid, numeric, text, date, text, text, uuid)
  from public, anon;
grant execute on function public.record_invoice_payment(uuid, numeric, text, date, text, text, uuid)
  to authenticated;

-- Invoices ---------------------------------------------------------------
-- Runs as the caller, so the existing row-level security policies still apply.
-- The whole call is one transaction: a failure leaves the header, the line
-- items and the number counter untouched. The client chooses p_invoice_id, so
-- retrying a create returns the saved invoice rather than making a second one.
create or replace function public.save_invoice(
  p_invoice_id uuid,
  p_header jsonb,
  p_items jsonb,
  p_is_edit boolean default false,
  p_number_prefix text default 'INV'
)
returns public.invoices
language plpgsql
security invoker
set search_path = public
as $$
declare
  owner uuid := auth.uid();
  is_edit boolean := p_is_edit;
  invoice_row public.invoices;
  invoice_date_value date := (p_header->>'invoice_date')::date;
  total numeric := coalesce((p_header->>'total_amount')::numeric, 0);
  requested_number text := nullif(upper(btrim(p_header->>'invoice_number')), '');
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_invoice_id is null then raise exception 'Invoice id is required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'An invoice needs at least one item';
  end if;

  -- Serialises concurrent retries of the same invoice.
  perform pg_advisory_xact_lock(hashtextextended(p_invoice_id::text, 0));

  select * into invoice_row from public.invoices
    where id = p_invoice_id and user_id = owner
    for update;

  if is_edit and not found then raise exception 'Invoice not found'; end if;
  if not is_edit and found then
    if exists (select 1 from public.invoice_items where invoice_id = p_invoice_id) then
      return invoice_row;
    end if;
    -- A header stranded without items by an older app version: complete it.
    is_edit := true;
  end if;

  if is_edit then
    update public.invoices set
      invoice_number = coalesce(requested_number, invoice_row.invoice_number),
      customer_name = p_header->>'customer_name',
      customer_gstin = coalesce(p_header->>'customer_gstin', ''),
      invoice_date = invoice_date_value,
      due_date = (p_header->>'due_date')::date,
      subtotal = coalesce((p_header->>'subtotal')::numeric, 0),
      tax_amount = coalesce((p_header->>'tax_amount')::numeric, 0),
      total_amount = total,
      -- Uses the locked paid amount, never a value the client read earlier.
      balance_amount = greatest(total - invoice_row.paid_amount, 0),
      status = case
        when invoice_row.status = 'cancelled' then 'cancelled'
        when invoice_row.paid_amount >= total then 'paid'
        when invoice_row.paid_amount > 0 then 'partial'
        else 'sent'
      end,
      terms = p_header->>'terms',
      place_of_supply = coalesce(p_header->>'place_of_supply', ''),
      tax_type = coalesce(p_header->>'tax_type', 'none'),
      cgst_amount = coalesce((p_header->>'cgst_amount')::numeric, 0),
      sgst_amount = coalesce((p_header->>'sgst_amount')::numeric, 0),
      igst_amount = coalesce((p_header->>'igst_amount')::numeric, 0)
    where id = p_invoice_id
    returning * into invoice_row;
    if not found then raise exception 'Invoice not found'; end if;
    delete from public.invoice_items where invoice_id = p_invoice_id;
  else
    insert into public.invoices (
      id, user_id, invoice_number, customer_name, customer_gstin, invoice_date,
      due_date, status, subtotal, tax_amount, total_amount, balance_amount,
      terms, place_of_supply, tax_type, cgst_amount, sgst_amount, igst_amount
    ) values (
      p_invoice_id,
      owner,
      coalesce(requested_number, public.next_invoice_number(p_number_prefix, invoice_date_value)),
      p_header->>'customer_name',
      coalesce(p_header->>'customer_gstin', ''),
      invoice_date_value,
      (p_header->>'due_date')::date,
      case when total <= 0 then 'paid' else 'sent' end,
      coalesce((p_header->>'subtotal')::numeric, 0),
      coalesce((p_header->>'tax_amount')::numeric, 0),
      total,
      total,
      p_header->>'terms',
      coalesce(p_header->>'place_of_supply', ''),
      coalesce(p_header->>'tax_type', 'none'),
      coalesce((p_header->>'cgst_amount')::numeric, 0),
      coalesce((p_header->>'sgst_amount')::numeric, 0),
      coalesce((p_header->>'igst_amount')::numeric, 0)
    )
    returning * into invoice_row;
  end if;

  insert into public.invoice_items (
    invoice_id, product_id, product_name, item_name, quantity, uqc_code,
    unit_price, taxable_amount, gst_rate, tax_amount,
    cgst_amount, sgst_amount, igst_amount, total_amount
  )
  select
    p_invoice_id, item.product_id, item.item_name, item.item_name, item.quantity, item.uqc_code,
    item.unit_price, item.taxable_amount, item.gst_rate, item.tax_amount,
    coalesce(item.cgst_amount, 0), coalesce(item.sgst_amount, 0),
    coalesce(item.igst_amount, 0), item.total_amount
  from jsonb_to_recordset(p_items) as item(
    product_id uuid, item_name text, quantity numeric, uqc_code text,
    unit_price numeric, taxable_amount numeric, gst_rate numeric, tax_amount numeric,
    cgst_amount numeric, sgst_amount numeric, igst_amount numeric, total_amount numeric
  );

  return invoice_row;
end;
$$;

revoke all on function public.save_invoice(uuid, jsonb, jsonb, boolean, text) from public, anon;
grant execute on function public.save_invoice(uuid, jsonb, jsonb, boolean, text) to authenticated;

-- Quotation conversion ---------------------------------------------------
-- Locking the quotation means a double tap or retry returns the same invoice.
create or replace function public.convert_quotation_to_invoice(
  p_quotation_id uuid,
  p_invoice_date date default current_date,
  p_number_prefix text default 'INV'
)
returns public.invoices
language plpgsql
security invoker
set search_path = public
as $$
declare
  owner uuid := auth.uid();
  quotation_row public.quotations;
  invoice_row public.invoices;
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select * into quotation_row from public.quotations
    where id = p_quotation_id and user_id = owner
    for update;
  if not found then raise exception 'Quotation not found'; end if;

  if quotation_row.converted_invoice_id is not null then
    select * into invoice_row from public.invoices
      where id = quotation_row.converted_invoice_id and user_id = owner;
    if found then return invoice_row; end if;
    raise exception 'The converted invoice no longer exists';
  end if;

  if not exists (select 1 from public.quotation_items where quotation_id = p_quotation_id) then
    raise exception 'Quotation has no items to convert';
  end if;

  insert into public.invoices (
    user_id, invoice_number, customer_name, invoice_date, status,
    subtotal, tax_amount, total_amount, balance_amount, terms, place_of_supply,
    tax_type, cgst_amount, sgst_amount, igst_amount
  )
  select
    owner,
    public.next_invoice_number(p_number_prefix, p_invoice_date),
    quotation_row.customer_name,
    p_invoice_date,
    'draft',
    coalesce(sum(item.taxable_amount), 0),
    coalesce(sum(item.tax_amount), 0),
    quotation_row.total_amount,
    quotation_row.total_amount,
    quotation_row.terms,
    quotation_row.place_of_supply,
    case when quotation_row.igst_amount > 0 then 'igst' else 'cgst_sgst' end,
    quotation_row.cgst_amount,
    quotation_row.sgst_amount,
    quotation_row.igst_amount
  from public.quotation_items item
  where item.quotation_id = p_quotation_id
  returning * into invoice_row;

  insert into public.invoice_items (
    invoice_id, product_id, product_name, item_name, quantity, uqc_code,
    unit_price, taxable_amount, gst_rate, tax_amount,
    cgst_amount, sgst_amount, igst_amount, total_amount
  )
  select
    invoice_row.id, product_id, item_name, item_name, quantity, uqc_code,
    unit_price, taxable_amount, gst_rate, tax_amount,
    cgst_amount, sgst_amount, igst_amount, total_amount
  from public.quotation_items
  where quotation_id = p_quotation_id;

  update public.quotations
  set status = 'accepted', converted_invoice_id = invoice_row.id
  where id = p_quotation_id;

  return invoice_row;
end;
$$;

revoke all on function public.convert_quotation_to_invoice(uuid, date, text) from public, anon;
grant execute on function public.convert_quotation_to_invoice(uuid, date, text) to authenticated;

notify pgrst, 'reload schema';
commit;
