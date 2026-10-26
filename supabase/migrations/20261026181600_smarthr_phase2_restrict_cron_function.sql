-- generate_backoffice_rosters is a scheduled job, not a user action. It writes
-- rosters for any department, so no signed-in user should be able to trigger it
-- over /rest/v1/rpc. pg_cron runs it as the owning role, which is unaffected
-- by this grant.
--
-- The other SECURITY DEFINER functions in public (clock_in, clock_out, and the
-- shift_swap workflow) are deliberately callable by `authenticated`: each one
-- authorises its own caller internally, which is precisely why the logic lives
-- in the database instead of the API layer.
revoke execute on function public.generate_backoffice_rosters(date) from authenticated;
