-- Enables the 90-day selfie retention job (PRD v2.0, Storage).
--
-- Why this is not a plain pg_cron job: deleting a row from storage.objects
-- removes only the metadata and leaves the file in the bucket, so the space is
-- never reclaimed. Reclaiming it requires the Storage API, which requires the
-- service-role key -- so the work happens in the `purge-attendance-photos` Edge
-- Function, where Supabase injects that key itself. It is never stored in this
-- repo, in .env, or anywhere the Astro app can reach.
--
-- BEFORE RUNNING
--   1. Set the function secret (Dashboard -> Edge Functions -> purge-attendance-photos
--      -> Secrets, or `supabase secrets set PURGE_SECRET=...`). Use a long random
--      value; the function refuses every request until it is set.
--   2. Replace <PURGE_SECRET> below with that same value.
--
-- The secret is a low-privilege shared token: it only authorises "run the purge",
-- and grants no database access of its own.

create extension if not exists pg_net with schema extensions;

-- Store the invocation token in Vault rather than inlining it in the job
-- definition, which is world-readable via cron.job.
select vault.create_secret(
  '<PURGE_SECRET>',
  'smarthr_purge_secret',
  'Shared token authorising the attendance-photo retention Edge Function'
);

create or replace function public.run_attendance_photo_purge()
returns bigint
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  token text;
  request_id bigint;
begin
  select decrypted_secret into token
  from vault.decrypted_secrets
  where name = 'smarthr_purge_secret';

  if token is null then
    raise exception 'smarthr_purge_secret is not set in Vault; run scripts/enable-photo-retention.sql';
  end if;

  select net.http_post(
    url := 'https://dnobvrudkdtvdhynplny.supabase.co/functions/v1/purge-attendance-photos',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', token
    ),
    body := '{}'::jsonb
  ) into request_id;

  return request_id;
end;
$$;

revoke all on function public.run_attendance_photo_purge() from public, anon, authenticated;

-- Daily at 18:00 UTC = 01:00 Asia/Jakarta, outside every shift changeover.
select cron.schedule(
  'smarthr-purge-attendance-photos',
  '0 18 * * *',
  $cron$ select public.run_attendance_photo_purge(); $cron$
);

-- Verify:
--   select jobname, schedule, active from cron.job;
--   select public.run_attendance_photo_purge();              -- fire once by hand
--   select * from net._http_response order by created desc limit 1;
