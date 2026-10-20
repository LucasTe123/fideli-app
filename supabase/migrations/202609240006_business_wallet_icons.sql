alter table public.businesses
  add column if not exists wallet_icon_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'business-assets',
  'business-assets',
  false,
  2097152,
  array['image/png']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "business owners read wallet artwork"
on storage.objects for select
to authenticated
using (
  bucket_id = 'business-assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "business owners upload wallet artwork"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'business-assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "business owners update wallet artwork"
on storage.objects for update
to authenticated
using (
  bucket_id = 'business-assets'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'business-assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);

create policy "business owners delete wallet artwork"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'business-assets'
  and (storage.foldername(name))[1] = auth.uid()::text
);
