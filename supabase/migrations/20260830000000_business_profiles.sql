create table if not exists public.business_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  owner_name text not null default '',
  business_name text not null default '',
  address text not null default '',
  gst_registered boolean not null default false,
  gstin text not null default '',
  phone text not null default '',
  email text not null default '',
  bank_name text not null default '',
  bank_branch text not null default '',
  bank_account text not null default '',
  ifsc text not null default '',
  upi_id text not null default '',
  quotation_terms text not null default '',
  invoice_terms text not null default '',
  default_due_day integer check (default_due_day between 1 and 31),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.business_profiles enable row level security;

drop policy if exists "Users can read their business profile" on public.business_profiles;
create policy "Users can read their business profile"
on public.business_profiles for select
using (auth.uid() = user_id);

drop policy if exists "Users can create their business profile" on public.business_profiles;
create policy "Users can create their business profile"
on public.business_profiles for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update their business profile" on public.business_profiles;
create policy "Users can update their business profile"
on public.business_profiles for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
