-- PRD v2.0 §4.2: staff may clock in at most 45 minutes before their shift, so an
-- early arrival cannot be logged as premature overtime. Configurable alongside
-- the geofence rather than hard-coded, since it is the same kind of policy knob.
alter table public.hotel_settings
  add column early_clock_in_limit_mins integer not null default 45
    check (early_clock_in_limit_mins between 0 and 480);

comment on column public.hotel_settings.early_clock_in_limit_mins is 'PRD v2.0 4.2: how long before expected_clock_in a shift may be clocked into.';

-- PRD v2.0 §3: "Late" is past the 15-minute grace period.
alter table public.master_shifts alter column grace_period_mins set default 15;
update public.master_shifts set grace_period_mins = 15 where grace_period_mins = 10;

create or replace function public.clock_in(
  p_roster_id uuid,
  p_lat numeric,
  p_long numeric,
  p_photo_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  r record;
  cfg record;
  dist numeric;
  late boolean := false;
  late_mins integer := 0;
  opens_at timestamptz;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  select ro.id, ro.employee_id, ro.expected_clock_in, ro.status, ms.grace_period_mins
  into r
  from public.rosters ro
  join public.master_shifts ms on ms.id = ro.shift_id
  where ro.id = p_roster_id;

  if not found then
    raise exception 'That shift could not be found.' using errcode = 'P0002';
  end if;

  if r.employee_id <> me then
    raise exception 'That shift belongs to another employee.' using errcode = '42501';
  end if;

  if exists (select 1 from public.attendance_logs where roster_id = p_roster_id) then
    raise exception 'You have already clocked in for this shift.' using errcode = '23505';
  end if;

  select * into cfg from public.hotel_settings where id;

  -- Too early: refuse before the geofence check, so an employee standing in the
  -- lobby an hour early gets the useful message rather than a location one.
  opens_at := r.expected_clock_in - make_interval(mins => cfg.early_clock_in_limit_mins);

  if now() < opens_at then
    raise exception
      'Too early. You can clock in from % minutes before your shift starts.',
      cfg.early_clock_in_limit_mins
      using errcode = 'P0003';
  end if;

  dist := app_private.haversine_meters(p_lat, p_long, cfg.latitude, cfg.longitude);

  if dist > cfg.geofence_radius_meters then
    raise exception 'You are outside the designated clock-in zone.' using errcode = 'P0001';
  end if;

  if now() > r.expected_clock_in + make_interval(mins => coalesce(r.grace_period_mins, 0)) then
    late := true;
    late_mins := greatest(
      0, ceil(extract(epoch from (now() - r.expected_clock_in)) / 60)
    )::integer;
  end if;

  insert into public.attendance_logs (
    roster_id, clock_in_time, clock_in_lat, clock_in_long,
    clock_in_distance_meters, clock_in_photo_path, is_late, late_by_minutes
  ) values (
    p_roster_id, now(), p_lat, p_long, dist, p_photo_path, late, late_mins
  );

  update public.rosters set status = 'in_progress', updated_at = now() where id = p_roster_id;

  return jsonb_build_object(
    'distance_meters', dist,
    'is_late', late,
    'late_by_minutes', late_mins
  );
end;
$$;
