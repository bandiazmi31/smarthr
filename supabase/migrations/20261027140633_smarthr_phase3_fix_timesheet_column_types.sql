-- departments.name is varchar(100) and the other joined columns carry their own
-- lengths, but the RETURNS TABLE declares text. Postgres rejects that at call
-- time with "structure of query does not match function result type", so every
-- column the signature calls text is now cast explicitly, and the aggregates
-- are pinned to numeric.
create or replace function public.pre_payroll_timesheet(p_start date, p_end date)
returns table (
  staff_number text,
  full_name text,
  department text,
  job_title text,
  job_level text,
  employment_status text,
  scheduled_days integer,
  worked_days integer,
  late_count integer,
  total_late_minutes integer,
  total_worked_minutes integer,
  overtime_hours numeric,
  overtime_weighted_hours numeric,
  holiday_overtime_hours numeric,
  annual_leave_days numeric,
  sick_leave_days numeric,
  unpaid_leave_days numeric,
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
    select e.id,
           e.employee_id::text as staff_number,
           e.full_name::text as full_name,
           d.name::text as department,
           e.job_title::text as job_title,
           coalesce(jl.name, '-')::text as job_level,
           e.employment_status::text as employment_status
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
    -- Approved only: unapproved time past the shift end is never paid.
    select
      o.employee_id,
      coalesce(sum(o.approved_hours), 0)::numeric as overtime_hours,
      coalesce(sum(o.approved_hours * coalesce(o.multiplier_applied, 1)), 0)::numeric as weighted_hours,
      coalesce(sum(o.approved_hours) filter (where o.is_public_holiday), 0)::numeric as holiday_hours
    from public.overtime_records o
    join public.rosters r on r.id = o.roster_id
    where o.status = 'approved'
      and r.shift_date between p_start and p_end
    group by o.employee_id
  ),
  leave as (
    -- Only the portion of a request that falls inside the cut-off window.
    select
      lr.employee_id,
      coalesce(sum(
        (least(lr.end_date, p_end) - greatest(lr.start_date, p_start) + 1)
      ) filter (where lr.leave_type = 'Annual'), 0)::numeric as annual_days,
      coalesce(sum(
        (least(lr.end_date, p_end) - greatest(lr.start_date, p_start) + 1)
      ) filter (where lr.leave_type = 'Sick'), 0)::numeric as sick_days,
      coalesce(sum(
        (least(lr.end_date, p_end) - greatest(lr.start_date, p_start) + 1)
      ) filter (where lr.leave_type = 'Unpaid'), 0)::numeric as unpaid_days
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
    coalesce(lv.annual_days, 0),
    coalesce(lv.sick_days, 0),
    coalesce(lv.unpaid_days, 0),
    coalesce(pt.final_points, 0)::numeric
  from scope s
  left join attendance at on at.employee_id = s.id
  left join overtime ot on ot.employee_id = s.id
  left join leave lv on lv.employee_id = s.id
  left join points pt on pt.employee_id = s.id
  order by s.department, s.full_name;
end;
$$;
