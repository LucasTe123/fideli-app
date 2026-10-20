alter table public.businesses
  add column if not exists public_slug text;

create or replace function public.normalize_business_slug(source text)
returns text
language sql
immutable
strict
as $$
  select trim(both '-' from regexp_replace(
    lower(translate(source, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunAEIOUUN')),
    '[^a-z0-9]+',
    '-',
    'g'
  ));
$$;

create or replace function public.assign_business_public_slug()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_slug text;
  candidate text;
  suffix integer := 1;
begin
  if new.public_slug is not null and new.public_slug <> '' then
    new.public_slug := public.normalize_business_slug(new.public_slug);
    return new;
  end if;

  base_slug := public.normalize_business_slug(coalesce(new.name, 'negocio'));
  if base_slug = '' or base_slug in ('www', 'app', 'api', 'admin', 'fideli') then
    base_slug := 'negocio';
  end if;
  candidate := base_slug;

  while exists (
    select 1 from public.businesses
    where public_slug = candidate and id <> new.id
  ) loop
    suffix := suffix + 1;
    candidate := base_slug || '-' || suffix::text;
  end loop;

  new.public_slug := candidate;
  return new;
end;
$$;

drop trigger if exists businesses_assign_public_slug on public.businesses;
create trigger businesses_assign_public_slug
before insert on public.businesses
for each row execute function public.assign_business_public_slug();

do $$
declare
  business_row record;
  generated_slug text;
  suffix integer;
begin
  for business_row in
    select id, name from public.businesses
    where public_slug is null or public_slug = ''
    order by created_at, id
  loop
    generated_slug := public.normalize_business_slug(coalesce(business_row.name, 'negocio'));
    if generated_slug = '' or generated_slug in ('www', 'app', 'api', 'admin', 'fideli') then
      generated_slug := 'negocio';
    end if;
    suffix := 1;
    while exists (
      select 1 from public.businesses where public_slug = generated_slug
    ) loop
      suffix := suffix + 1;
      generated_slug := public.normalize_business_slug(coalesce(business_row.name, 'negocio')) || '-' || suffix::text;
    end loop;
    update public.businesses set public_slug = generated_slug where id = business_row.id;
  end loop;
end;
$$;

alter table public.businesses
  alter column public_slug set not null;

create unique index if not exists businesses_public_slug_unique_idx
  on public.businesses (public_slug);

alter table public.businesses
  drop constraint if exists businesses_public_slug_format;
alter table public.businesses
  add constraint businesses_public_slug_format
  check (public_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');
