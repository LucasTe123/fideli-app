-- Historial operativo por cliente y canjes idempotentes.

alter table public.loyalty_events drop constraint if exists loyalty_events_event_type_check;
alter table public.loyalty_events add constraint loyalty_events_event_type_check
  check (event_type in (
    'visit', 'purchase', 'stamp_added', 'points_added', 'reward_redeemed',
    'campaign_sent', 'qr_scan', 'referral', 'wallet_pass_created',
    'wallet_pass_updated', 'adjustment', 'other'
  ));

create table if not exists public.customer_reward_redemptions (
  business_id uuid not null references public.businesses(id) on delete cascade,
  customer_id text not null,
  reward_id text not null,
  program_id text not null,
  reward_name text not null,
  event_id text not null unique,
  redeemed_at timestamptz not null default now(),
  primary key (business_id, customer_id, reward_id),
  foreign key (business_id, customer_id)
    references public.customers(business_id, id) on delete cascade
);

create index if not exists customer_reward_redemptions_timeline_idx
  on public.customer_reward_redemptions (business_id, customer_id, redeemed_at desc);

alter table public.customer_reward_redemptions enable row level security;

drop policy if exists "members read reward redemptions" on public.customer_reward_redemptions;
create policy "members read reward redemptions"
  on public.customer_reward_redemptions for select
  using (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  );

create or replace function public.redeem_customer_reward(
  p_business_id uuid,
  p_customer_id text,
  p_reward_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reward jsonb;
  v_customer public.customers%rowtype;
  v_program_id text;
  v_reward_name text;
  v_points_cost integer;
  v_stamps_cost integer;
  v_points integer;
  v_stamps integer;
  v_next_points integer;
  v_next_stamps integer;
  v_event_id text := 'reward-redemption-' || gen_random_uuid()::text;
  v_intermediate boolean := false;
  v_balances jsonb;
begin
  select payload into v_reward
  from public.module_records
  where business_id = p_business_id
    and module_type = 'reward'
    and record_id = p_reward_id
  limit 1;

  if v_reward is null or coalesce((v_reward->>'active')::boolean, true) is false then
    return jsonb_build_object('ok', false, 'code', 'reward_not_found', 'message', 'Recompensa no encontrada');
  end if;

  v_program_id := coalesce(v_reward->>'programId', '');
  v_reward_name := coalesce(nullif(v_reward->>'name', ''), 'Recompensa');
  v_points_cost := greatest(0, coalesce((v_reward->>'pointsCost')::integer, 0));
  v_stamps_cost := greatest(0, coalesce((v_reward->>'stampsCost')::integer, 0));

  if v_program_id = '' then
    return jsonb_build_object('ok', false, 'code', 'program_not_found', 'message', 'La recompensa no está vinculada a una tarjeta');
  end if;

  select * into v_customer
  from public.customers
  where business_id = p_business_id and id = p_customer_id and deleted_at is null
  for update;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'customer_not_found', 'message', 'Cliente no encontrado');
  end if;

  if exists (
    select 1 from public.customer_reward_redemptions
    where business_id = p_business_id
      and customer_id = p_customer_id
      and reward_id = p_reward_id
  ) then
    return jsonb_build_object('ok', false, 'code', 'already_redeemed', 'message', 'Esta recompensa ya fue cobrada');
  end if;

  v_balances := coalesce(v_customer.card_balances, '{}'::jsonb);
  v_points := coalesce((v_balances->v_program_id->>'points')::integer, 0);
  v_stamps := coalesce((v_balances->v_program_id->>'stamps')::integer, 0);

  if v_points < v_points_cost or v_stamps < v_stamps_cost then
    return jsonb_build_object('ok', false, 'code', 'not_available', 'message', 'La recompensa todavía no está disponible');
  end if;

  select exists (
    select 1
    from public.loyalty_cards card,
      jsonb_array_elements(coalesce(card.reward_milestones, '[]'::jsonb)) milestone
    where card.business_id = p_business_id
      and card.id = v_program_id
      and milestone->>'id' = p_reward_id
      and coalesce((milestone->>'stamp')::integer, card.goal) < card.goal
  ) into v_intermediate;

  v_next_points := case when v_intermediate then v_points else v_points - v_points_cost end;
  v_next_stamps := case when v_intermediate then v_stamps else v_stamps - v_stamps_cost end;

  insert into public.customer_reward_redemptions (
    business_id, customer_id, reward_id, program_id, reward_name, event_id
  ) values (
    p_business_id, p_customer_id, p_reward_id, v_program_id, v_reward_name, v_event_id
  );

  if not v_intermediate then
    v_balances := jsonb_set(v_balances, array[v_program_id, 'points'], to_jsonb(v_next_points), true);
    v_balances := jsonb_set(v_balances, array[v_program_id, 'stamps'], to_jsonb(v_next_stamps), true);
    update public.customers
    set card_balances = v_balances,
        points = greatest(0, points - v_points_cost),
        stamps = greatest(0, stamps - v_stamps_cost),
        updated_at = now()
    where business_id = p_business_id and id = p_customer_id;
  end if;

  insert into public.loyalty_events (
    id, business_id, customer_id, description, points_delta, event_type,
    program_id, metadata, created_at
  ) values (
    v_event_id, p_business_id, p_customer_id, 'Recompensa cobrada: ' || v_reward_name,
    case when v_intermediate then 0 else -v_points_cost end,
    'reward_redeemed', v_program_id,
    jsonb_build_object(
      'reward_id', p_reward_id,
      'reward_name', v_reward_name,
      'intermediate', v_intermediate
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'redeemed',
    'message', 'Recompensa cobrada correctamente',
    'eventId', v_event_id,
    'programId', v_program_id,
    'points', v_next_points,
    'stamps', v_next_stamps
  );
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'already_redeemed', 'message', 'Esta recompensa ya fue cobrada');
end;
$$;

revoke all on function public.redeem_customer_reward(uuid, text, text) from public;
grant execute on function public.redeem_customer_reward(uuid, text, text) to service_role;
