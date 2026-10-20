do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'loyalty_cards'
  ) then
    alter publication supabase_realtime add table public.loyalty_cards;
  end if;
end
$$;

-- Incluye business_id también en actualizaciones y eliminaciones para que el
-- filtro por comercio funcione en todos los dispositivos conectados.
alter table public.loyalty_cards replica identity full;
