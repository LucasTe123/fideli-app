alter table public.loyalty_cards
  add column if not exists expiration_notice text,
  add column if not exists expiration_notice_key text;

create table if not exists public.card_expiration_notifications (
  business_id uuid not null,
  card_id text not null,
  reminder_key text not null,
  sent_at timestamptz not null default now(),
  primary key (business_id, card_id, reminder_key),
  foreign key (business_id, card_id)
    references public.loyalty_cards(business_id, id) on delete cascade
);

create index if not exists card_expiration_notifications_sent_idx
  on public.card_expiration_notifications(sent_at desc);

alter table public.card_expiration_notifications enable row level security;
revoke all on public.card_expiration_notifications from anon, authenticated;

comment on table public.card_expiration_notifications is
  'Registro idempotente de avisos automáticos de vencimiento enviados por tarjeta.';

do $$
declare
  existing_job record;
begin
  begin
    create extension if not exists pg_cron with schema extensions;
    create extension if not exists pg_net with schema extensions;
  exception when insufficient_privilege then
    raise notice 'pg_cron o pg_net no disponible; configure el job desde Supabase Cron.';
  end;

  if exists (select 1 from pg_extension where extname = 'pg_cron')
     and exists (select 1 from pg_extension where extname = 'pg_net') then
    for existing_job in
      select jobid from cron.job where jobname = 'fideli-card-expiration-notifications'
    loop
      perform cron.unschedule(existing_job.jobid);
    end loop;

    perform cron.schedule(
      'fideli-card-expiration-notifications',
      '*/15 * * * *',
      $job$
        select net.http_post(
          url := 'https://qdrssnhlbwkufnhgqfwo.supabase.co/functions/v1/wallet/api/cron/expirations',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFkcnNzbmhsYndrdWZuaGdxZndvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4OTAyMzAsImV4cCI6MjA5NjQ2NjIzMH0.Y-P94zJJKx4n5L5f-23CoKFaQ3gP1ssvcKv6cn3uP1U'
          ),
          body := '{}'::jsonb,
          timeout_milliseconds := 120000
        );
      $job$
    );
  end if;
end
$$;
