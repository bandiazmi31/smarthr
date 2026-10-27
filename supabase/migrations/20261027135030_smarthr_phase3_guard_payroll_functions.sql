-- pre_payroll_timesheet returns every employee's figures and is SECURITY
-- DEFINER, so it must authorise its own caller. Granting EXECUTE is not a gate:
-- any signed-in employee could otherwise read the whole payroll via
-- /rest/v1/rpc/pre_payroll_timesheet.
--
-- The body is otherwise unchanged from the previous migration; 20261027140633
-- then fixes the column types. Only the guard matters here.
create or replace function public.pre_payroll_timesheet(p_start date, p_end date)
returns table (
  staff_number text, full_name text, department text, job_title text,
  job_level text, employment_status text,
  scheduled_days integer, worked_days integer, late_count integer,
  total_late_minutes integer, total_worked_minutes integer,
  overtime_hours numeric, overtime_weighted_hours numeric, holiday_overtime_hours numeric,
  annual_leave_days numeric, sick_leave_days numeric, unpaid_leave_days numeric,
  service_charge_points numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not app_private.is_hr_staff() then
    raise exception 'Only HR can read the pre-payroll timesheet.' using errcode = '42501';
  end if;

  return query
  with scope as (
    select e.id, e.employee_id as staff_number, e.full_name, d.name as department,
           e.job_title, coalesce(jl.name, '-') as job_level, e.employment_status
    from public.employees e
    join public.departments d on d.id = e.department_id
    left join public.job_levels jl on jl.id = e.job_level_id
    where e.is_active
  ),
  attendance as (
    select
      r.employee_id,
      count(r.id)::integer as scheduled_days,
      count(a.id) filter (where a.clock_out_time is not null)::integer as worked_days,
      count(a.id) filter (where a.is_late)::integer as late_count,
      coalesce(sum(a.late_by_minutes), 0)::integer as total_late_minutes,
      coalesce(sum(a.worked_minutes), 0)::integer as total_worked_minutes
    from public.rosters r
    left join public.attendance_logs a on a.roster_id = r.id
    where r.shift_date between p_start and p_end
    group by r.employee_id
  ),
  overtime as (
    select
      o.employee_id,
      coalesce(sum(o.approved_hours), 0) as overtime_hours,
      coalesce(sum(o.approved_hours * coalesce(o.multiplier_applied, 1)), 0) as weighted_hours,
      coalesce(sum(o.approved_hours) filter (where o.is_public_holiday), 0) as holiday_hours
    from public.overtime_records o
    join public.rosters r on r.id = o.roster_id
    where o.status = 'approved'
      and r.shift_date between p_start and p_end
    group by o.employee_id
  ),
  leave as (
    select
      lr.employee_id,
      coalesce(sum(
        (least(lr.end_date, p_end) - greatest(lr.start_date, p_start) + 1)
      ) filter (where lr.leave_type = 'Annual'), 0) as annual_days,
      coalesce(sum(
        (least(lr.end_date, p_end) - greatest(lr.start_date, p_start) + 1)
      ) filter (where lr.leave_type = 'Sick'), 0) as sick_days,
      coalesce(sum(
        (least(lr.end_date, p_end) - greatest(lr.start_date, p_start) + 1)
      ) filter (where lr.leave_type = 'Unpaid'), 0) as unpaid_days
    from public.leave_requests lr
    where lr.status = 'approved'
      and daterange(lr.start_date, lr.end_date, '[]') && daterange(p_start, p_end, '[]')
    group by lr.employee_id
  ),
  points as (
    select scp.employee_id, scp.final_points
    from public.service_charge_points scp
    where scp.period_start = p_start and scp.period_end = p_end
  )
  select
    s.staff_number, s.full_name, s.department, s.job_title, s.job_level, s.employment_status,
    coalesce(at.scheduled_days, 0),
    coalesce(at.worked_days, 0),
    coalesce(at.late_count, 0),
    coalesce(at.total_late_minutes, 0),
    coalesce(at.total_worked_minutes, 0),
    round(coalesce(ot.overtime_hours, 0), 2),
    round(coalesce(ot.weighted_hours, 0), 2),
    round(coalesce(ot.holiday_hours, 0), 2),
    coalesce(lv.annual_days, 0)::numeric,
    coalesce(lv.sick_days, 0)::numeric,
    coalesce(lv.unpaid_days, 0)::numeric,
    coalesce(pt.final_points, 0)
  from scope s
  left join attendance at on at.employee_id = s.id
  left join overtime ot on ot.employee_id = s.id
  left join leave lv on lv.employee_id = s.id
  left join points pt on pt.employee_id = s.id
  order by s.department, s.full_name;
end;
$$;

-- Coverage reveals a department's staffing. Only that department's HOD, or HR,
-- has any business asking.
create or replace function public.leave_coverage(p_department_id uuid, p_date date)
returns table (
  total_staff integer, scheduled integer, on_leave integer,
  effective integer, ratio_pct integer, below_threshold boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (
    app_private.is_hr_staff()
    or (app_private.is_hod() and p_department_id = app_private.current_department_id())
  ) then
    raise exception 'Only the department head or HR can see coverage.' using errcode = '42501';
  end if;

  return query
  with staff as (
    select count(*)::integer as n
    from public.employees e
    where e.is_active and e.department_id = p_department_id
  ),
  sched as (
    select count(*)::integer as n
    from public.rosters r
    join public.employees e on e.id = r.employee_id
    where e.department_id = p_department_id
      and r.shift_date = p_date
      and r.status <> 'absent'
  ),
  away as (
    select count(distinct lr.employee_id)::integer as n
    from public.leave_requests lr
    where lr.department_id = p_department_id
      and lr.status = 'approved'
      and p_date between lr.start_date and lr.end_date
  )
  select
    staff.n, sched.n, away.n,
    greatest(0, sched.n - away.n),
    case when staff.n = 0 then 0
         else floor(greatest(0, sched.n - away.n)::numeric * 100 / staff.n)::integer end,
    case when staff.n = 0 then false
         else floor(greatest(0, sched.n - away.n)::numeric * 100 / staff.n)
              < (select leave_coverage_threshold_pct from public.hotel_settings where id) end
  from staff, sched, away;
end;
$$;
