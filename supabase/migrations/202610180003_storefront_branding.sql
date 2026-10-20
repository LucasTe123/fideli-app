-- Branding is scoped to the same business as products and orders.
create table if not exists public.storefront_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  logo_url text not null default '',
  button_color text not null default '#171225' check (button_color ~ '^#[0-9a-fA-F]{6}$')
);
alter table public.storefront_settings enable row level security;
revoke all on public.storefront_settings from anon;
grant select, insert, update, delete on public.storefront_settings to authenticated;
create policy "members manage storefront branding" on public.storefront_settings
for all to authenticated
using (business_id in (select business_id from public.business_members where user_id = auth.uid()))
with check (business_id in (select business_id from public.business_members where user_id = auth.uid()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('storefront-images','storefront-images',true,350000,array['image/jpeg'])
on conflict (id) do update set public=true,file_size_limit=350000,allowed_mime_types=array['image/jpeg'];
create policy "public storefront images" on storage.objects for select
using (bucket_id = 'storefront-images');
create policy "members manage storefront images" on storage.objects for all to authenticated
using (bucket_id = 'storefront-images' and (storage.foldername(name))[1] in
  (select business_id::text from public.business_members where user_id=auth.uid()))
with check (bucket_id = 'storefront-images' and (storage.foldername(name))[1] in
  (select business_id::text from public.business_members where user_id=auth.uid()));

create or replace function public.get_storefront(p_slug text)
returns jsonb language sql stable security definer set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'name', b.name,
    'logo_url', coalesce(s.logo_url, ''),
    'button_color', coalesce(s.button_color, '#171225'),
    'products', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'description', p.description,
        'category', p.category,
        'image_url', p.image_url,
        'price', p.price
      ) order by p.created_at)
      from public.storefront_products p
      where p.business_id = b.id and p.active
    ), '[]'::jsonb)
  )
  from public.businesses b
  left join public.storefront_settings s on s.business_id = b.id
  where b.public_slug = p_slug
  limit 1;
$$;

revoke all on function public.get_storefront(text) from public;
grant execute on function public.get_storefront(text) to anon, authenticated;
