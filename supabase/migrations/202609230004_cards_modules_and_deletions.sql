alter table public.customers
  add column if not exists deleted_at timestamptz;

alter table public.wallet_passes
  add column if not exists customer_id text,
  add column if not exists card_id text;

update public.wallet_passes
set customer_id = serial_number
where customer_id is null;

create table if not exists public.loyalty_cards (
  id text not null,
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  card_kind text not null default 'Fidelización',
  program_type text not null default 'stamps',
  earning_rate integer not null default 1,
  goal integer not null default 7,
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, id)
);

create table if not exists public.module_records (
  business_id uuid not null references public.businesses(id) on delete cascade,
  module_type text not null,
  record_id text not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (business_id, module_type, record_id)
);

create index if not exists loyalty_cards_business_idx
  on public.loyalty_cards(business_id);
create index if not exists module_records_business_idx
  on public.module_records(business_id, module_type);
create index if not exists wallet_passes_customer_idx
  on public.wallet_passes(business_id, customer_id);

alter table public.loyalty_cards enable row level security;
alter table public.module_records enable row level security;

create policy "members manage loyalty cards" on public.loyalty_cards
  for all using (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  ) with check (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  );

create policy "members manage module records" on public.module_records
  for all using (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  ) with check (
    business_id in (select business_id from public.business_members where user_id = auth.uid())
  );
