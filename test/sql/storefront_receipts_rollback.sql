begin;
do $$
declare
  a public.businesses%rowtype;
  b_id uuid := gen_random_uuid();
  b_slug text := 'qa-' || replace(gen_random_uuid()::text,'-','');
  product_id text := 'qa-' || gen_random_uuid()::text;
  qa_request uuid := gen_random_uuid();
  first_order jsonb;
  replay jsonb;
  other_order jsonb;
  visible_count integer;
begin
  select * into a from public.businesses where public_slug='culina';
  if not found then raise exception 'QA requires existing Culina business'; end if;
  insert into public.businesses(id,owner_id,name,public_slug) values(b_id,a.owner_id,'QA isolated business',b_slug);
  insert into public.storefront_products(business_id,id,name,price)
    values(a.id,product_id,'QA price 10',10),(b_id,product_id,'QA price 999',999);
  first_order := public.place_storefront_order(a.public_slug,'Cliente prueba','',
    jsonb_build_array(jsonb_build_object('id',product_id,'quantity',2,'price',0,'line_total',0)),qa_request, 'Sin cebolla');
  if first_order->>'customer_comment' <> 'Sin cebolla' then raise exception 'Comment missing'; end if;
  if not ((first_order->'items'->0) ? 'image_url') then raise exception 'Image snapshot missing'; end if;
  replay := public.place_storefront_order(a.public_slug,'Cliente prueba','',
    jsonb_build_array(jsonb_build_object('id',product_id,'quantity',2)),qa_request);
  if (first_order->>'total')::numeric <> 20 or first_order->>'id' <> replay->>'id'
    or replay->>'customer_comment' <> 'Sin cebolla'
    or first_order->>'created_at' is null then raise exception 'Receipt or server pricing failed'; end if;
  select count(*) into visible_count from public.storefront_orders where business_id=a.id and request_id=qa_request;
  if visible_count <> 1 then raise exception 'Duplicate checkout persisted'; end if;
  other_order := public.place_storefront_order(b_slug,'Cliente prueba','',
    jsonb_build_array(jsonb_build_object('id',product_id,'quantity',1)),qa_request);
  if (other_order->>'total')::numeric <> 999 then raise exception 'Cross-business request isolation failed'; end if;
  perform set_config('request.jwt.claim.sub', a.owner_id::text, true);
  execute 'set local role authenticated';
  select count(*) into visible_count from public.storefront_orders where business_id=b_id;
  if visible_count <> 0 then raise exception 'RLS leaked another business orders'; end if;
  update public.storefront_orders set status='entregado' where business_id=b_id;
  get diagnostics visible_count = row_count;
  if visible_count <> 0 then raise exception 'RLS allowed cross-business update'; end if;
  select count(*) into visible_count from public.storefront_products where business_id=b_id;
  if visible_count <> 0 then raise exception 'RLS leaked another business products'; end if;
  select count(*) into visible_count from public.storefront_orders where business_id=a.id and request_id=qa_request;
  if visible_count <> 1 then raise exception 'Business cannot see its new order'; end if;
  execute 'reset role';
end $$;
select 'PASS: server prices, receipt, retry deduplication, tenant visibility and updates' as validation;
rollback;
