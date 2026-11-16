-- Let signed-in devices hear about changes to their own business's rows, so
-- the phone app and the web app stay in step without a manual refresh.
-- Realtime applies each table's row-level security, so a business only
-- receives events for rows it can already read.
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;
  foreach t in array array['invoices', 'quotations', 'customers', 'products'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
