alter table public.business_profiles
  add column if not exists pan text not null default '',
  add column if not exists gst_registration_type text not null default 'Regular',
  add column if not exists business_state text not null default '',
  add column if not exists place_of_supply text not null default '',
  add column if not exists financial_year text not null default '',
  add column if not exists invoice_prefix text not null default 'INV',
  add column if not exists quotation_prefix text not null default 'QTN';

create or replace function public.next_invoice_number(
  p_prefix text,
  p_invoice_date date,
  p_financial_year text
) returns text language plpgsql security definer set search_path = public as $$
declare allocated_number bigint; financial_year_label text; clean_prefix text;
begin
  clean_prefix := upper(trim(coalesce(p_prefix, 'INV')));
  if clean_prefix !~ '^[A-Z0-9-]{1,20}$' then raise exception 'Invalid invoice prefix'; end if;
  financial_year_label := trim(coalesce(p_financial_year, ''));
  if financial_year_label = '' then
    financial_year_label := case when extract(month from p_invoice_date) >= 4
      then format('%s-%s', extract(year from p_invoice_date)::integer, right((extract(year from p_invoice_date)::integer + 1)::text, 2))
      else format('%s-%s', extract(year from p_invoice_date)::integer - 1, right(extract(year from p_invoice_date)::integer::text, 2)) end;
  end if;
  update public.document_number_sequences set next_number = next_number + 1
    where document_type = 'invoice' returning next_number - 1 into allocated_number;
  return format('%s/%s/%s', clean_prefix, financial_year_label, lpad(allocated_number::text, 4, '0'));
end; $$;

create or replace function public.next_quotation_number(
  p_prefix text,
  p_quotation_date date,
  p_financial_year text
) returns text language plpgsql security definer set search_path = public as $$
declare allocated_number bigint; financial_year_label text; clean_prefix text;
begin
  clean_prefix := upper(trim(coalesce(p_prefix, 'QTN')));
  if clean_prefix !~ '^[A-Z0-9-]{1,20}$' then raise exception 'Invalid quotation prefix'; end if;
  financial_year_label := trim(coalesce(p_financial_year, ''));
  if financial_year_label = '' then
    financial_year_label := case when extract(month from p_quotation_date) >= 4
      then format('%s-%s', extract(year from p_quotation_date)::integer, right((extract(year from p_quotation_date)::integer + 1)::text, 2))
      else format('%s-%s', extract(year from p_quotation_date)::integer - 1, right(extract(year from p_quotation_date)::integer::text, 2)) end;
  end if;
  update public.quotation_number_sequences set next_number = next_number + 1
    where sequence_key = 'quotation' returning next_number - 1 into allocated_number;
  return format('%s/%s/%s', clean_prefix, financial_year_label, lpad(allocated_number::text, 4, '0'));
end; $$;

grant execute on function public.next_invoice_number(text, date, text) to authenticated;
grant execute on function public.next_quotation_number(text, date, text) to authenticated;
