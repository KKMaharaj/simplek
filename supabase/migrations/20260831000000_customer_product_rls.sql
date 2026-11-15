-- Keep customer and product data private to the authenticated business owner.
-- The columns are added defensively for databases created before ownership was
-- included in the schema. New app inserts always provide auth.uid().

alter table public.customers
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

alter table public.products
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

create index if not exists customers_user_id_idx
  on public.customers (user_id);

create index if not exists products_user_id_idx
  on public.products (user_id);

alter table public.customers enable row level security;
alter table public.products enable row level security;

drop policy if exists "Users can read their customers" on public.customers;
create policy "Users can read their customers"
on public.customers for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can create their customers" on public.customers;
create policy "Users can create their customers"
on public.customers for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their customers" on public.customers;
create policy "Users can update their customers"
on public.customers for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their customers" on public.customers;
create policy "Users can delete their customers"
on public.customers for delete to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can read their products" on public.products;
create policy "Users can read their products"
on public.products for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can create their products" on public.products;
create policy "Users can create their products"
on public.products for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their products" on public.products;
create policy "Users can update their products"
on public.products for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their products" on public.products;
create policy "Users can delete their products"
on public.products for delete to authenticated
using (auth.uid() = user_id);
