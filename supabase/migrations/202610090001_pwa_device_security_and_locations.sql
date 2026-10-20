create extension if not exists pgcrypto;

alter table public.businesses
  add column if not exists locations jsonb not null default '[]'::jsonb;

alter table public.customers
  add column if not exists phone_normalized text,
  add column if not exists pwa_device_token_hash text,
  add column if not exists pwa_claim_token_hash text,
  add column if not exists pwa_claim_expires_at timestamptz;

create index if not exists customers_business_email_lookup_idx
  on public.customers (business_id, lower(email))
  where deleted_at is null;

update public.customers
set phone_normalized = regexp_replace(coalesce(phone, ''), '\D', '', 'g')
where phone_normalized is null;

create index if not exists customers_business_phone_lookup_idx
  on public.customers (business_id, phone_normalized)
  where deleted_at is null;

create unique index if not exists customers_pwa_device_token_hash_key
  on public.customers (pwa_device_token_hash)
  where pwa_device_token_hash is not null;

comment on column public.customers.pwa_device_token_hash is
  'SHA-256 del secreto local que liga la PWA a un solo dispositivo.';

comment on column public.customers.pwa_claim_token_hash is
  'SHA-256 del token de un solo uso utilizado para activar la PWA.';
