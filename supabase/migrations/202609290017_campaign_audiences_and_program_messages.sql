alter table public.customers
  add column if not exists last_activity_at timestamptz;

update public.customers
set last_activity_at = updated_at
where last_activity_at is null
  and (points > 0 or stamps > 0 or visits > 0);

create index if not exists customers_business_last_activity_idx
  on public.customers (business_id, last_activity_at)
  where deleted_at is null;

alter table public.loyalty_cards
  add column if not exists welcome_message text not null
    default '¡Bienvenido! Nos alegra tenerte aquí.',
  add column if not exists completion_message text not null
    default '🎉 ¡Completaste tu tarjeta! Tu recompensa está lista.';

comment on column public.customers.last_activity_at is
  'Última operación de fidelización; se usa para campañas de clientes inactivos.';

comment on column public.loyalty_cards.welcome_message is
  'Mensaje visible al agregar la tarjeta a Wallet.';

comment on column public.loyalty_cards.completion_message is
  'Mensaje de actualización cuando el cliente alcanza la meta del programa.';
