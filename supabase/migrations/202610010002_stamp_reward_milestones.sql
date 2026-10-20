alter table public.loyalty_cards
  add column if not exists reward_milestones jsonb not null default '[]'::jsonb;

comment on column public.loyalty_cards.reward_milestones is
  'Premios y mensajes personalizados que se activan al alcanzar sellos concretos.';
