-- Let an accountant viewing a shared business load its logo and signature, so
-- the documents they open look the same as the owner's. Upload, replace and
-- delete stay limited to the owner's own folder.
begin;

drop policy if exists "Users read own business media" on storage.objects;
drop policy if exists "Read media of the business being viewed" on storage.objects;
create policy "Read media of the business being viewed"
on storage.objects for select to authenticated
using (
  bucket_id = 'business-media'
  and (storage.foldername(name))[1] = (select public.viewing_business())::text
);

commit;
