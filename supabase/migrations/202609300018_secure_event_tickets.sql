create table if not exists public.event_listings (
  id text not null,
  business_id uuid not null references public.businesses(id) on delete cascade,
  program_id text not null,
  name text not null,
  venue text not null default '',
  description text not null default '',
  starts_at timestamptz not null,
  image_path text,
  capacity integer not null default 100 check (capacity > 0),
  sold_count integer not null default 0 check (sold_count >= 0),
  price_minor integer not null default 0 check (price_minor >= 0),
  currency text not null default 'BOB',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id, id),
  foreign key (business_id, program_id)
    references public.loyalty_cards(business_id, id) on delete cascade,
  check (sold_count <= capacity)
);

create table if not exists public.event_tickets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  event_id text not null,
  attendee_name text not null,
  attendee_email text not null default '',
  token_hash text not null,
  status text not null default 'issued'
    check (status in ('issued', 'redeemed', 'cancelled')),
  issued_at timestamptz not null default now(),
  redeemed_at timestamptz,
  foreign key (business_id, event_id)
    references public.event_listings(business_id, id) on delete cascade
);

create unique index if not exists event_tickets_token_hash_idx
  on public.event_tickets(token_hash);
create index if not exists event_listings_program_idx
  on public.event_listings(business_id, program_id, starts_at);
create index if not exists event_tickets_event_idx
  on public.event_tickets(business_id, event_id, status);

alter table public.event_listings enable row level security;
alter table public.event_tickets enable row level security;

drop policy if exists "members manage event listings" on public.event_listings;
create policy "members manage event listings" on public.event_listings
  for all using (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  ) with check (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  );

drop policy if exists "members read event tickets" on public.event_tickets;
create policy "members read event tickets" on public.event_tickets
  for select using (
    business_id in (
      select business_id from public.business_members where user_id = auth.uid()
    )
  );

create or replace function public.issue_event_ticket(
  p_business_id uuid,
  p_event_id text,
  p_attendee_name text,
  p_attendee_email text default ''
)
returns table(ticket_id uuid, ticket_token text, remaining integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  selected_event public.event_listings%rowtype;
  raw_token text;
  created_ticket uuid;
begin
  select * into selected_event
  from public.event_listings
  where business_id = p_business_id
    and id = p_event_id
    and active = true
    and starts_at > now()
  for update;

  if not found then
    raise exception 'EVENT_NOT_AVAILABLE';
  end if;
  if selected_event.sold_count >= selected_event.capacity then
    raise exception 'EVENT_SOLD_OUT';
  end if;
  if char_length(trim(p_attendee_name)) < 2 then
    raise exception 'INVALID_ATTENDEE';
  end if;

  raw_token := encode(gen_random_bytes(16), 'hex');
  insert into public.event_tickets (
    business_id, event_id, attendee_name, attendee_email, token_hash
  ) values (
    p_business_id,
    p_event_id,
    left(trim(p_attendee_name), 120),
    left(lower(trim(p_attendee_email)), 160),
    encode(digest(raw_token, 'sha256'), 'hex')
  ) returning id into created_ticket;

  update public.event_listings
  set sold_count = sold_count + 1,
      updated_at = now()
  where business_id = p_business_id and id = p_event_id;

  return query select
    created_ticket,
    raw_token,
    selected_event.capacity - selected_event.sold_count - 1;
end;
$$;

create or replace function public.redeem_event_ticket(
  p_business_id uuid,
  p_ticket_id uuid,
  p_ticket_token text
)
returns table(valid boolean, result text, event_name text, attendee_name text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  selected_ticket public.event_tickets%rowtype;
  selected_event public.event_listings%rowtype;
begin
  select * into selected_ticket
  from public.event_tickets
  where id = p_ticket_id and business_id = p_business_id
  for update;

  if not found or selected_ticket.token_hash <> encode(digest(p_ticket_token, 'sha256'), 'hex') then
    return query select false, 'INVALID'::text, ''::text, ''::text;
    return;
  end if;

  select * into selected_event
  from public.event_listings
  where business_id = p_business_id and id = selected_ticket.event_id;

  if selected_ticket.status = 'redeemed' then
    return query select false, 'ALREADY_REDEEMED'::text,
      selected_event.name, selected_ticket.attendee_name;
    return;
  end if;
  if selected_ticket.status <> 'issued' or not selected_event.active then
    return query select false, 'CANCELLED'::text,
      selected_event.name, selected_ticket.attendee_name;
    return;
  end if;

  update public.event_tickets
  set status = 'redeemed', redeemed_at = now()
  where id = p_ticket_id;

  return query select true, 'REDEEMED'::text,
    selected_event.name, selected_ticket.attendee_name;
end;
$$;

revoke all on function public.issue_event_ticket(uuid, text, text, text)
  from public, anon, authenticated;
revoke all on function public.redeem_event_ticket(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.issue_event_ticket(uuid, text, text, text)
  to service_role;
grant execute on function public.redeem_event_ticket(uuid, uuid, text)
  to service_role;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'event_listings'
  ) then
    alter publication supabase_realtime add table public.event_listings;
  end if;
end
$$;

alter table public.event_listings replica identity full;
