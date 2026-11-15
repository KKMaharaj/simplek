alter table public.quotations
  add column if not exists user_id uuid references auth.users(id) on delete cascade
  default auth.uid();

do $$
declare only_user uuid;
begin
  if (select count(*) from auth.users) = 1 then
    select id into only_user from auth.users limit 1;
    update public.quotations set user_id = only_user where user_id is null;
  end if;
end $$;

create index if not exists quotations_user_id_idx
  on public.quotations (user_id);

alter table public.quotations enable row level security;
alter table public.quotation_items enable row level security;

drop policy if exists "Users read own quotations" on public.quotations;
create policy "Users read own quotations"
on public.quotations for select to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users create own quotations" on public.quotations;
create policy "Users create own quotations"
on public.quotations for insert to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users update own quotations" on public.quotations;
create policy "Users update own quotations"
on public.quotations for update to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users delete own quotations" on public.quotations;
create policy "Users delete own quotations"
on public.quotations for delete to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users read own quotation items" on public.quotation_items;
create policy "Users read own quotation items"
on public.quotation_items for select to authenticated
using (
  exists (
    select 1 from public.quotations q
    where q.id = quotation_id and q.user_id = auth.uid()
  )
);

drop policy if exists "Users create own quotation items" on public.quotation_items;
create policy "Users create own quotation items"
on public.quotation_items for insert to authenticated
with check (
  exists (
    select 1 from public.quotations q
    where q.id = quotation_id and q.user_id = auth.uid()
  )
);

drop policy if exists "Users update own quotation items" on public.quotation_items;
create policy "Users update own quotation items"
on public.quotation_items for update to authenticated
using (
  exists (
    select 1 from public.quotations q
    where q.id = quotation_id and q.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.quotations q
    where q.id = quotation_id and q.user_id = auth.uid()
  )
);

drop policy if exists "Users delete own quotation items" on public.quotation_items;
create policy "Users delete own quotation items"
on public.quotation_items for delete to authenticated
using (
  exists (
    select 1 from public.quotations q
    where q.id = quotation_id and q.user_id = auth.uid()
  )
);

revoke execute on function public.next_quotation_number(date) from anon;
