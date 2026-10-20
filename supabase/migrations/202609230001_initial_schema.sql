create extension if not exists pgcrypto;

create table public.businesses (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Fideli',
  category text not null default '',
  color_hex text not null default '#6750A4',
  branches jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.business_members (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'manager', 'cashier', 'viewer')),
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create table public.app_snapshots (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.customers (
  id text not null,
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text not null default '',
  email text not null default '',
  points integer not null default 0 check (points >= 0),
  stamps integer not null default 0 check (stamps >= 0),
  visits integer not null default 0 check (visits >= 0),
  tier text not null default 'Bronce',
  referral_code text not null,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, id),
  unique (id)
);

create table public.loyalty_events (
  id text primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id text not null,
  description text not null,
  points_delta integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.wallet_devices (
  device_library_identifier text primary key,
  push_token text not null,
  updated_at timestamptz not null default now()
);

create table public.wallet_passes (
  serial_number text primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  pass_type_identifier text not null,
  authentication_token text not null,
  update_tag bigint not null default ((extract(epoch from clock_timestamp()) * 1000)::bigint),
  updated_at timestamptz not null default now()
);

create table public.wallet_registrations (
  device_library_identifier text not null references public.wallet_devices(device_library_identifier) on delete cascade,
  serial_number text not null references public.wallet_passes(serial_number) on delete cascade,
  pass_type_identifier text not null,
  created_at timestamptz not null default now(),
  primary key (device_library_identifier, serial_number, pass_type_identifier)
);

create index customers_business_id_idx on public.customers(business_id);
create index events_business_id_idx on public.loyalty_events(business_id);
create index wallet_registrations_serial_idx on public.wallet_registrations(serial_number);

alter table public.businesses enable row level security;
alter table public.business_members enable row level security;
alter table public.app_snapshots enable row level security;
alter table public.customers enable row level security;
alter table public.loyalty_events enable row level security;
alter table public.wallet_devices enable row level security;
alter table public.wallet_passes enable row level security;
alter table public.wallet_registrations enable row level security;

create policy "owners manage businesses" on public.businesses
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "users manage own membership" on public.business_members
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "owners manage snapshots" on public.app_snapshots
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "members manage customers" on public.customers
  for all using (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  ) with check (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  );

create policy "members manage loyalty events" on public.loyalty_events
  for all using (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  ) with check (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  );

-- Wallet tables are intentionally service-role only. Apple accesses them through
-- the wallet Edge Function, which validates each pass authentication token.

