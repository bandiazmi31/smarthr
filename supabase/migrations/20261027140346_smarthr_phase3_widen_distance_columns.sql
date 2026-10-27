-- numeric(8,2) caps at 999,999.99 metres, so any clock-out from further than
-- ~1,000 km raised "numeric field overflow" instead of recording the distance.
-- Clock-IN rejects out-of-zone before writing, so it was unaffected; clock-OUT
-- records distance rather than refusing it (by design), so it hit the ceiling.
--
-- Half the Earth's circumference is ~20,000 km, so numeric(12,2) holds any real
-- reading with room to spare.
--
-- roster_details selects these columns, so it has to go first: a column type
-- cannot change while a view depends on it.
drop view public.roster_details;

alter table public.attendance_logs
  alter column clock_in_distance_meters type numeric(12, 2),
  alter column clock_out_distance_meters type numeric(12, 2);

comment on column public.attendance_logs.clock_out_distance_meters is 'Metres from the hotel anchor at clock-out. Recorded but not enforced, so it must hold an arbitrarily distant reading.';

create view public.roster_details
with (security_invoker = true)
as
select
  r.id, r.employee_id, r.shift_id, r.shift_date,
  r.expected_clock_in, r.expected_clock_out, r.status, r.note,
  e.employee_id as staff_number,
  e.full_name, e.job_title, e.department_id,
  d.name as department_name,
  s.name as shift_name, s.code as shift_code,
  s.start_time, s.end_time, s.is_overnight, s.grace_period_mins,
  a.id as attendance_id,
  a.clock_in_time, a.clock_out_time,
  a.is_late, a.late_by_minutes, a.worked_minutes,
  a.early_leave_minutes, a.overtime_minutes,
  a.clock_in_distance_meters, a.clock_out_distance_meters,
  a.clock_in_photo_path, a.clock_out_photo_path
from public.rosters r
join public.employees e on e.id = r.employee_id
join public.departments d on d.id = e.department_id
join public.master_shifts s on s.id = r.shift_id
left join public.attendance_logs a on a.roster_id = r.id;

comment on view public.roster_details is 'Roster joined to employee, department, shift definition and attendance. Inherits the caller RLS of every underlying table.';

grant select on public.roster_details to authenticated;
