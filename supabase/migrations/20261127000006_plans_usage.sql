-- Change request 26 Nov 2026, super admin panel S4: plans, the free limit
-- and how invoices are counted.
--
-- * plans: Free (250 invoices, lifetime; the owner confirms total or per
--   month, one setting) and Unlimited (Rs 250 a month or Rs 1,500 a year).
-- * business_plans: the plan in effect is the latest row whose dates cover
--   today. Every existing business gets Free; a new business gets Free
--   automatically.
-- * Usage = every invoice the business ever created in the plan's period,
--   including soft-deleted (B1) and cancelled ones, not drafts: each invoice
--   number issued counts once, so deleting one gives nothing back. Counted
--   from the invoices table itself (security definer sees deleted rows).
-- * Enforcement: save_invoice and quotation conversion refuse a NEW invoice
--   at the limit (plus extra invoices granted) only while the platform
--   setting "enforce_plan_limits" is on (it starts off). Edits are always
--   allowed. A suspended account can't save.
begin;

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  price_monthly numeric(12,2) not null default 0,
  price_yearly numeric(12,2) not null default 0,
  invoice_limit integer check (invoice_limit is null or invoice_limit >= 0),
  limit_period text not null default 'none'
    check (limit_period in ('lifetime', 'monthly', 'none')),
  features jsonb not null default '{}'::jsonb,
  visible boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.plans enable row level security;
revoke all on table public.plans from anon, authenticated;

insert into public.plans (code, name, price_monthly, price_yearly, invoice_limit, limit_period, features)
values
  ('free', 'Free', 0, 0, 250, 'lifetime',
   '{"accountant_access": true, "tally_export": true}'),
  ('unlimited', 'Unlimited', 250, 1500, null, 'none',
   '{"accountant_access": true, "tally_export": true}')
on conflict (code) do nothing;

create table if not exists public.business_plans (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  plan_id uuid not null references public.plans (id),
  starts_on date not null default current_date,
  ends_on date,
  extra_invoices integer not null default 0 check (extra_invoices >= 0),
  reason text not null,
  changed_by uuid,
  changed_at timestamptz not null default clock_timestamp(),
  constraint business_plans_dates check (ends_on is null or ends_on >= starts_on)
);
create index if not exists business_plans_business_idx
  on public.business_plans (business_id, starts_on desc, changed_at desc);
alter table public.business_plans enable row level security;
revoke all on table public.business_plans from anon, authenticated;

-- Free for every existing business, from the day it was set up.
insert into public.business_plans (business_id, plan_id, starts_on, reason)
select p.user_id, (select id from public.plans where code = 'free'),
       p.created_at::date, 'Free plan for existing businesses (26 Nov 2026)'
from public.business_profiles p
where not exists (select 1 from public.business_plans b where b.business_id = p.user_id);

-- Free for every new business.
create or replace function public.free_plan_for_new_business()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.business_plans where business_id = new.user_id) then
    insert into public.business_plans (business_id, plan_id, starts_on, reason)
    values (new.user_id, (select id from public.plans where code = 'free'),
            current_date, 'New sign-up');
  end if;
  return new;
end;
$$;
drop trigger if exists free_plan_for_new_business on public.business_profiles;
create trigger free_plan_for_new_business after insert on public.business_profiles
  for each row execute function public.free_plan_for_new_business();

-- The plan in effect for a business, its limit and its usage.
create or replace function public.plan_usage(p_business uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with current_plan as (
    select bp.starts_on, bp.ends_on, bp.extra_invoices, pl.*
    from public.business_plans bp
    join public.plans pl on pl.id = bp.plan_id
    where bp.business_id = p_business
      and bp.starts_on <= current_date
      and (bp.ends_on is null or bp.ends_on >= current_date)
    order by bp.starts_on desc, bp.changed_at desc
    limit 1
  ), effective as (
    select * from current_plan
    union all
    select null::date, null::date, 0, pl.*
    from public.plans pl
    where pl.code = 'free' and not exists (select 1 from current_plan)
  ), used as (
    select count(*) as n
    from public.invoices i, effective e
    where i.user_id = p_business
      and i.status <> 'draft'
      and (e.limit_period <> 'monthly'
           or date_trunc('month', i.created_at at time zone 'Asia/Kolkata')
              = date_trunc('month', now() at time zone 'Asia/Kolkata'))
  )
  select jsonb_build_object(
    'plan_id', e.id,
    'plan_code', e.code,
    'plan_name', e.name,
    'invoice_limit', e.invoice_limit,
    'limit_period', e.limit_period,
    'extra_invoices', e.extra_invoices,
    'allowed', case when e.invoice_limit is null or e.limit_period = 'none' then null
                    else e.invoice_limit + e.extra_invoices end,
    'used', u.n,
    'starts_on', e.starts_on,
    'ends_on', e.ends_on,
    'price_monthly', e.price_monthly,
    'price_yearly', e.price_yearly,
    'enforced', coalesce((public.platform_setting('enforce_plan_limits'))::boolean, false)
  )
  from effective e, used u
  limit 1;
$$;
revoke all on function public.plan_usage(uuid) from public, anon, authenticated;

-- "Your plan: Free · 212 of 250 invoices used" (the signed-in owner's).
create or replace function public.my_plan()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when auth.uid() is null then null else public.plan_usage(auth.uid()) end;
$$;
revoke all on function public.my_plan() from public, anon;
grant execute on function public.my_plan() to authenticated;

create or replace function public.require_active_account(p_user uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.account_flags
             where user_id = p_user and suspended_at is not null) then
    raise exception 'Your account is paused. Contact support.' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.check_invoice_limit(p_user uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  usage jsonb := public.plan_usage(p_user);
begin
  if (usage ->> 'enforced')::boolean
     and usage ->> 'allowed' is not null
     and (usage ->> 'used')::int >= (usage ->> 'allowed')::int then
    raise exception 'You''ve used all % % invoices. Upgrade to keep creating invoices.',
      usage ->> 'allowed',
      case when usage ->> 'plan_code' = 'free' then 'free' else 'plan' end
      using errcode = 'P0001', hint = 'PLAN_LIMIT';
  end if;
end;
$$;
revoke all on function public.require_active_account(uuid) from public, anon;
revoke all on function public.check_invoice_limit(uuid) from public, anon;
grant execute on function public.require_active_account(uuid) to authenticated;
grant execute on function public.check_invoice_limit(uuid) to authenticated;

-- save_invoice: as in 20261127000001, plus the two checks for a new invoice.
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

  -- Super admin S2/S4: a paused account can't save; a new invoice is
  -- refused at the plan limit while "Enforce plan limits" is on.
  perform public.require_active_account(owner);
  if not is_edit then perform public.check_invoice_limit(owner); end if;

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


-- Quotation conversion: as in 20261126000000, plus the same checks.
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

  -- A conversion is a new invoice (S4).
  perform public.require_active_account(owner);
  perform public.check_invoice_limit(owner);

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


notify pgrst, 'reload schema';
commit;
