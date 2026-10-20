-- One confirmed checkout creates one durable order, even after retry.
alter table public.storefront_orders add column if not exists request_id uuid;
create unique index if not exists storefront_orders_request_idx
  on public.storefront_orders(business_id,request_id) where request_id is not null;
drop function if exists public.place_storefront_order(text,text,text,jsonb);
create or replace function public.place_storefront_order(
  p_slug text, p_name text, p_phone text, p_items jsonb, p_request_id uuid default null
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, extensions
as $$
declare
  b public.businesses%rowtype;
  saved public.storefront_orders%rowtype;
  normalized_items jsonb;
  order_total numeric(12,2);
  order_code text;
  requested_item jsonb;
  quantity_text text;
  item_count integer;
begin
  select * into b from public.businesses where public_slug = p_slug;
  if not found then raise exception 'Local no encontrado'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'Escribe tu nombre'; end if;
  if length(trim(p_name)) > 120 or length(coalesce(p_phone,'')) > 40 then
    raise exception 'Revisa el nombre y el teléfono';
  end if;
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(b.id::text || p_request_id::text, 0));
    select * into saved from public.storefront_orders
      where business_id=b.id and request_id=p_request_id;
    if found then
      return jsonb_build_object('id',saved.id,'total',saved.total,'items',saved.items,
        'business_name',b.name,'whatsapp_phone',coalesce(b.whatsapp_phone,''),
        'customer_name',saved.customer_name,'customer_phone',saved.customer_phone,
        'created_at',saved.created_at,'status',saved.status);
    end if;
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'El carrito no es válido'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'El carrito está vacío'; end if;

  item_count := jsonb_array_length(p_items);
  if item_count > 100 then raise exception 'El carrito tiene demasiados productos'; end if;
  for requested_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(requested_item) is distinct from 'object'
      or jsonb_typeof(requested_item->'id') is distinct from 'string'
      or length(trim(coalesce(requested_item->>'id', ''))) = 0 then
      raise exception 'El carrito contiene un producto inválido';
    end if;
    quantity_text := requested_item->>'quantity';
    if jsonb_typeof(requested_item->'quantity') is distinct from 'number'
      or quantity_text !~ '^[0-9]+$'
      or quantity_text::numeric < 1
      or quantity_text::numeric > 99 then
      raise exception 'La cantidad de un producto no es válida';
    end if;
  end loop;

  if (select count(distinct item->>'id') from jsonb_array_elements(p_items) as x(item)) <> item_count then
    raise exception 'El carrito contiene productos repetidos';
  end if;

  with requested as (
    select (item->>'id') as product_id, (item->>'quantity')::integer as quantity
    from jsonb_array_elements(p_items) item
  ), priced as (
    select p.id, p.name, p.price, r.quantity, p.price * r.quantity as line_total
    from requested r join public.storefront_products p on p.id = r.product_id and p.business_id = b.id and p.active
  )
  select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'quantity', quantity, 'price', price, 'line_total', line_total) order by id), sum(line_total), count(*)
  into normalized_items, order_total, item_count from priced;
  if normalized_items is null then raise exception 'No hay productos disponibles'; end if;
  if item_count <> jsonb_array_length(p_items) then
    raise exception 'Uno o más productos ya no están disponibles. Actualiza el catálogo e inténtalo otra vez.';
  end if;

  loop
    order_code := 'ORD-' || upper(encode(gen_random_bytes(5), 'hex'));
    exit when not exists (
      select 1 from public.storefront_orders
      where business_id = b.id and id = order_code
    );
  end loop;

  insert into public.storefront_orders (business_id,id,customer_name,customer_phone,items,total,request_id)
  values (b.id,order_code,trim(p_name),trim(coalesce(p_phone,'')),normalized_items,order_total,p_request_id) returning * into saved;
  return jsonb_build_object('id',order_code,'total',order_total,'items',normalized_items,'business_name',b.name,'whatsapp_phone',coalesce(b.whatsapp_phone,''),'customer_name',saved.customer_name,
    'customer_phone',saved.customer_phone,'created_at',saved.created_at,'status',saved.status);
end;
$$;

revoke all on function public.place_storefront_order(text, text, text, jsonb, uuid) from public;
grant execute on function public.place_storefront_order(text, text, text, jsonb, uuid) to anon, authenticated;


-- Realtime delivery remains protected by the existing business membership RLS.
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
    and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
      and schemaname='public' and tablename='storefront_orders') then
    alter publication supabase_realtime add table public.storefront_orders;
  end if;
end $$;
