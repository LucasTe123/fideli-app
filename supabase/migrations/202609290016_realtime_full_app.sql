do $$
declare
  realtime_table text;
begin
  foreach realtime_table in array array[
    'customers',
    'module_records',
    'businesses'
  ]
  loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = realtime_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        realtime_table
      );
    end if;
  end loop;
end
$$;

-- Conserva las columnas de la fila anterior en cambios y eliminaciones para
-- que los filtros por negocio funcionen de forma consistente en Realtime.
alter table public.customers replica identity full;
alter table public.module_records replica identity full;
alter table public.businesses replica identity full;
