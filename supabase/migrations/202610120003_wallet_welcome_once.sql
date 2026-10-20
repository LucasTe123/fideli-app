alter table public.wallet_passes
  add column if not exists welcome_sent_at timestamptz;

-- Existing installed passes have already completed their welcome flow.  This
-- prevents an old pass from receiving one more welcome after this migration.
update public.wallet_passes pass
set welcome_sent_at = coalesce(pass.welcome_sent_at, now())
where pass.welcome_sent_at is null
  and exists (
    select 1
    from public.wallet_registrations registration
    where registration.serial_number = pass.serial_number
  );
