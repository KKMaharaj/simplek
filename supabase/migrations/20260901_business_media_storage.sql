alter table public.business_profiles
  add column if not exists logo_object_path text not null default '',
  add column if not exists signature_object_path text not null default '',
  add column if not exists qr_object_path text not null default '';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'business-media',
  'business-media',
  false,
  5242880,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users read own business media" on storage.objects;
create policy "Users read own business media"
on storage.objects for select to authenticated
using (
  bucket_id = 'business-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users upload own business media" on storage.objects;
create policy "Users upload own business media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'business-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users update own business media" on storage.objects;
create policy "Users update own business media"
on storage.objects for update to authenticated
using (
  bucket_id = 'business-media'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'business-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Users delete own business media" on storage.objects;
create policy "Users delete own business media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'business-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
