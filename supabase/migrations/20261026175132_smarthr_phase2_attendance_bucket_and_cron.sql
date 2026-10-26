-- Private bucket for clock-in/out selfies. Path is <employee_id>/<file>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attendance-photos', 'attendance-photos', false, 3145728, array['image/jpeg', 'image/png'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Staff may only write into their own folder, and never overwrite: an uploaded
-- selfie is evidence, so there is no update policy and no delete for employees.
create policy "attendance_photos_write_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'attendance-photos'
    and (storage.foldername(name))[1] = app_private.current_employee_id()::text
  );

create policy "attendance_photos_read_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attendance-photos'
    and (storage.foldername(name))[1] = app_private.current_employee_id()::text
  );

create policy "attendance_photos_read_hr" on storage.objects
  for select to authenticated
  using (bucket_id = 'attendance-photos' and app_private.is_hr_staff());

create policy "attendance_photos_read_hod" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'attendance-photos'
    and app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id::text = (storage.foldername(name))[1]
        and e.department_id = app_private.current_department_id()
    )
  );

create policy "attendance_photos_remove_hr" on storage.objects
  for delete to authenticated
  using (bucket_id = 'attendance-photos' and app_private.is_hr_staff());

-- Backoffice auto-roster: Monday-Friday for every employee carrying an
-- auto_schedule_shift_id. Idempotent, so a re-run or a manual entry wins.
-- NOTE: superseded by 20261026181125, which replaces the ON CONFLICT arbiter.
create or replace function public.generate_backoffice_rosters(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tz text;
  week_start date;
  created integer;
begin
  select timezone into tz from public.hotel_settings where id;
  tz := coalesce(tz, 'UTC');

  -- Default: the Monday of the coming week, in the hotel's own timezone.
  week_start := coalesce(
    p_week_start,
    (date_trunc('week', ((now() at time zone tz)::date + 7)::timestamp))::date
  );

  insert into public.rosters (employee_id, shift_id, shift_date, expected_clock_in, expected_clock_out, note)
  select
    e.id,
    e.auto_schedule_shift_id,
    week_start + offset_days,
    now(),  -- overwritten by the rosters_apply_window trigger
    now(),
    'Auto-generated backoffice schedule'
  from public.employees e
  cross join generate_series(0, 4) as offset_days
  where e.is_active
    and e.auto_schedule_shift_id is not null
  on conflict (employee_id, shift_date) do nothing;

  get diagnostics created = row_count;
  return created;
end;
$$;

comment on function public.generate_backoffice_rosters(date) is 'Creates Mon-Fri rosters for auto-scheduled staff. Defaults to next week. Idempotent.';

revoke all on function public.generate_backoffice_rosters(date) from public, anon;
grant execute on function public.generate_backoffice_rosters(date) to authenticated;

create extension if not exists pg_cron with schema pg_cron;

-- Sunday 00:00 Asia/Jakarta is Saturday 17:00 UTC, which is when pg_cron ticks.
select cron.schedule(
  'smarthr-backoffice-roster',
  '0 17 * * 6',
  $cron$ select public.generate_backoffice_rosters(); $cron$
);
