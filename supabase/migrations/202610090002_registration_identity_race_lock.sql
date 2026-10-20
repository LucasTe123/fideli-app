alter table public.customers
  add column if not exists registration_phone_key text,
  add column if not exists registration_email_key text;

create unique index if not exists customers_registration_phone_key_unique
  on public.customers (registration_phone_key)
  where deleted_at is null and registration_phone_key is not null;

create unique index if not exists customers_registration_email_key_unique
  on public.customers (registration_email_key)
  where deleted_at is null and registration_email_key is not null;

comment on column public.customers.registration_phone_key is
  'Bloqueo de concurrencia para impedir dos altas públicas simultáneas con el mismo teléfono.';

comment on column public.customers.registration_email_key is
  'Bloqueo de concurrencia para impedir dos altas públicas simultáneas con el mismo correo.';
