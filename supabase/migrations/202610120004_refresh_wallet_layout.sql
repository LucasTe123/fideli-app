-- Make every installed Apple pass advertise the corrected layout revision.
-- Wallet will fetch the newly generated package on its next update check.
update public.wallet_passes
set update_tag = ((extract(epoch from clock_timestamp()) * 1000)::bigint),
    updated_at = now();
