-- CR-25B B1 (25 Nov 2026): invoices can be deleted, as a soft delete with
-- Undo, and every delete, restore and edit is written to an audit log.
--
-- * invoices.deleted_at / deleted_by mark a deleted invoice. The row, its
--   items and its payments stay in the database.
-- * A restrictive SELECT policy hides deleted invoices from everyone, so
--   every list, total, report, export and outstanding balance leaves them
--   out without each query having to remember. Their items go with them,
--   because the items' policy reads through invoices. Payments are not
--   readable by the app at all (no policy), only through functions.
-- * delete_invoice / restore_invoice are the only way to set or clear
--   deleted_at. They check that the caller owns the invoice, so an
--   accountant viewing the business cannot delete.
-- * The hard-delete policy on invoices is dropped: nothing in the app uses
--   it, and the standard says never to delete history.
-- * Numbers are never reused: allocate_business_document_number is security
--   definer, so it still sees deleted invoices when it finds the highest
--   number, and the per-year counter only goes up.
-- * audit_log keeps who, what, when and the old values as JSON. It has RLS
--   and no policies, so the app can't read or change it; only the security
--   definer function audit_invoice writes to it, from the database's own
--   copy of the invoice (never values sent by the app).
begin;

alter table public.invoices add column if not exists deleted_at timestamptz;
alter table public.invoices add column if not exists deleted_by uuid;

create index if not exists invoices_live_by_user_date_idx
  on public.invoices (user_id, invoice_date desc)
  where deleted_at is null;

create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  business_id uuid not null,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id uuid,
  old_values jsonb,
  created_at timestamptz not null default now(),
  constraint audit_log_action_check
    check (action in ('edit', 'delete', 'restore'))
);
create index if not exists audit_log_business_idx
  on public.audit_log (business_id, created_at desc);
create index if not exists audit_log_entity_idx
  on public.audit_log (entity, entity_id);
alter table public.audit_log enable row level security;
revoke all on table public.audit_log from anon, authenticated;

drop policy if exists "Hide deleted invoices" on public.invoices;
create policy "Hide deleted invoices" on public.invoices
  as restrictive for select to authenticated
  using (deleted_at is null);

drop policy if exists "Users delete own invoices" on public.invoices;

-- Writes one audit entry for the caller's own invoice, with the database's
-- copy of the invoice, its items and its payments as the old values.
create or replace function public.audit_invoice(p_invoice_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if p_action not in ('edit', 'delete', 'restore') then
    raise exception 'Invalid audit action';
  end if;
  insert into public.audit_log (business_id, actor_id, action, entity, entity_id, old_values)
  select i.user_id, owner, p_action, 'invoice', i.id,
    jsonb_build_object(
      'invoice', to_jsonb(i),
      'items', coalesce((
        select jsonb_agg(to_jsonb(it) order by it.id)
        from public.invoice_items it where it.invoice_id = i.id), '[]'::jsonb),
      'payments', coalesce((
        select jsonb_agg(to_jsonb(p) order by p.created_at)
        from public.payments p where p.invoice_id = i.id), '[]'::jsonb)
    )
  from public.invoices i
  where i.id = p_invoice_id and i.user_id = owner;
end;
$$;

revoke all on function public.audit_invoice(uuid, text) from public, anon;
grant execute on function public.audit_invoice(uuid, text) to authenticated;

create or replace function public.delete_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  perform 1 from public.invoices
    where id = p_invoice_id and user_id = owner and deleted_at is null
    for update;
  -- Someone else's invoice (an accountant's view included) is reported
  -- exactly like a missing one.
  if not found then raise exception 'Invoice not found'; end if;
  perform public.audit_invoice(p_invoice_id, 'delete');
  update public.invoices
    set deleted_at = now(), deleted_by = owner
    where id = p_invoice_id;
end;
$$;

create or replace function public.restore_invoice(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid := auth.uid();
begin
  if owner is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  perform 1 from public.invoices
    where id = p_invoice_id and user_id = owner and deleted_at is not null
    for update;
  if not found then raise exception 'Invoice not found'; end if;
  perform public.audit_invoice(p_invoice_id, 'restore');
  update public.invoices
    set deleted_at = null, deleted_by = null
    where id = p_invoice_id;
end;
$$;

revoke all on function public.delete_invoice(uuid) from public, anon;
revoke all on function public.restore_invoice(uuid) from public, anon;
grant execute on function public.delete_invoice(uuid) to authenticated;
grant execute on function public.restore_invoice(uuid) to authenticated;

-- Payments: a deleted invoice can't receive one (it is reported as missing).
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

  -- Someone else's invoice, or a deleted one, is reported like a missing one.
  select * into invoice_row from public.invoices
    where id = p_invoice_id and user_id = owner and deleted_at is null
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

-- save_invoice: unchanged except that an edit first writes the invoice as it
-- was to the audit log. A deleted invoice can't be edited: the restrictive
-- policy hides it, so it is "Invoice not found".
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
    perform public.audit_invoice(p_invoice_id, 'edit');
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

notify pgrst, 'reload schema';
commit;
