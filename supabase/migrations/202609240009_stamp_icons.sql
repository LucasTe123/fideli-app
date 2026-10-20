alter table public.loyalty_cards
  add column if not exists stamp_icon text not null default 'coffee',
  add column if not exists wallet_layout text not null default 'poster',
  add column if not exists stamp_notification_message text not null
    default '¡Ya tienes {sellos} sellos! Sigue así.';
