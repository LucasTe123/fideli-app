-- Repara las tarjetas creadas durante el despliegue de la vinculacion por
-- dispositivo. Solo afecta altas recientes; las futuras se enlazan al crear.
insert into public.customer_card_devices (
  business_id,
  customer_id,
  card_id,
  device_token_hash
)
select distinct
  recent.business_id,
  recent.customer_id,
  recent.card_id,
  known.device_token_hash
from public.customer_card_enrollments recent
join public.customer_card_enrollments known
  on known.business_id = recent.business_id
 and known.customer_id = recent.customer_id
where recent.created_at >= timestamptz '2026-10-12 13:30:00+00'
  and known.device_token_hash is not null
  and known.device_token_hash <> ''
on conflict do nothing;
