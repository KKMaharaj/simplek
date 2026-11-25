-- CR-25 change 9: an optional short description (up to 300 characters) on
-- invoices and quotations, saved by save_invoice and copied when a quotation
-- becomes an invoice. Existing rows are not modified.
--
-- save_invoice gains p_description with a default, so app versions that
-- don't send it keep working. The old five-parameter version is dropped
-- first: two versions would make the API's choice of function ambiguous.
-- An edit that doesn't send a description keeps the saved one; '' clears it.
begin;

alter table public.invoices add column if not exists description text;
alter table public.quotations add column if not exists description text;

alter table public.invoices drop constraint if exists invoices_description_length;
alter table public.invoices add constraint invoices_description_length
  check (description is null or char_length(description) <= 300);
alter table public.quotations drop constraint if exists quotations_description_length;
alter table public.quotations add constraint quotations_description_length
  check (description is null or char_length(description) <= 300);

drop function if exists public.save_invoice(uuid, jsonb, jsonb, boolean, text);

create or replace function public.save_invoice(
  p_invoice_id uuid,
  p_header jsonb,
  p_items jsonb,
  p_is_edit boolean default false,
  p_number_prefix text default 'INV',
  p_description text default null
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
  new_description text := nullif(btrim(p_description), '');
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
      igst_amount = coalesce((p_header->>'igst_amount')::numeric, 0),
      description = case
        when p_description is null then invoice_row.description
        else new_description
      end
    where id = p_invoice_id
    returning * into invoice_row;
    if not found then raise exception 'Invoice not found'; end if;
    delete from public.invoice_items where invoice_id = p_invoice_id;
  else
    insert into public.invoices (
      id, user_id, invoice_number, customer_name, customer_gstin, invoice_date,
      due_date, status, subtotal, tax_amount, total_amount, balance_amount,
      terms, place_of_supply, tax_type, cgst_amount, sgst_amount, igst_amount,
      description
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
      coalesce((p_header->>'igst_amount')::numeric, 0),
      new_description
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

revoke all on function public.save_invoice(uuid, jsonb, jsonb, boolean, text, text) from public, anon;
grant execute on function public.save_invoice(uuid, jsonb, jsonb, boolean, text, text) to authenticated;

-- Quotation conversion: same as before, plus the description.
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
    tax_type, cgst_amount, sgst_amount, igst_amount, description
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
    quotation_row.igst_amount,
    quotation_row.description
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
