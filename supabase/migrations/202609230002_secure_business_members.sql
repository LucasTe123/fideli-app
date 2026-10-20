-- Prevent an authenticated user from adding themselves to an unrelated
-- business. Owners and managers may manage staff; a new owner may only add
-- their own initial membership to a business they own.

create or replace function public.is_business_admin(target_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.businesses
      where id = target_business_id
        and owner_id = auth.uid()
    )
    or exists (
      select 1
      from public.business_members
      where business_id = target_business_id
        and user_id = auth.uid()
        and role in ('owner', 'manager')
    );
$$;

revoke all on function public.is_business_admin(uuid) from public;
grant execute on function public.is_business_admin(uuid) to authenticated;

drop policy if exists "users manage own membership" on public.business_members;

create policy "members read business memberships" on public.business_members
  for select
  using (
    user_id = auth.uid()
    or public.is_business_admin(business_id)
  );

create policy "owners and managers add memberships" on public.business_members
  for insert
  with check (
    public.is_business_admin(business_id)
  );

create policy "owners and managers update memberships" on public.business_members
  for update
  using (public.is_business_admin(business_id))
  with check (public.is_business_admin(business_id));

create policy "owners and managers remove memberships" on public.business_members
  for delete
  using (public.is_business_admin(business_id));

create policy "members read their business" on public.businesses
  for select
  using (
    id in (
      select business_id
      from public.business_members
      where user_id = auth.uid()
    )
  );
