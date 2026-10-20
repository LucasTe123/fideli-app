create table if not exists public.campaign_requests (
  business_id uuid not null references public.businesses(id) on delete cascade,
  request_id text not null,
  status text not null default 'processing' check (status in ('processing', 'completed')),
  response_payload jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, request_id)
);

comment on table public.campaign_requests is
  'Claves de idempotencia para impedir envíos duplicados de una campaña.';

alter table public.campaign_requests enable row level security;

-- La Edge Function usa service_role. Los clientes no necesitan acceso directo.
