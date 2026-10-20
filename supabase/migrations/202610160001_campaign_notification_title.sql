-- Keep the optional notification title in every campaign payload. Older app
-- builds omitted the property and could otherwise erase a title saved by a
-- newer build during their next full snapshot sync.
create or replace function public.preserve_campaign_notification_title()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.module_type = 'campaign' then
    if not (new.payload ? 'notificationTitle') then
      new.payload = new.payload || jsonb_build_object(
        'notificationTitle',
        case
          when tg_op = 'UPDATE' then coalesce(old.payload->>'notificationTitle', '')
          else ''
        end
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_campaign_notification_title
on public.module_records;

create trigger preserve_campaign_notification_title
before insert or update of payload on public.module_records
for each row
execute function public.preserve_campaign_notification_title();

update public.module_records
set payload = payload || jsonb_build_object(
  'notificationTitle',
  coalesce(payload->>'notificationTitle', '')
)
where module_type = 'campaign';
