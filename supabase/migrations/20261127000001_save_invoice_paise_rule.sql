-- CR-25B B3 (25 Nov 2026): save_invoice repeats the app's money maths and
-- rejects a mismatch. The rule is written in lib/money.dart and NOTES.md:
--
--   line taxable = round(quantity × rate, 2)
--   line tax     = round(taxable × GST % ÷ 100, 2)
--   within the state: CGST = round(tax ÷ 2, 2), SGST = tax − CGST;
--   otherwise IGST = tax
--   line total   = taxable + tax
--   invoice subtotal, tax, CGST, SGST, IGST = sums of the lines
--   total payable = round(subtotal + tax, 0)   (half-up, decided 19 Nov)
--
-- Postgres round() on numeric rounds half away from zero, the same as the
-- app. Quantity, rate and GST % are first rounded to the places the columns
-- store (3, 2 and 2).
--
-- The app sends header.money_rule = 'paise-v1'. Then every amount it sends
-- must equal the server's, or the save is refused. Older app versions (the
-- 1.4.0 web app and phones not yet updated) don't send it: their amounts are
-- replaced by the server's, so the database always follows the rule and
-- those versions keep working. Invoices already saved keep their amounts.
-- Everything else is as in 20261127000000 (audit of edits included).
begin;

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
  requested_number text := nullif(upper(btrim(p_header->>'invoice_number')), '');
  new_description text := nullif(btrim(p_description), '');
  strict_rule boolean := coalesce(p_header->>'money_rule', '') = 'paise-v1';
  tax_type_value text := coalesce(nullif(p_header->>'tax_type', ''), 'none');
  intra boolean;
  lines jsonb;
  mismatched_line int;
  s_subtotal numeric;
  s_tax numeric;
  s_cgst numeric;
  s_sgst numeric;
  s_igst numeric;
  total numeric;
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_invoice_id is null then raise exception 'Invoice id is required'; end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'An invoice needs at least one item';
  end if;
  if tax_type_value not in ('none', 'cgst_sgst', 'igst') then
    raise exception 'Invalid tax type';
  end if;
  intra := tax_type_value <> 'igst';

  -- The server's own amounts for every line, in the order sent.
  with sent as (
    select ord, item,
      round(coalesce((item->>'quantity')::numeric, 0), 3) as quantity,
      round(coalesce((item->>'unit_price')::numeric, 0), 2) as unit_price,
      round(coalesce((item->>'gst_rate')::numeric, 0), 2) as gst_rate
    from jsonb_array_elements(p_items) with ordinality as e(item, ord)
  ), taxable as (
    select *, round(quantity * unit_price, 2) as taxable_amount from sent
  ), taxed as (
    select *, round(taxable_amount * gst_rate / 100, 2) as tax_amount from taxable
  )
  select jsonb_agg(
           item || jsonb_build_object(
             'quantity', quantity,
             'unit_price', unit_price,
             'gst_rate', gst_rate,
             'taxable_amount', taxable_amount,
             'tax_amount', tax_amount,
             'cgst_amount', case when intra then round(tax_amount / 2, 2) else 0 end,
             'sgst_amount', case when intra then tax_amount - round(tax_amount / 2, 2) else 0 end,
             'igst_amount', case when intra then 0 else tax_amount end,
             'total_amount', taxable_amount + tax_amount,
             '_ord', ord
           ) order by ord),
         min(ord) filter (where strict_rule and (
           (item->>'taxable_amount')::numeric is distinct from taxable_amount
           or (item->>'tax_amount')::numeric is distinct from tax_amount
           or coalesce((item->>'cgst_amount')::numeric, 0)
                is distinct from case when intra then round(tax_amount / 2, 2) else 0 end
           or coalesce((item->>'sgst_amount')::numeric, 0)
                is distinct from case when intra then tax_amount - round(tax_amount / 2, 2) else 0 end
           or coalesce((item->>'igst_amount')::numeric, 0)
                is distinct from case when intra then 0 else tax_amount end
           or (item->>'total_amount')::numeric is distinct from taxable_amount + tax_amount
         ))
    into lines, mismatched_line
    from taxed;

  select sum((l->>'taxable_amount')::numeric), sum((l->>'tax_amount')::numeric),
         sum((l->>'cgst_amount')::numeric), sum((l->>'sgst_amount')::numeric),
         sum((l->>'igst_amount')::numeric)
    into s_subtotal, s_tax, s_cgst, s_sgst, s_igst
    from jsonb_array_elements(lines) as l;
  total := round(s_subtotal + s_tax, 0);

  if strict_rule then
    if mismatched_line is not null then
      raise exception 'The amounts on line % do not match the server''s calculation. Update the app and try again.', mismatched_line
        using errcode = '22000';
    end if;
    if (p_header->>'subtotal')::numeric is distinct from s_subtotal
       or (p_header->>'tax_amount')::numeric is distinct from s_tax
       or coalesce((p_header->>'cgst_amount')::numeric, 0) is distinct from s_cgst
       or coalesce((p_header->>'sgst_amount')::numeric, 0) is distinct from s_sgst
       or coalesce((p_header->>'igst_amount')::numeric, 0) is distinct from s_igst
       or (p_header->>'total_amount')::numeric is distinct from total then
      raise exception 'The invoice totals do not match the server''s calculation. Update the app and try again.'
        using errcode = '22000';
    end if;
    if (tax_type_value = 'none') <> (s_tax = 0) then
      raise exception 'The tax type does not match the items. Update the app and try again.'
        using errcode = '22000';
    end if;
  elsif s_tax = 0 then
    tax_type_value := 'none';
  elsif tax_type_value = 'none' then
    -- An older app with tax but no tax type: the lines were already split
    -- as within the state ('none' is not 'igst'), so say so.
    tax_type_value := 'cgst_sgst';
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
    perform public.audit_invoice(p_invoice_id, 'edit');
    update public.invoices set
      invoice_number = coalesce(requested_number, invoice_row.invoice_number),
      customer_name = p_header->>'customer_name',
      customer_gstin = coalesce(p_header->>'customer_gstin', ''),
      invoice_date = invoice_date_value,
      due_date = (p_header->>'due_date')::date,
      subtotal = s_subtotal,
      tax_amount = s_tax,
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
      tax_type = tax_type_value,
      cgst_amount = s_cgst,
      sgst_amount = s_sgst,
      igst_amount = s_igst,
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
      s_subtotal,
      s_tax,
      total,
      total,
      p_header->>'terms',
      coalesce(p_header->>'place_of_supply', ''),
      tax_type_value,
      s_cgst,
      s_sgst,
      s_igst,
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
    item.cgst_amount, item.sgst_amount, item.igst_amount, item.total_amount
  from jsonb_to_recordset(lines) as item(
    product_id uuid, item_name text, quantity numeric, uqc_code text,
    unit_price numeric, taxable_amount numeric, gst_rate numeric, tax_amount numeric,
    cgst_amount numeric, sgst_amount numeric, igst_amount numeric, total_amount numeric,
    _ord int
  )
  order by item._ord;

  return invoice_row;
end;
$$;

notify pgrst, 'reload schema';
commit;
