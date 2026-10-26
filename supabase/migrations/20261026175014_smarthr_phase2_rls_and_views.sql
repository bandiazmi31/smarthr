-- Which employees the weekly cron schedules automatically, and onto which shift.
-- NULL means "rostered by hand", which is every operational role.
alter table public.employees
  add column auto_schedule_shift_id uuid references public.master_shifts (id) on delete set null;

comment on column public.employees.auto_schedule_shift_id is 'Non-null = backoffice staff auto-rostered Mon-Fri onto this shift by the weekly cron.';

-- A swap trades employee_id between two rosters. When both fall on the same day
-- the intermediate row state collides, so the uniqueness check has to defer to
-- the end of the transaction.
alter table public.rosters drop constraint rosters_one_shift_per_day;
alter table public.rosters add constraint rosters_one_shift_per_day
  unique (employee_id, shift_date) deferrable initially immediate;

-- Great-circle distance in metres. least(1, ...) guards against floating point
-- nudging the asin argument past 1 for near-identical coordinates.
create or replace function app_private.haversine_meters(
  lat1 numeric, lon1 numeric, lat2 numeric, lon2 numeric
)
returns numeric
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select round((
    6371000 * 2 * asin(least(1, sqrt(
      power(sin(radians((lat2 - lat1)::double precision) / 2), 2)
      + cos(radians(lat1::double precision)) * cos(radians(lat2::double precision))
        * power(sin(radians((lon2 - lon1)::double precision) / 2), 2)
    )))
  )::numeric, 2);
$$;

grant execute on function app_private.haversine_meters(numeric, numeric, numeric, numeric) to authenticated;

alter table public.hotel_settings enable row level security;
alter table public.master_shifts enable row level security;
alter table public.rosters enable row level security;
alter table public.attendance_logs enable row level security;
alter table public.shift_swaps enable row level security;

-- Settings and shift definitions are readable by anyone in the portal (the mobile
-- app shows the geofence radius and shift times); only HR changes them.
create policy hotel_settings_select on public.hotel_settings
  for select to authenticated
  using (app_private.is_hr_staff() or app_private.is_linked_employee());

create policy hotel_settings_update on public.hotel_settings
  for update to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

create policy master_shifts_select on public.master_shifts
  for select to authenticated
  using (app_private.is_hr_staff() or app_private.is_linked_employee());

create policy master_shifts_insert on public.master_shifts
  for insert to authenticated with check (app_private.is_hr_staff());

create policy master_shifts_update on public.master_shifts
  for update to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

-- Rosters: HR everywhere, a HOD within their department, an employee their own.
create policy rosters_select_hr on public.rosters
  for select to authenticated using (app_private.is_hr_staff());

create policy rosters_select_self on public.rosters
  for select to authenticated using (employee_id = app_private.current_employee_id());

create policy rosters_select_department on public.rosters
  for select to authenticated
  using (
    app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id = rosters.employee_id
        and e.department_id = app_private.current_department_id()
    )
  );

create policy rosters_write_hr on public.rosters
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

create policy rosters_write_department on public.rosters
  for all to authenticated
  using (
    app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id = rosters.employee_id
        and e.department_id = app_private.current_department_id()
    )
  )
  with check (
    app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id = rosters.employee_id
        and e.department_id = app_private.current_department_id()
    )
  );

-- Attendance is written only through clock_in/clock_out, which are SECURITY
-- DEFINER, so staff get no direct insert or update here.
create policy attendance_logs_select_hr on public.attendance_logs
  for select to authenticated using (app_private.is_hr_staff());

create policy attendance_logs_select_self on public.attendance_logs
  for select to authenticated
  using (
    exists (
      select 1 from public.rosters r
      where r.id = attendance_logs.roster_id
        and r.employee_id = app_private.current_employee_id()
    )
  );

create policy attendance_logs_select_department on public.attendance_logs
  for select to authenticated
  using (
    app_private.is_hod()
    and exists (
      select 1 from public.rosters r
      join public.employees e on e.id = r.employee_id
      where r.id = attendance_logs.roster_id
        and e.department_id = app_private.current_department_id()
    )
  );

create policy attendance_logs_update_hr on public.attendance_logs
  for update to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

-- Swaps: both participants, their HOD, and HR can read. Mutations go through
-- the workflow functions.
create policy shift_swaps_select_hr on public.shift_swaps
  for select to authenticated using (app_private.is_hr_staff());

create policy shift_swaps_select_participant on public.shift_swaps
  for select to authenticated
  using (
    exists (
      select 1 from public.rosters r
      where r.id in (shift_swaps.requester_roster_id, shift_swaps.target_roster_id)
        and r.employee_id = app_private.current_employee_id()
    )
  );

create policy shift_swaps_select_department on public.shift_swaps
  for select to authenticated
  using (
    app_private.is_hod()
    and exists (
      select 1 from public.rosters r
      join public.employees e on e.id = r.employee_id
      where r.id = shift_swaps.requester_roster_id
        and e.department_id = app_private.current_department_id()
    )
  );

-- One denormalised read model for every roster screen.
create view public.roster_details
with (security_invoker = true)
as
select
  r.id,
  r.employee_id,
  r.shift_id,
  r.shift_date,
  r.expected_clock_in,
  r.expected_clock_out,
  r.status,
  r.note,
  e.employee_id as staff_number,
  e.full_name,
  e.job_title,
  e.department_id,
  d.name as department_name,
  s.name as shift_name,
  s.code as shift_code,
  s.start_time,
  s.end_time,
  s.is_overnight,
  s.grace_period_mins,
  a.id as attendance_id,
  a.clock_in_time,
  a.clock_out_time,
  a.is_late,
  a.late_by_minutes,
  a.worked_minutes,
  a.early_leave_minutes,
  a.overtime_minutes,
  a.clock_in_distance_meters,
  a.clock_out_distance_meters,
  a.clock_in_photo_path,
  a.clock_out_photo_path
from public.rosters r
join public.employees e on e.id = r.employee_id
join public.departments d on d.id = e.department_id
join public.master_shifts s on s.id = r.shift_id
left join public.attendance_logs a on a.roster_id = r.id;

comment on view public.roster_details is 'Roster joined to employee, department, shift definition and attendance. Inherits the caller RLS of every underlying table.';

grant select on public.roster_details to authenticated;

-- Swap requests with both sides resolved, for the swaps inbox.
create view public.shift_swap_details
with (security_invoker = true)
as
select
  sw.id,
  sw.status,
  sw.reason,
  sw.decision_note,
  sw.created_at,
  sw.target_responded_at,
  sw.decided_at,
  sw.requester_roster_id,
  sw.target_roster_id,
  rr.employee_id as requester_employee_id,
  re.full_name   as requester_name,
  re.department_id as department_id,
  rr.shift_date  as requester_shift_date,
  rs.name        as requester_shift_name,
  rs.code        as requester_shift_code,
  tr.employee_id as target_employee_id,
  te.full_name   as target_name,
  tr.shift_date  as target_shift_date,
  ts.name        as target_shift_name,
  ts.code        as target_shift_code
from public.shift_swaps sw
join public.rosters rr on rr.id = sw.requester_roster_id
join public.employees re on re.id = rr.employee_id
join public.master_shifts rs on rs.id = rr.shift_id
join public.rosters tr on tr.id = sw.target_roster_id
join public.employees te on te.id = tr.employee_id
join public.master_shifts ts on ts.id = tr.shift_id;

grant select on public.shift_swap_details to authenticated;
