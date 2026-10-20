alter table public.loyalty_cards
  add column if not exists color_hex text,
  add column if not exists background_image_path text;
