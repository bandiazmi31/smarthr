-- PRD v2.0 §1 (Storage): selfies are purged after 90 days to save space.
-- The log row itself is kept forever -- it is the attendance record -- but the
-- photo paths are cleared once the objects are gone, so nothing dangles.
alter table public.attendance_logs
  alter column clock_in_photo_path drop not null,
  add column photos_purged_at timestamptz;

comment on column public.attendance_logs.photos_purged_at is 'Set when the 90-day retention job removed this record''s selfies. The attendance times themselves are never purged.';

create index attendance_logs_purge_idx
  on public.attendance_logs (clock_in_time)
  where photos_purged_at is null;

-- How long selfies are kept, configurable like the other attendance policies.
alter table public.hotel_settings
  add column photo_retention_days integer not null default 90
    check (photo_retention_days between 1 and 3650);

comment on column public.hotel_settings.photo_retention_days is 'PRD v2.0: clock-in/out selfies are deleted this many days after the shift.';

-- The rows the retention job should act on. Reading this needs no privilege
-- beyond HR; only the deletion itself requires the Storage API.
create or replace function public.attendance_photos_to_purge(p_limit integer default 200)
returns table (
  id uuid,
  clock_in_photo_path text,
  clock_out_photo_path text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select a.id, a.clock_in_photo_path, a.clock_out_photo_path
  from public.attendance_logs a
  cross join public.hotel_settings cfg
  where a.photos_purged_at is null
    and a.clock_in_time < now() - make_interval(days => cfg.photo_retention_days)
    and (a.clock_in_photo_path is not null or a.clock_out_photo_path is not null)
  order by a.clock_in_time
  limit greatest(1, least(coalesce(p_limit, 200), 1000));
$$;

-- Called once the objects are actually gone from the bucket.
create or replace function public.mark_attendance_photos_purged(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  touched integer;
begin
  update public.attendance_logs
  set clock_in_photo_path = null,
      clock_out_photo_path = null,
      photos_purged_at = now()
  where id = any(p_ids) and photos_purged_at is null;

  get diagnostics touched = row_count;
  return touched;
end;
$$;

-- Maintenance only: no signed-in user calls these, the Edge Function does.
revoke all on function public.attendance_photos_to_purge(integer) from public, anon, authenticated;
revoke all on function public.mark_attendance_photos_purged(uuid[]) from public, anon, authenticated;
