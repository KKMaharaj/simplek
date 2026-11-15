-- Invoice-number allocation for the current single-business development app.
-- The format is INV/YYYY-YY/0001. It is generated in Postgres so concurrent
-- invoice saves cannot receive the same number. Per-business sequences should
-- replace this singleton table when Supabase Auth/business ownership is added.

create table if not exists public.document_number_sequences (
  document_type text primary key
    check (document_type in ('invoice')),
  next_number bigint not null default 1 check (next_number > 0)
);

insert into public.document_number_sequences (document_type, next_number)
values ('invoice', 1)
on conflict (document_type) do nothing;

alter table public.document_number_sequences enable row level security;

create or replace function public.next_invoice_number(
  p_prefix text default 'INV',
  p_invoice_date date default current_date
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  allocated_number bigint;
  financial_year_start integer;
  financial_year_label text;
  clean_prefix text;
begin
  clean_prefix := upper(trim(coalesce(p_prefix, 'INV')));
  if clean_prefix !~ '^[A-Z0-9-]{1,20}$' then
    raise exception 'Invoice prefix must use 1-20 letters, numbers, or hyphens';
  end if;

  financial_year_start := case
    when extract(month from p_invoice_date) >= 4 then extract(year from p_invoice_date)::integer
    else extract(year from p_invoice_date)::integer - 1
  end;
  financial_year_label := format('%s-%s', financial_year_start, right((financial_year_start + 1)::text, 2));

  update public.document_number_sequences
  set next_number = next_number + 1
  where document_type = 'invoice'
  returning next_number - 1 into allocated_number;

  return format('%s/%s/%s', clean_prefix, financial_year_label, lpad(allocated_number::text, 4, '0'));
end;
$$;

revoke all on table public.document_number_sequences from anon, authenticated;
grant execute on function public.next_invoice_number(text, date) to anon, authenticated;
