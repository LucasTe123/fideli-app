create table if not exists public.customer_reward_claims (
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id text not null,
  reward_id text not null,
  program_id text not null,
  reward_name text not null,
  earned_at timestamptz not null default now(),
  reminder_count integer not null default 0,
  last_reminder_at timestamptz,
  claimed_at timestamptz,
  primary key (business_id, customer_id, reward_id),
  foreign key (business_id, customer_id)
    references public.customers(business_id, id) on delete cascade
);

create index if not exists customer_reward_claims_due_idx
  on public.customer_reward_claims (earned_at, last_reminder_at)
  where claimed_at is null;

create index if not exists customer_reward_claims_business_idx
  on public.customer_reward_claims (business_id, claimed_at, earned_at desc);

alter table public.customer_reward_claims enable row level security;
revoke all on public.customer_reward_claims from anon, authenticated;
grant select on public.customer_reward_claims to authenticated;

drop policy if exists "members read reward claims" on public.customer_reward_claims;
create policy "members read reward claims"
  on public.customer_reward_claims for select
  using (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  );

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
      select jobid from cron.job where jobname = 'fideli-pending-reward-reminders'
    loop
      perform cron.unschedule(existing_job.jobid);
    end loop;

    perform cron.schedule(
      'fideli-pending-reward-reminders',
      '0 13 * * *',
      $job$
        select net.http_post(
          url := 'https://qdrssnhlbwkufnhgqfwo.supabase.co/functions/v1/wallet/api/cron/reward-claims',
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
