alter table public.storefront_settings add column if not exists categories text[] not null default array[]::text[];
