create table if not exists public.customer_card_enrollments (
  business_id uuid not null,
  customer_id text not null,
  card_id text not null,
  category text not null check (category in ('loyalty', 'membership', 'gift')),
  device_token_hash text,
  claim_token_hash text,
  claim_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, customer_id, card_id),
  foreign key (business_id, customer_id)
    references public.customers (business_id, id) on delete cascade,
  foreign key (business_id, card_id)
    references public.loyalty_cards (business_id, id) on delete cascade
);

create unique index if not exists customer_card_enrollments_category_unique
  on public.customer_card_enrollments (business_id, customer_id, category);

create index if not exists customer_card_enrollments_card_idx
  on public.customer_card_enrollments (business_id, card_id);

alter table public.customer_card_enrollments enable row level security;

drop policy if exists "members manage customer card enrollments"
  on public.customer_card_enrollments;
create policy "members manage customer card enrollments"
  on public.customer_card_enrollments
  for all using (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  ) with check (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  );

with existing as (
  select
    customer.business_id,
    customer.id as customer_id,
    card.id as card_id,
    case
      when card.card_kind = 'Tarjeta de regalo' then 'gift'
      when card.program_type = 'membership' then 'membership'
      else 'loyalty'
    end as category,
    customer.pwa_device_token_hash as device_token_hash,
    customer.pwa_claim_token_hash as claim_token_hash,
    customer.pwa_claim_expires_at as claim_expires_at,
    row_number() over (
      partition by customer.business_id, customer.id,
        case
          when card.card_kind = 'Tarjeta de regalo' then 'gift'
          when card.program_type = 'membership' then 'membership'
          else 'loyalty'
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
  device_token_hash,
  claim_token_hash,
  claim_expires_at
)
select
  business_id,
  customer_id,
  card_id,
  category,
  device_token_hash,
  claim_token_hash,
  claim_expires_at
from existing
where category_position = 1
on conflict (business_id, customer_id, card_id) do nothing;

alter table public.customer_card_enrollments replica identity full;
alter publication supabase_realtime add table public.customer_card_enrollments;

comment on table public.customer_card_enrollments is
  'Una identidad de cliente con una inscripción independiente de fidelización, membresía y regalo.';
