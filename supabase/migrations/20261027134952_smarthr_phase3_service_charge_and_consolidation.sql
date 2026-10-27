-- PRD v3 §4.3. A monthly snapshot rather than a live calculation: once a period
-- is cut off, the points Finance was given must not drift.
create table public.service_charge_points (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  period_month integer not null check (period_month between 1 and 12),
  period_year integer not null check (period_year between 2000 and 2100),
  period_start date not null,
  period_end date not null,
  job_level text,
  base_points numeric(6, 2) not null default 0,
  scheduled_days integer not null default 0,
  worked_days integer not null default 0,
  prorated_points numeric(8, 3) not null default 0,
  late_count integer not null default 0,
  penalty_pct numeric(5, 2) not null default 0,
  penalty_deduction numeric(8, 3) not null default 0,
  final_points numeric(8, 3) not null default 0,
  generated_at timestamptz not null default now(),
  constraint service_charge_points_period_key unique (employee_id, period_month, period_year)
);

comment on column public.service_charge_points.scheduled_days is 'Roster days in the period. Pro-rata is worked_days / scheduled_days; leave days are not rostered, so they neither earn nor cost points. Change here if policy says paid leave should still earn.';

alter table public.service_charge_points enable row level security;

create policy service_charge_select_self on public.service_charge_points
  for select to authenticated
  using (employee_id = app_private.current_employee_id());

create policy service_charge_select_department on public.service_charge_points
  for select to authenticated
  using (
    app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id = service_charge_points.employee_id
        and e.department_id = app_private.current_department_id()
    )
  );

create policy service_charge_hr on public.service_charge_points
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

-- Recomputes the month's snapshot. Idempotent: re-running replaces the figures,
-- which is what HR wants before a cut-off and must not do after one.
create or replace function public.generate_service_charge_points(
  p_month integer,
  p_year integer
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  rng record;
  cfg record;
  touched integer;
begin
  if not app_private.is_hr_staff() then
    raise exception 'Only HR can generate service charge points.' using errcode = '42501';
  end if;

  select * into rng from public.payroll_period_range(p_month, p_year);
  select * into cfg from public.hotel_settings where id;

  if exists (
    select 1 from public.payroll_periods
    where status = 'locked' and start_date = rng.start_date and end_date = rng.end_date
  ) then
    raise exception 'That period is locked. Reopen it before regenerating points.'
      using errcode = 'P0007';
  end if;

  with worked as (
    select
      e.id as employee_id,
      coalesce(jl.name, '-') as job_level,
      coalesce(jl.base_points, 0) as base_points,
      count(r.id)::integer as scheduled_days,
      count(a.id) filter (where a.clock_out_time is not null)::integer as worked_days,
      count(a.id) filter (where a.is_late)::integer as late_count
    from public.employees e
    left join public.job_levels jl on jl.id = e.job_level_id
    left join public.rosters r
      on r.employee_id = e.id
     and r.shift_date between rng.start_date and rng.end_date
    left join public.attendance_logs a on a.roster_id = r.id
    where e.is_active and e.job_level_id is not null
    group by e.id, jl.name, jl.base_points
  ),
  computed as (
    select
      w.*,
      case when w.scheduled_days = 0 then 0
           else round(w.base_points * w.worked_days::numeric / w.scheduled_days, 3)
      end as prorated_points,
      case when w.late_count > cfg.late_penalty_threshold then cfg.late_penalty_pct
           else 0
      end as penalty_pct
    from worked w
  )
  insert into public.service_charge_points (
    employee_id, period_month, period_year, period_start, period_end,
    job_level, base_points, scheduled_days, worked_days,
    prorated_points, late_count, penalty_pct, penalty_deduction, final_points,
    generated_at
  )
  select
    c.employee_id, p_month, p_year, rng.start_date, rng.end_date,
    c.job_level, c.base_points, c.scheduled_days, c.worked_days,
    c.prorated_points, c.late_count, c.penalty_pct,
    round(c.prorated_points * c.penalty_pct / 100, 3),
    round(c.prorated_points - (c.prorated_points * c.penalty_pct / 100), 3),
    now()
  from computed c
  on conflict (employee_id, period_month, period_year) do update
  set period_start      = excluded.period_start,
      period_end        = excluded.period_end,
      job_level         = excluded.job_level,
      base_points       = excluded.base_points,
      scheduled_days    = excluded.scheduled_days,
      worked_days       = excluded.worked_days,
      prorated_points   = excluded.prorated_points,
      late_count        = excluded.late_count,
      penalty_pct       = excluded.penalty_pct,
      penalty_deduction = excluded.penalty_deduction,
      final_points      = excluded.final_points,
      generated_at      = excluded.generated_at;

  get diagnostics touched = row_count;
  return touched;
end;
$$;

-- PRD v3 §3.2 / §4.4: one row per employee, everything Finance needs.
-- NOTE: 20261027135030 adds the authorisation guard (this version is callable
-- by any authenticated user, which was a defect) and 20261027140633 fixes the
-- column types. The final shape is the one in that last migration.
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
language sql
stable
security definer
set search_path = public, pg_temp
as $$
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
    -- Approved only: unapproved time past the shift end is never paid.
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
    -- Only the portion of a request that falls inside the cut-off window.
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
$$;

revoke all on function
  public.generate_service_charge_points(integer, integer),
  public.pre_payroll_timesheet(date, date)
from public, anon;

grant execute on function public.generate_service_charge_points(integer, integer) to authenticated;
grant execute on function public.pre_payroll_timesheet(date, date) to authenticated;
