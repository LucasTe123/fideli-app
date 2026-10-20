-- Cada cliente puede conservar exactamente una tarjeta de cada familia:
-- sellos, puntos, membresía y regalo. Sellos y puntos dejan de compartir la
-- antigua categoría "loyalty" para que una no reemplace a la otra.

alter table public.customer_card_enrollments
  drop constraint if exists customer_card_enrollments_category_check;

update public.customer_card_enrollments enrollment
set category = case
  when card.card_kind = 'Tarjeta de regalo' then 'gift'
  when card.program_type = 'membership' then 'membership'
  when card.program_type in ('points', 'hybrid') then 'points'
  else 'stamps'
end,
updated_at = now()
from public.loyalty_cards card
where card.business_id = enrollment.business_id
  and card.id = enrollment.card_id;

alter table public.customer_card_enrollments
  add constraint customer_card_enrollments_category_check
  check (category in ('stamps', 'points', 'membership', 'gift'));

with existing as (
  select
    customer.business_id,
    customer.id as customer_id,
    card.id as card_id,
    case
      when card.card_kind = 'Tarjeta de regalo' then 'gift'
      when card.program_type = 'membership' then 'membership'
      when card.program_type in ('points', 'hybrid') then 'points'
      else 'stamps'
    end as category,
    customer.pwa_device_token_hash as device_token_hash,
    row_number() over (
      partition by customer.business_id, customer.id,
        case
          when card.card_kind = 'Tarjeta de regalo' then 'gift'
          when card.program_type = 'membership' then 'membership'
          when card.program_type in ('points', 'hybrid') then 'points'
          else 'stamps'
        end
      order by card.created_at, card.id
    ) as category_position
  from public.customers customer
  join lateral jsonb_object_keys(coalesce(customer.card_balances, '{}'::jsonb)) balance(card_id)
    on true
  join public.loyalty_cards card
    on card.business_id = customer.business_id and card.id = balance.card_id
  where customer.deleted_at is null
)
insert into public.customer_card_enrollments (
  business_id,
  customer_id,
  card_id,
  category,
  device_token_hash
)
select business_id, customer_id, card_id, category, device_token_hash
from existing
where category_position = 1
on conflict (business_id, customer_id, card_id) do update
set category = excluded.category,
    device_token_hash = coalesce(
      public.customer_card_enrollments.device_token_hash,
      excluded.device_token_hash
    ),
    updated_at = now();

comment on table public.customer_card_enrollments is
  'Una identidad de cliente con una sola inscripción de sellos, puntos, membresía y regalo.';
