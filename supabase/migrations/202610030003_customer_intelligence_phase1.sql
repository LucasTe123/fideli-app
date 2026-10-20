-- Fideli Customer Intelligence Engine · fase 1
-- Métricas explicables, cadencia adaptativa, segmentos e historial multi-tenant.

alter table public.loyalty_events
  add column if not exists event_type text not null default 'other',
  add column if not exists program_id text,
  add column if not exists amount_minor bigint not null default 0,
  add column if not exists currency text not null default 'BOB',
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.loyalty_events drop constraint if exists loyalty_events_event_type_check;
alter table public.loyalty_events add constraint loyalty_events_event_type_check
  check (event_type in (
    'visit', 'purchase', 'stamp_added', 'points_added', 'reward_redeemed',
    'qr_scan', 'referral', 'wallet_pass_created', 'wallet_pass_updated',
    'adjustment', 'other'
  ));

update public.loyalty_events set event_type = case
  when description ilike '%canje%' then 'reward_redeemed'
  when description ilike '%refer%' then 'referral'
  when description ilike '%sello%' then 'stamp_added'
  when description ilike '%punto%' then 'points_added'
  when description ilike '%visita%' then 'visit'
  else event_type
end
where event_type = 'other';

create index if not exists loyalty_events_customer_timeline_idx
  on public.loyalty_events (business_id, customer_id, created_at desc);
create index if not exists loyalty_events_type_timeline_idx
  on public.loyalty_events (business_id, event_type, created_at desc);

create table if not exists public.business_intelligence_baselines (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  median_visit_interval_days numeric(10,2) not null default 30,
  median_visits_90d numeric(10,2) not null default 1,
  p75_visits_90d numeric(10,2) not null default 2,
  max_spend_90d bigint not null default 0,
  customer_count integer not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_features (
  business_id uuid not null,
  customer_id text not null,
  first_visit_at timestamptz,
  last_visit_at timestamptz,
  total_visits integer not null default 0,
  total_transactions integer not null default 0,
  total_spend_minor bigint not null default 0,
  average_ticket_minor bigint not null default 0,
  customer_age_days integer not null default 0,
  days_since_last_visit integer,
  visits_7d integer not null default 0,
  visits_30d integer not null default 0,
  visits_60d integer not null default 0,
  visits_90d integer not null default 0,
  spend_30d_minor bigint not null default 0,
  spend_90d_minor bigint not null default 0,
  average_visit_interval_days numeric(10,2),
  median_visit_interval_days numeric(10,2),
  visit_interval_stddev_days numeric(10,2),
  expected_visit_interval_days numeric(10,2),
  expected_next_visit_at timestamptz,
  delay_ratio numeric(10,3),
  historical_frequency numeric(10,4) not null default 0,
  recent_frequency numeric(10,4) not null default 0,
  frequency_change numeric(10,4) not null default 0,
  visit_trend text not null default 'stable'
    check (visit_trend in ('growing', 'stable', 'declining')),
  spend_trend text not null default 'stable'
    check (spend_trend in ('growing', 'stable', 'declining')),
  recency_score numeric(6,4) not null default 0,
  frequency_score numeric(6,4) not null default 0,
  monetary_score numeric(6,4) not null default 0,
  rfm_score numeric(6,4) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (business_id, customer_id),
  foreign key (business_id, customer_id)
    references public.customers(business_id, id) on delete cascade
);

create table if not exists public.customer_segments (
  business_id uuid not null,
  customer_id text not null,
  segment_code text not null default 'NEW'
    check (segment_code in (
      'NEW', 'FREQUENT', 'REGULAR', 'OCCASIONAL',
      'AT_RISK', 'INACTIVE', 'RECOVERED'
    )),
  previous_segment text,
  risk_score numeric(6,4) not null default 0,
  value_score numeric(6,4) not null default 0,
  reason_codes text[] not null default '{}',
  explanation text not null default '',
  expected_next_visit_at timestamptz,
  last_evaluated_at timestamptz not null default now(),
  primary key (business_id, customer_id),
  foreign key (business_id, customer_id)
    references public.customers(business_id, id) on delete cascade
);

create table if not exists public.customer_segment_history (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  customer_id text not null,
  previous_segment text,
  new_segment text not null,
  reason text not null default '',
  scores_snapshot jsonb not null default '{}'::jsonb,
  changed_at timestamptz not null default now(),
  foreign key (business_id, customer_id)
    references public.customers(business_id, id) on delete cascade
);

create table if not exists public.customer_intelligence_queue (
  business_id uuid not null,
  customer_id text not null,
  requested_at timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text,
  primary key (business_id, customer_id),
  foreign key (business_id, customer_id)
    references public.customers(business_id, id) on delete cascade
);

create index if not exists customer_segments_business_segment_idx
  on public.customer_segments (business_id, segment_code, risk_score desc);
create index if not exists customer_segments_business_value_idx
  on public.customer_segments (business_id, value_score desc);
create index if not exists customer_features_business_recency_idx
  on public.customer_features (business_id, days_since_last_visit desc);
create index if not exists customer_segment_history_customer_idx
  on public.customer_segment_history (business_id, customer_id, changed_at desc);

alter table public.business_intelligence_baselines enable row level security;
alter table public.customer_features enable row level security;
alter table public.customer_segments enable row level security;
alter table public.customer_segment_history enable row level security;
alter table public.customer_intelligence_queue enable row level security;

drop policy if exists "members read intelligence baselines" on public.business_intelligence_baselines;
create policy "members read intelligence baselines"
  on public.business_intelligence_baselines for select to authenticated
  using (business_id in (
    select business_id from public.business_members where user_id = auth.uid()
  ));

drop policy if exists "members read customer features" on public.customer_features;
create policy "members read customer features"
  on public.customer_features for select to authenticated
  using (business_id in (
    select business_id from public.business_members where user_id = auth.uid()
  ));

drop policy if exists "members read customer segments" on public.customer_segments;
create policy "members read customer segments"
  on public.customer_segments for select to authenticated
  using (business_id in (
    select business_id from public.business_members where user_id = auth.uid()
  ));

drop policy if exists "members read segment history" on public.customer_segment_history;
create policy "members read segment history"
  on public.customer_segment_history for select to authenticated
  using (business_id in (
    select business_id from public.business_members where user_id = auth.uid()
  ));

revoke all on public.customer_intelligence_queue from anon, authenticated;
revoke insert, update, delete on public.business_intelligence_baselines from anon, authenticated;
revoke insert, update, delete on public.customer_features from anon, authenticated;
revoke insert, update, delete on public.customer_segments from anon, authenticated;
revoke insert, update, delete on public.customer_segment_history from anon, authenticated;

create or replace function public.refresh_customer_intelligence(
  p_business_id uuid,
  p_customer_id text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target record;
  stats record;
  baseline_interval numeric := 30;
  business_median_90 numeric := 1;
  business_p75_90 numeric := 2;
  business_max_spend bigint := 0;
  personal_weight numeric;
  expected_interval numeric;
  computed_delay numeric;
  computed_risk numeric;
  computed_value numeric;
  next_segment text;
  old_segment text;
  reasons text[];
  explanation_text text;
  business_customer_count integer := 0;
begin
  if auth.uid() is not null and not exists (
    select 1 from public.business_members
    where business_id = p_business_id and user_id = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  if p_customer_id is null then
    for target in
      select id from public.customers
      where business_id = p_business_id and deleted_at is null
    loop
      perform public.refresh_customer_intelligence(p_business_id, target.id);
    end loop;

    select
      coalesce(percentile_cont(0.5) within group (
        order by median_visit_interval_days
      ) filter (where median_visit_interval_days is not null), 30),
      coalesce(percentile_cont(0.5) within group (order by visits_90d), 1),
      coalesce(percentile_cont(0.75) within group (order by visits_90d), 2),
      coalesce(max(spend_90d_minor), 0),
      count(*)
    into baseline_interval, business_median_90, business_p75_90,
      business_max_spend, business_customer_count
    from public.customer_features
    where business_id = p_business_id;

    insert into public.business_intelligence_baselines (
      business_id, median_visit_interval_days, median_visits_90d,
      p75_visits_90d, max_spend_90d, customer_count, updated_at
    ) values (
      p_business_id, baseline_interval, business_median_90,
      business_p75_90, business_max_spend, business_customer_count, now()
    ) on conflict (business_id) do update set
      median_visit_interval_days = excluded.median_visit_interval_days,
      median_visits_90d = excluded.median_visits_90d,
      p75_visits_90d = excluded.p75_visits_90d,
      max_spend_90d = excluded.max_spend_90d,
      customer_count = excluded.customer_count,
      updated_at = now();

    -- La primera pasada crea la línea base; la segunda reclasifica con esa
    -- referencia real del negocio en vez del valor conservador inicial.
    for target in
      select id from public.customers
      where business_id = p_business_id and deleted_at is null
    loop
      perform public.refresh_customer_intelligence(p_business_id, target.id);
    end loop;
    return;
  end if;

  select * into target from public.customers
  where business_id = p_business_id and id = p_customer_id and deleted_at is null;
  if not found then return; end if;

  select coalesce(median_visit_interval_days, 30),
         coalesce(median_visits_90d, 1), coalesce(p75_visits_90d, 2),
         coalesce(max_spend_90d, 0)
  into baseline_interval, business_median_90, business_p75_90, business_max_spend
  from public.business_intelligence_baselines where business_id = p_business_id;
  baseline_interval := coalesce(baseline_interval, 30);
  business_median_90 := coalesce(business_median_90, 1);
  business_p75_90 := coalesce(business_p75_90, 2);
  business_max_spend := coalesce(business_max_spend, 0);

  with real_events as (
    select created_at, amount_minor,
      lag(created_at) over (order by created_at) as previous_at
    from public.loyalty_events
    where business_id = p_business_id and customer_id = p_customer_id
      and event_type in ('visit', 'purchase', 'stamp_added', 'points_added')
  ), intervals as (
    select extract(epoch from (created_at - previous_at)) / 86400.0 as days
    from real_events where previous_at is not null
  )
  select
    min(e.created_at) as first_visit_at,
    max(e.created_at) as last_visit_at,
    greatest(count(e.created_at)::integer, target.visits) as total_visits,
    count(*) filter (where e.amount_minor > 0)::integer as total_transactions,
    coalesce(sum(e.amount_minor), 0)::bigint as total_spend_minor,
    coalesce(avg(e.amount_minor) filter (where e.amount_minor > 0), 0)::bigint as average_ticket_minor,
    count(*) filter (where e.created_at >= now() - interval '7 days')::integer as visits_7d,
    count(*) filter (where e.created_at >= now() - interval '30 days')::integer as visits_30d,
    count(*) filter (where e.created_at >= now() - interval '60 days')::integer as visits_60d,
    count(*) filter (where e.created_at >= now() - interval '90 days')::integer as visits_90d,
    coalesce(sum(e.amount_minor) filter (where e.created_at >= now() - interval '30 days'), 0)::bigint as spend_30d,
    coalesce(sum(e.amount_minor) filter (where e.created_at >= now() - interval '90 days'), 0)::bigint as spend_90d,
    (select avg(days) from intervals) as average_interval,
    (select percentile_cont(0.5) within group (order by days) from intervals) as median_interval,
    (select stddev_pop(days) from intervals) as stddev_interval,
    count(*) filter (where e.created_at >= now() - interval '30 days')::numeric as recent_count,
    count(*) filter (
      where e.created_at >= now() - interval '60 days'
        and e.created_at < now() - interval '30 days'
    )::numeric as previous_count,
    coalesce(sum(e.amount_minor) filter (
      where e.created_at >= now() - interval '60 days'
        and e.created_at < now() - interval '30 days'
    ), 0)::bigint as previous_spend
  into stats from real_events e;

  stats.first_visit_at := coalesce(stats.first_visit_at, target.joined_at);
  stats.last_visit_at := coalesce(stats.last_visit_at, target.last_activity_at);
  personal_weight := least(greatest((stats.total_visits - 2)::numeric / 8, 0), 0.85);
  expected_interval := round((
    coalesce(stats.median_interval, baseline_interval) * personal_weight +
    baseline_interval * (1 - personal_weight)
  )::numeric, 2);
  computed_delay := case when stats.last_visit_at is null then null else
    round((extract(epoch from (now() - stats.last_visit_at)) / 86400.0 /
      greatest(expected_interval, 1))::numeric, 3) end;

  computed_risk := least(1, greatest(0,
    coalesce((computed_delay - 0.75) / 2.5, 0) * 0.60 +
    case when stats.previous_count > 0
      then greatest(0, (stats.previous_count - stats.recent_count) / stats.previous_count)
      else 0 end * 0.25 +
    case when stats.recent_count < stats.previous_count then 0.15 else 0 end
  ));
  computed_value := least(1, greatest(0,
    least(stats.visits_90d::numeric / greatest(business_p75_90, 1), 1) * 0.55 +
    case when business_max_spend > 0
      then least(stats.spend_90d::numeric / business_max_spend, 1) else 0 end * 0.45
  ));

  select segment_code into old_segment from public.customer_segments
  where business_id = p_business_id and customer_id = p_customer_id;

  if stats.total_visits <= 2 or now() - target.joined_at <= interval '14 days' then
    next_segment := 'NEW';
  elsif old_segment in ('AT_RISK', 'INACTIVE')
      and stats.last_visit_at >= now() - interval '7 days'
      and coalesce(computed_delay, 0) <= 1.25 then
    next_segment := 'RECOVERED';
  elsif coalesce(computed_delay, 0) >= 3 or computed_risk >= 0.85 then
    next_segment := 'INACTIVE';
  elsif coalesce(computed_delay, 0) >= 1.8 or computed_risk >= 0.65 then
    next_segment := 'AT_RISK';
  elsif stats.visits_90d >= business_p75_90 and coalesce(computed_delay, 0) <= 1.25 then
    next_segment := 'FREQUENT';
  elsif stats.visits_90d < business_median_90 then
    next_segment := 'OCCASIONAL';
  else
    next_segment := 'REGULAR';
  end if;

  reasons := array_remove(array[
    case when computed_delay >= 3 then 'VERY_LATE' end,
    case when computed_delay >= 1.8 and computed_delay < 3 then 'LATE' end,
    case when stats.recent_count < stats.previous_count then 'FREQUENCY_DOWN' end,
    case when stats.recent_count > stats.previous_count then 'FREQUENCY_UP' end,
    case when stats.spend_30d < stats.previous_spend then 'SPEND_DOWN' end,
    case when stats.visits_90d >= business_p75_90 then 'HIGH_FREQUENCY' end,
    case when stats.total_visits <= 2 then 'LIMITED_HISTORY' end
  ], null);
  explanation_text := case next_segment
    when 'NEW' then 'Todavía está construyendo su historial.'
    when 'FREQUENT' then 'Visita más seguido que la mayoría.'
    when 'REGULAR' then 'Mantiene una frecuencia estable.'
    when 'OCCASIONAL' then 'Visita con menor frecuencia, dentro de su ritmo.'
    when 'AT_RISK' then 'Está demorando más de lo habitual en volver.'
    when 'INACTIVE' then 'Superó ampliamente su intervalo habitual.'
    when 'RECOVERED' then 'Volvió después de un periodo de riesgo.'
  end;

  insert into public.customer_features (
    business_id, customer_id, first_visit_at, last_visit_at, total_visits,
    total_transactions, total_spend_minor, average_ticket_minor,
    customer_age_days, days_since_last_visit, visits_7d, visits_30d,
    visits_60d, visits_90d, spend_30d_minor, spend_90d_minor,
    average_visit_interval_days, median_visit_interval_days,
    visit_interval_stddev_days, expected_visit_interval_days,
    expected_next_visit_at, delay_ratio, historical_frequency,
    recent_frequency, frequency_change, visit_trend, spend_trend,
    recency_score, frequency_score, monetary_score, rfm_score, updated_at
  ) values (
    p_business_id, p_customer_id, stats.first_visit_at, stats.last_visit_at,
    stats.total_visits, stats.total_transactions, stats.total_spend_minor,
    stats.average_ticket_minor,
    greatest(0, floor(extract(epoch from (now() - target.joined_at)) / 86400))::integer,
    case when stats.last_visit_at is null then null else
      greatest(0, floor(extract(epoch from (now() - stats.last_visit_at)) / 86400))::integer end,
    stats.visits_7d, stats.visits_30d, stats.visits_60d, stats.visits_90d,
    stats.spend_30d, stats.spend_90d, stats.average_interval,
    stats.median_interval, stats.stddev_interval, expected_interval,
    stats.last_visit_at + make_interval(days => expected_interval::integer),
    computed_delay,
    stats.total_visits::numeric / greatest(
      extract(epoch from (now() - stats.first_visit_at)) / 2592000.0, 1
    ),
    stats.recent_count,
    case when stats.previous_count > 0
      then (stats.recent_count - stats.previous_count) / stats.previous_count
      else case when stats.recent_count > 0 then 1 else 0 end end,
    case when stats.recent_count > stats.previous_count * 1.2 then 'growing'
      when stats.recent_count < stats.previous_count * 0.8 then 'declining'
      else 'stable' end,
    case when stats.spend_30d > stats.previous_spend * 1.2 then 'growing'
      when stats.spend_30d < stats.previous_spend * 0.8 then 'declining'
      else 'stable' end,
    1 - computed_risk,
    least(stats.visits_90d::numeric / greatest(business_p75_90, 1), 1),
    case when business_max_spend > 0
      then least(stats.spend_90d::numeric / business_max_spend, 1) else 0 end,
    ((1 - computed_risk) + computed_value * 2) / 3,
    now()
  ) on conflict (business_id, customer_id) do update set
    first_visit_at = excluded.first_visit_at,
    last_visit_at = excluded.last_visit_at,
    total_visits = excluded.total_visits,
    total_transactions = excluded.total_transactions,
    total_spend_minor = excluded.total_spend_minor,
    average_ticket_minor = excluded.average_ticket_minor,
    customer_age_days = excluded.customer_age_days,
    days_since_last_visit = excluded.days_since_last_visit,
    visits_7d = excluded.visits_7d,
    visits_30d = excluded.visits_30d,
    visits_60d = excluded.visits_60d,
    visits_90d = excluded.visits_90d,
    spend_30d_minor = excluded.spend_30d_minor,
    spend_90d_minor = excluded.spend_90d_minor,
    average_visit_interval_days = excluded.average_visit_interval_days,
    median_visit_interval_days = excluded.median_visit_interval_days,
    visit_interval_stddev_days = excluded.visit_interval_stddev_days,
    expected_visit_interval_days = excluded.expected_visit_interval_days,
    expected_next_visit_at = excluded.expected_next_visit_at,
    delay_ratio = excluded.delay_ratio,
    historical_frequency = excluded.historical_frequency,
    recent_frequency = excluded.recent_frequency,
    frequency_change = excluded.frequency_change,
    visit_trend = excluded.visit_trend,
    spend_trend = excluded.spend_trend,
    recency_score = excluded.recency_score,
    frequency_score = excluded.frequency_score,
    monetary_score = excluded.monetary_score,
    rfm_score = excluded.rfm_score,
    updated_at = now();

  if old_segment is distinct from next_segment then
    insert into public.customer_segment_history (
      business_id, customer_id, previous_segment, new_segment,
      reason, scores_snapshot
    ) values (
      p_business_id, p_customer_id, old_segment, next_segment,
      explanation_text,
      jsonb_build_object('risk', computed_risk, 'value', computed_value,
        'delay_ratio', computed_delay, 'reasons', reasons)
    );
  end if;

  insert into public.customer_segments (
    business_id, customer_id, segment_code, previous_segment,
    risk_score, value_score, reason_codes, explanation,
    expected_next_visit_at, last_evaluated_at
  ) values (
    p_business_id, p_customer_id, next_segment, old_segment,
    computed_risk, computed_value, reasons, explanation_text,
    stats.last_visit_at + make_interval(days => expected_interval::integer), now()
  ) on conflict (business_id, customer_id) do update set
    segment_code = excluded.segment_code,
    previous_segment = case
      when customer_segments.segment_code is distinct from excluded.segment_code
      then customer_segments.segment_code else customer_segments.previous_segment end,
    risk_score = excluded.risk_score,
    value_score = excluded.value_score,
    reason_codes = excluded.reason_codes,
    explanation = excluded.explanation,
    expected_next_visit_at = excluded.expected_next_visit_at,
    last_evaluated_at = now();
end;
$$;

revoke all on function public.refresh_customer_intelligence(uuid, text) from public, anon;
grant execute on function public.refresh_customer_intelligence(uuid, text) to authenticated, service_role;

create or replace function public.queue_customer_intelligence_refresh()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  business uuid;
  customer text;
begin
  if tg_table_name = 'loyalty_events' then
    if tg_op = 'DELETE' then
      business := old.business_id;
      customer := old.customer_id;
    else
      business := new.business_id;
      customer := new.customer_id;
    end if;
  else
    if tg_op = 'DELETE' then
      business := old.business_id;
      customer := old.id;
    else
      business := new.business_id;
      customer := new.id;
    end if;
  end if;
  if business is not null and customer is not null and exists (
    select 1 from public.customers c
    where c.business_id = business and c.id = customer and c.deleted_at is null
  ) then
    insert into public.customer_intelligence_queue (business_id, customer_id, requested_at)
    values (business, customer, now())
    on conflict (business_id, customer_id) do update
      set requested_at = now(), last_error = null;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists queue_intelligence_from_events on public.loyalty_events;
create trigger queue_intelligence_from_events
after insert or update or delete on public.loyalty_events
for each row execute function public.queue_customer_intelligence_refresh();

drop trigger if exists queue_intelligence_from_customers on public.customers;
create trigger queue_intelligence_from_customers
after insert or update of visits, points, stamps, last_activity_at, deleted_at
on public.customers for each row
execute function public.queue_customer_intelligence_refresh();

create or replace function public.process_customer_intelligence_queue(p_batch_size integer default 100)
returns integer language plpgsql security definer set search_path = public as $$
declare
  item record;
  processed integer := 0;
begin
  for item in
    select business_id, customer_id
    from public.customer_intelligence_queue
    order by requested_at
    limit greatest(1, least(p_batch_size, 1000))
    for update skip locked
  loop
    begin
      perform public.refresh_customer_intelligence(item.business_id, item.customer_id);
      delete from public.customer_intelligence_queue
      where business_id = item.business_id and customer_id = item.customer_id;
      processed := processed + 1;
    exception when others then
      update public.customer_intelligence_queue
      set attempts = attempts + 1, last_error = sqlerrm, requested_at = now()
      where business_id = item.business_id and customer_id = item.customer_id;
    end;
  end loop;
  return processed;
end;
$$;

revoke all on function public.process_customer_intelligence_queue(integer) from public, anon, authenticated;
grant execute on function public.process_customer_intelligence_queue(integer) to service_role;

insert into public.customer_intelligence_queue (business_id, customer_id)
select business_id, id from public.customers where deleted_at is null
on conflict (business_id, customer_id) do update set requested_at = now();

do $$
begin
  begin
    create extension if not exists pg_cron with schema extensions;
  exception when insufficient_privilege then
    raise notice 'pg_cron no disponible; configure los jobs desde Supabase Cron.';
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'fideli-customer-intelligence-queue', '* * * * *',
      'select public.process_customer_intelligence_queue(200)'
    );
    perform cron.schedule(
      'fideli-customer-intelligence-daily', '17 4 * * *',
      'select public.refresh_customer_intelligence(id, null) from public.businesses'
    );
  end if;
end
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array['customer_features', 'customer_segments'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end
$$;

alter table public.customer_features replica identity full;
alter table public.customer_segments replica identity full;

comment on table public.customer_features is
  'Features deterministas por business_id + customer_id; nunca mezcla comercios.';
comment on table public.customer_segments is
  'Segmento actual explicable y utilizable como audiencia dinámica de campañas.';
