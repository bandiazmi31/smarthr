-- A clock-in uploads the selfie before calling clock_in(), because a stored photo
-- with no log is recoverable while a log pointing at nothing is not. When the
-- call is then refused (outside the geofence, already clocked in, wrong shift)
-- the API deletes the upload again -- but staff have no delete grant, so that
-- cleanup was failing silently and leaving orphans behind.
--
-- This lets an employee delete only an object in their own folder that no
-- attendance log references, which is exactly the orphan case. A selfie that has
-- been recorded stays untouchable.
create or replace function app_private.photo_is_referenced(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.attendance_logs
    where clock_in_photo_path = p_name or clock_out_photo_path = p_name
  );
$$;

revoke all on function app_private.photo_is_referenced(text) from public, anon;
grant execute on function app_private.photo_is_referenced(text) to authenticated;

create policy "attendance_photos_remove_orphan" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'attendance-photos'
    and (storage.foldername(name))[1] = app_private.current_employee_id()::text
    and not app_private.photo_is_referenced(name)
  );
