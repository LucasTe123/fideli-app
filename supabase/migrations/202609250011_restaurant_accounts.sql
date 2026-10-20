create extension if not exists citext;

-- Las cuentas que usan Fideli son distintas de los clientes que reciben
-- tarjetas Wallet. La contraseña permanece exclusivamente en Supabase Auth.
create table if not exists public.restaurant_accounts (
  id uuid primary key references auth.users(id) on delete cascade,
  email citext not null unique,
  restaurant_name text not null check (char_length(trim(restaurant_name)) between 2 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.restaurant_accounts enable row level security;

drop policy if exists "restaurant owners read own account" on public.restaurant_accounts;
create policy "restaurant owners read own account"
  on public.restaurant_accounts
  for select
  to authenticated
  using (id = auth.uid());

drop policy if exists "restaurant owners update own account" on public.restaurant_accounts;
create policy "restaurant owners update own account"
  on public.restaurant_accounts
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

revoke all on public.restaurant_accounts from anon;
grant select, update on public.restaurant_accounts to authenticated;

create or replace function public.sync_restaurant_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_name text;
begin
  if new.email is null or coalesce(new.is_anonymous, false) then
    return new;
  end if;

  account_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'restaurant_name'), ''),
    split_part(new.email, '@', 1)
  );

  insert into public.restaurant_accounts (id, email, restaurant_name, updated_at)
  values (new.id, lower(new.email), account_name, now())
  on conflict (id) do update
    set email = excluded.email,
        restaurant_name = excluded.restaurant_name,
        updated_at = now();

  insert into public.businesses (id, owner_id, name, updated_at)
  values (new.id, new.id, account_name, now())
  on conflict (id) do update
    set owner_id = excluded.owner_id,
        name = case
          when trim(public.businesses.name) in ('', 'Fideli') then excluded.name
          else public.businesses.name
        end,
        updated_at = now();

  insert into public.business_members (business_id, user_id, role)
  values (new.id, new.id, 'owner')
  on conflict (business_id, user_id) do update set role = 'owner';

  return new;
end;
$$;

revoke all on function public.sync_restaurant_account() from public;

drop trigger if exists sync_restaurant_account_after_auth_change on auth.users;
create trigger sync_restaurant_account_after_auth_change
  after insert or update of email, raw_user_meta_data, is_anonymous
  on auth.users
  for each row execute function public.sync_restaurant_account();

-- Incluye cualquier cuenta permanente creada antes de esta migración.
insert into public.restaurant_accounts (id, email, restaurant_name)
select
  id,
  lower(email),
  coalesce(
    nullif(trim(raw_user_meta_data ->> 'restaurant_name'), ''),
    split_part(email, '@', 1)
  )
from auth.users
where email is not null and not coalesce(is_anonymous, false)
on conflict (id) do nothing;

