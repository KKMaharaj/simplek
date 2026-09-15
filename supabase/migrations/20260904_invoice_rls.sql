alter table public.invoices
  add column if not exists user_id uuid references auth.users(id) on delete cascade
  default auth.uid();

-- Recover ownership for legacy invoices only when their customer name maps to
-- exactly one tenant. Ambiguous rows remain unassigned instead of leaking data.
with customer_owners as (
  select lower(trim(name)) as customer_name, (array_agg(user_id))[1] as user_id
  from public.customers
  where user_id is not null
  group by lower(trim(name))
  having count(distinct user_id) = 1
)
update public.invoices i
set user_id = owners.user_id
from customer_owners owners
where i.user_id is null
  and lower(trim(i.customer_name)) = owners.customer_name;

create index if not exists invoices_user_id_idx
  on public.invoices (user_id);

alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;

drop policy if exists "Allow all invoices" on public.invoices;
drop policy if exists "Users read own invoices" on public.invoices;
create policy "Users read own invoices"
on public.invoices for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users create own invoices" on public.invoices;
create policy "Users create own invoices"
on public.invoices for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users update own invoices" on public.invoices;
create policy "Users update own invoices"
on public.invoices for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users delete own invoices" on public.invoices;
create policy "Users delete own invoices"
on public.invoices for delete to authenticated
using (auth.uid() = user_id);

drop policy if exists "Allow all invoice items" on public.invoice_items;
drop policy if exists "Users read own invoice items" on public.invoice_items;
create policy "Users read own invoice items"
on public.invoice_items for select to authenticated
using (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id and i.user_id = auth.uid()
  )
);

drop policy if exists "Users create own invoice items" on public.invoice_items;
create policy "Users create own invoice items"
on public.invoice_items for insert to authenticated
with check (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id and i.user_id = auth.uid()
  )
);

drop policy if exists "Users update own invoice items" on public.invoice_items;
create policy "Users update own invoice items"
on public.invoice_items for update to authenticated
using (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id and i.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id and i.user_id = auth.uid()
  )
);

drop policy if exists "Users delete own invoice items" on public.invoice_items;
create policy "Users delete own invoice items"
on public.invoice_items for delete to authenticated
using (
  exists (
    select 1 from public.invoices i
    where i.id = invoice_id and i.user_id = auth.uid()
  )
);
