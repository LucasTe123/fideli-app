alter table public.customers
  add column if not exists wallet_campaign_url text;

comment on column public.customers.wallet_campaign_url is
  'Optional current campaign URL shown as a call to action in Apple and Google Wallet.';
