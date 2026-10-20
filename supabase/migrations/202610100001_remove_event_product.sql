-- Remove the discontinued event-ticketing product without touching the
-- generic loyalty activity history used by stamps, points and memberships.

create temporary table removed_event_programs on commit drop as
select business_id, id
from public.loyalty_cards
where card_kind = 'Evento';

delete from public.wallet_registrations registration
using public.wallet_passes pass, removed_event_programs removed
where registration.serial_number = pass.serial_number
  and pass.business_id = removed.business_id
  and pass.card_id = removed.id;

delete from public.wallet_passes pass
using removed_event_programs removed
where pass.business_id = removed.business_id
  and pass.card_id = removed.id;

delete from public.loyalty_events activity
using removed_event_programs removed
where activity.business_id = removed.business_id
  and activity.program_id = removed.id;

delete from public.module_records module
using removed_event_programs removed
where module.business_id = removed.business_id
  and module.module_type = 'program'
  and module.record_id = removed.id;

update public.customers customer
set card_balances = coalesce(customer.card_balances, '{}'::jsonb) - array(
  select removed.id
  from removed_event_programs removed
  where removed.business_id = customer.business_id
)
where exists (
  select 1
  from removed_event_programs removed
  where removed.business_id = customer.business_id
    and coalesce(customer.card_balances, '{}'::jsonb) ? removed.id
);

update public.app_snapshots snapshot
set payload = jsonb_set(
  snapshot.payload - 'events',
  '{programs}',
  coalesce(
    (
      select jsonb_agg(program)
      from jsonb_array_elements(coalesce(snapshot.payload -> 'programs', '[]'::jsonb)) program
      where coalesce(program ->> 'cardKind', '') <> 'Evento'
    ),
    '[]'::jsonb
  ),
  true
)
where snapshot.payload ? 'events'
   or exists (
     select 1
     from jsonb_array_elements(coalesce(snapshot.payload -> 'programs', '[]'::jsonb)) program
     where coalesce(program ->> 'cardKind', '') = 'Evento'
   );

delete from public.loyalty_cards card
using removed_event_programs removed
where card.business_id = removed.business_id
  and card.id = removed.id;

drop function if exists public.redeem_event_ticket(uuid, uuid, text);
drop function if exists public.issue_event_ticket(uuid, text, text, text);
drop table if exists public.event_tickets;
drop table if exists public.event_listings;
