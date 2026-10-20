alter table public.customers
  add column if not exists card_balances jsonb not null default '{}'::jsonb;

comment on column public.customers.card_balances is
  'Saldo independiente por tarjeta: puntos, sellos y visitas indexados por card_id.';
