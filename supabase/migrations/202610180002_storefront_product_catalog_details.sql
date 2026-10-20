-- Catalog presentation fields are added separately so projects that already
-- applied the initial storefront migration can upgrade without replaying it.
alter table public.storefront_products
  add column if not exists category text not null default 'General',
  add column if not exists image_url text not null default '';

create or replace function public.get_storefront(p_slug text)
returns jsonb language sql stable security definer set search_path = pg_catalog, public
as $$
  select jsonb_build_object(
    'name', b.name,
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
  where b.public_slug = p_slug
  limit 1;
$$;

revoke all on function public.get_storefront(text) from public;
grant execute on function public.get_storefront(text) to anon, authenticated;
