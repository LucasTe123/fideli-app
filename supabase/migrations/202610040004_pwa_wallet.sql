create extension if not exists pgcrypto;

alter table public.customers
  add column if not exists pwa_access_token text;

update public.customers
set pwa_access_token = replace(gen_random_uuid()::text, '-', '') ||
  substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)
where pwa_access_token is null or pwa_access_token = '';

alter table public.customers
  alter column pwa_access_token set default (
    replace(gen_random_uuid()::text, '-', '') ||
    substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)
  );

create unique index if not exists customers_pwa_access_token_key
  on public.customers (pwa_access_token)
  where pwa_access_token is not null;

create table if not exists public.web_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id text not null,
  card_id text,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  user_agent text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint web_push_customer_fk
    foreign key (business_id, customer_id)
    references public.customers(business_id, id)
    on delete cascade,
  constraint web_push_business_endpoint_key unique (business_id, endpoint)
);

alter table public.web_push_subscriptions enable row level security;
revoke all on table public.web_push_subscriptions from anon, authenticated;

create index if not exists web_push_subscriptions_customer_idx
  on public.web_push_subscriptions (business_id, customer_id);
