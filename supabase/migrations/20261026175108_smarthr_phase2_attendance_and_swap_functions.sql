-- Clock in. The geofence test lives here rather than in the API layer so it
-- holds for any caller, and the roster/attendance pair updates atomically.
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

-- Clock out. Distance is recorded but NOT enforced: refusing an off-site clock-out
-- would strand someone who has already left, producing a worse record than one
-- flagged for the HOD to review.
create or replace function public.clock_out(
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
  log record;
  cfg record;
  dist numeric;
  worked integer;
  early integer := 0;
  overtime integer := 0;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  select ro.id, ro.employee_id, ro.expected_clock_out into r
  from public.rosters ro where ro.id = p_roster_id;

  if not found then
    raise exception 'That shift could not be found.' using errcode = 'P0002';
  end if;

  if r.employee_id <> me then
    raise exception 'That shift belongs to another employee.' using errcode = '42501';
  end if;

  select * into log from public.attendance_logs where roster_id = p_roster_id;

  if not found then
    raise exception 'You have not clocked in for this shift yet.' using errcode = 'P0002';
  end if;

  if log.clock_out_time is not null then
    raise exception 'You have already clocked out for this shift.' using errcode = '23505';
  end if;

  select * into cfg from public.hotel_settings where id;
  dist := app_private.haversine_meters(p_lat, p_long, cfg.latitude, cfg.longitude);

  worked := greatest(0, floor(extract(epoch from (now() - log.clock_in_time)) / 60))::integer;

  if now() < r.expected_clock_out then
    early := ceil(extract(epoch from (r.expected_clock_out - now())) / 60)::integer;
  else
    overtime := floor(extract(epoch from (now() - r.expected_clock_out)) / 60)::integer;
  end if;

  update public.attendance_logs
  set clock_out_time = now(),
      clock_out_lat = p_lat,
      clock_out_long = p_long,
      clock_out_distance_meters = dist,
      clock_out_photo_path = p_photo_path,
      worked_minutes = worked,
      early_leave_minutes = early,
      overtime_minutes = overtime
  where roster_id = p_roster_id;

  update public.rosters set status = 'completed', updated_at = now() where id = p_roster_id;

  return jsonb_build_object(
    'distance_meters', dist,
    'worked_minutes', worked,
    'early_leave_minutes', early,
    'overtime_minutes', overtime,
    'outside_zone', dist > cfg.geofence_radius_meters
  );
end;
$$;

-- Peer-to-peer swap: the requester offers their shift to a colleague in the
-- same department. Both shifts must still be upcoming and unworked.
create or replace function public.request_shift_swap(
  p_requester_roster_id uuid,
  p_target_roster_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  mine record;
  theirs record;
  swap_id uuid;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  select r.*, e.department_id into mine
  from public.rosters r join public.employees e on e.id = r.employee_id
  where r.id = p_requester_roster_id;

  if not found or mine.employee_id <> me then
    raise exception 'That is not one of your shifts.' using errcode = '42501';
  end if;

  select r.*, e.department_id into theirs
  from public.rosters r join public.employees e on e.id = r.employee_id
  where r.id = p_target_roster_id;

  if not found then
    raise exception 'The colleague''s shift could not be found.' using errcode = 'P0002';
  end if;

  if theirs.employee_id = me then
    raise exception 'Pick a colleague''s shift, not your own.' using errcode = 'P0001';
  end if;

  if theirs.department_id <> mine.department_id then
    raise exception 'Shifts can only be swapped within the same department.' using errcode = 'P0001';
  end if;

  if mine.status <> 'scheduled' or theirs.status <> 'scheduled' then
    raise exception 'Only shifts that have not started can be swapped.' using errcode = 'P0001';
  end if;

  if mine.expected_clock_in <= now() or theirs.expected_clock_in <= now() then
    raise exception 'Both shifts must still be in the future.' using errcode = 'P0001';
  end if;

  insert into public.shift_swaps (requester_roster_id, target_roster_id, reason)
  values (p_requester_roster_id, p_target_roster_id, nullif(btrim(coalesce(p_reason, '')), ''))
  returning id into swap_id;

  return swap_id;
end;
$$;

-- The colleague accepts or declines. Acceptance only moves it to the HOD queue.
create or replace function public.respond_shift_swap(p_swap_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  sw record;
  target_owner uuid;
begin
  select * into sw from public.shift_swaps where id = p_swap_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  select employee_id into target_owner from public.rosters where id = sw.target_roster_id;

  if me is null or target_owner <> me then
    raise exception 'Only the colleague being asked can answer this request.' using errcode = '42501';
  end if;

  if sw.status <> 'pending_target' then
    raise exception 'This request has already been answered.' using errcode = 'P0001';
  end if;

  update public.shift_swaps
  set status = case when p_accept then 'pending_hod' else 'rejected' end,
      target_responded_at = now()
  where id = p_swap_id;

  return case when p_accept then 'pending_hod' else 'rejected' end;
end;
$$;

-- The requester can withdraw while it is still open.
create or replace function public.cancel_shift_swap(p_swap_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  sw record;
  requester_owner uuid;
begin
  select * into sw from public.shift_swaps where id = p_swap_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  select employee_id into requester_owner from public.rosters where id = sw.requester_roster_id;

  if me is null or requester_owner <> me then
    raise exception 'Only the requester can withdraw this.' using errcode = '42501';
  end if;

  if sw.status not in ('pending_target', 'pending_hod') then
    raise exception 'This request is already closed.' using errcode = 'P0001';
  end if;

  update public.shift_swaps set status = 'cancelled', decided_at = now() where id = p_swap_id;
  return 'cancelled';
end;
$$;

-- HOD (or HR) decision. Approving trades employee_id between the two rosters in
-- one statement; the one-shift-per-day constraint is deferred because a same-day
-- trade passes through a momentarily duplicate state.
create or replace function public.decide_shift_swap(
  p_swap_id uuid,
  p_approve boolean,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sw record;
  dept uuid;
  requester_employee uuid;
  target_employee uuid;
begin
  select * into sw from public.shift_swaps where id = p_swap_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  select e.department_id, r.employee_id into dept, requester_employee
  from public.rosters r join public.employees e on e.id = r.employee_id
  where r.id = sw.requester_roster_id;

  if not (
    app_private.is_hr_staff()
    or (app_private.is_hod() and dept = app_private.current_department_id())
  ) then
    raise exception 'Only the department head or HR can decide this.' using errcode = '42501';
  end if;

  if sw.status <> 'pending_hod' then
    raise exception 'This request is not awaiting approval.' using errcode = 'P0001';
  end if;

  if not p_approve then
    update public.shift_swaps
    set status = 'rejected', decided_at = now(), decided_by = auth.uid(),
        decision_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = p_swap_id;
    return 'rejected';
  end if;

  select employee_id into target_employee from public.rosters where id = sw.target_roster_id;

  set constraints public.rosters_one_shift_per_day deferred;

  update public.rosters
  set employee_id = case
        when id = sw.requester_roster_id then target_employee
        else requester_employee
      end,
      updated_at = now()
  where id in (sw.requester_roster_id, sw.target_roster_id);

  update public.shift_swaps
  set status = 'approved', decided_at = now(), decided_by = auth.uid(),
      decision_note = nullif(btrim(coalesce(p_note, '')), '')
  where id = p_swap_id;

  return 'approved';
end;
$$;

revoke all on function
  public.clock_in(uuid, numeric, numeric, text),
  public.clock_out(uuid, numeric, numeric, text),
  public.request_shift_swap(uuid, uuid, text),
  public.respond_shift_swap(uuid, boolean),
  public.cancel_shift_swap(uuid),
  public.decide_shift_swap(uuid, boolean, text)
from public, anon;

grant execute on function
  public.clock_in(uuid, numeric, numeric, text),
  public.clock_out(uuid, numeric, numeric, text),
  public.request_shift_swap(uuid, uuid, text),
  public.respond_shift_swap(uuid, boolean),
  public.cancel_shift_swap(uuid),
  public.decide_shift_swap(uuid, boolean, text)
to authenticated;
