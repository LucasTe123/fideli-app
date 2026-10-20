alter table public.customers
  add column if not exists wallet_message text;

comment on column public.customers.wallet_message is
  'Mensaje más reciente mostrado en Apple Wallet para este cliente.';
