update public.app_snapshots
set payload = jsonb_set(
  payload,
  '{wallet,cardTemplates}',
  coalesce(payload #> '{wallet,cardTemplates}', '{}'::jsonb) - 'event',
  true
)
where coalesce(payload #> '{wallet,cardTemplates}', '{}'::jsonb) ? 'event';

