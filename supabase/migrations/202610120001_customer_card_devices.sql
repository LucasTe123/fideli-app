create table if not exists public.customer_card_devices (
  business_id uuid not null,
  customer_id text not null,
  card_id text not null,
  device_token_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, customer_id, card_id, device_token_hash),
  foreign key (business_id, customer_id, card_id)
    references public.customer_card_enrollments (business_id, customer_id, card_id)
    on delete cascade
);

create index if not exists customer_card_devices_device_idx
  on public.customer_card_devices (business_id, customer_id, device_token_hash);

alter table public.customer_card_devices enable row level security;

insert into public.customer_card_devices (
  business_id,
  customer_id,
  card_id,
  device_token_hash
)
select
  business_id,
  customer_id,
  card_id,
  device_token_hash
from public.customer_card_enrollments
where device_token_hash is not null and device_token_hash <> ''
on conflict do nothing;

comment on table public.customer_card_devices is
  'Dispositivos autorizados por tarjeta; permite reunir pases en una PWA sin exponerlos a otros dispositivos.';
