-- PRD v3 §4.2: overtime only counts when it matches an approved request, which
-- is what stops someone lingering after their shift to inflate pay.
create table public.overtime_records (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null unique references public.rosters (id) on delete cascade,
  employee_id uuid not null references public.employees (id) on delete cascade,
  department_id uuid references public.departments (id) on delete set null,
  requested_hours numeric(5, 2) not null check (requested_hours > 0 and requested_hours <= 24),
  approved_hours numeric(5, 2) check (approved_hours >= 0 and approved_hours <= 24),
  multiplier_applied numeric(4, 2) check (multiplier_applied between 1 and 10),
  is_public_holiday boolean not null default false,
  reason text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid references auth.users (id) on delete set null,
  decided_by uuid references auth.users (id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now()
);

create index overtime_records_employee_idx on public.overtime_records (employee_id);
create index overtime_records_status_idx on public.overtime_records (status);

comment on column public.overtime_records.approved_hours is 'What payroll pays. Set at approval and capped by both the request and the hours actually worked past expected_clock_out.';

-- The rate for a date: a holiday-specific override, the hotel-wide holiday
-- rate, or the ordinary overtime rate.
create or replace function public.overtime_multiplier_for(p_date date)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select h.multiplier from public.master_holidays h where h.holiday_date = p_date),
    case
      when exists (select 1 from public.master_holidays h where h.holiday_date = p_date)
        then (select public_holiday_multiplier from public.hotel_settings where id)
      else (select overtime_multiplier from public.hotel_settings where id)
    end
  );
$$;

-- Everything a HOD needs to sign off: what was asked for, and what the clock
-- actually recorded past the expected end of the shift.
create view public.overtime_review
with (security_invoker = true)
as
select
  o.id, o.roster_id, o.employee_id, o.department_id, o.status,
  o.requested_hours, o.approved_hours, o.multiplier_applied, o.is_public_holiday,
  o.reason, o.decision_note, o.created_at, o.decided_at,
  e.full_name,
  e.employee_id as staff_number,
  r.shift_date,
  s.name as shift_name,
  s.code as shift_code,
  r.expected_clock_out,
  a.clock_out_time,
  -- Actual minutes worked past the rostered end, 0 when still on shift.
  coalesce(a.overtime_minutes, 0) as actual_overtime_minutes,
  round(coalesce(a.overtime_minutes, 0)::numeric / 60, 2) as actual_overtime_hours,
  (h.holiday_date is not null) as falls_on_holiday,
  h.description as holiday_description
from public.overtime_records o
join public.rosters r on r.id = o.roster_id
join public.employees e on e.id = o.employee_id
join public.master_shifts s on s.id = r.shift_id
left join public.attendance_logs a on a.roster_id = r.id
left join public.master_holidays h on h.holiday_date = r.shift_date;

grant select on public.overtime_review to authenticated;

alter table public.overtime_records enable row level security;

create policy overtime_select_self on public.overtime_records
  for select to authenticated
  using (employee_id = app_private.current_employee_id());

create policy overtime_select_department on public.overtime_records
  for select to authenticated
  using (app_private.is_hod() and department_id = app_private.current_department_id());

create policy overtime_hr on public.overtime_records
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

create or replace function public.request_overtime(
  p_roster_id uuid,
  p_hours numeric,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  r record;
  new_id uuid;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  if p_hours is null or p_hours <= 0 or p_hours > 24 then
    raise exception 'Overtime hours must be between 0 and 24.' using errcode = 'P0001';
  end if;

  select ro.id, ro.employee_id, ro.shift_date, e.department_id
  into r
  from public.rosters ro
  join public.employees e on e.id = ro.employee_id
  where ro.id = p_roster_id;

  if not found then
    raise exception 'That shift could not be found.' using errcode = 'P0002';
  end if;

  -- The employee raises their own; a HOD may raise one for their department.
  if r.employee_id <> me
     and not (app_private.is_hod() and r.department_id = app_private.current_department_id())
     and not app_private.is_hr_staff() then
    raise exception 'That shift belongs to another employee.' using errcode = '42501';
  end if;

  if exists (select 1 from public.overtime_records where roster_id = p_roster_id) then
    raise exception 'Overtime has already been raised for this shift.' using errcode = '23505';
  end if;

  insert into public.overtime_records (
    roster_id, employee_id, department_id, requested_hours, reason,
    is_public_holiday, requested_by
  ) values (
    p_roster_id, r.employee_id, r.department_id, p_hours,
    nullif(btrim(coalesce(p_reason, '')), ''),
    exists (select 1 from public.master_holidays h where h.holiday_date = r.shift_date),
    auth.uid()
  )
  returning id into new_id;

  return new_id;
end;
$$;

-- HOD signs off. Approved hours are capped by the request AND by what the clock
-- actually recorded, so an approval cannot invent time that was never worked.
create or replace function public.decide_overtime(
  p_record_id uuid,
  p_approve boolean,
  p_approved_hours numeric default null,
  p_note text default null
)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  rec record;
  actual_hours numeric;
  granted numeric;
  rate numeric;
begin
  select o.*, r.shift_date, coalesce(a.overtime_minutes, 0) as actual_minutes
  into rec
  from public.overtime_records o
  join public.rosters r on r.id = o.roster_id
  left join public.attendance_logs a on a.roster_id = o.roster_id
  where o.id = p_record_id;

  if not found then
    raise exception 'That overtime record could not be found.' using errcode = 'P0002';
  end if;

  if not (
    app_private.is_hr_staff()
    or (app_private.is_hod() and rec.department_id = app_private.current_department_id())
  ) then
    raise exception 'Only the department head or HR can decide this.' using errcode = '42501';
  end if;

  if rec.status <> 'pending' then
    raise exception 'This overtime record has already been decided.' using errcode = 'P0001';
  end if;

  if not p_approve then
    update public.overtime_records
    set status = 'rejected', approved_hours = 0, decided_at = now(), decided_by = auth.uid(),
        decision_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = p_record_id;
    return 0;
  end if;

  actual_hours := round(rec.actual_minutes::numeric / 60, 2);

  if actual_hours <= 0 then
    raise exception
      'No overtime was recorded for this shift yet, so there is nothing to approve.'
      using errcode = 'P0006';
  end if;

  granted := least(coalesce(p_approved_hours, actual_hours), rec.requested_hours, actual_hours);

  if granted <= 0 then
    raise exception 'Approved overtime must be greater than zero.' using errcode = 'P0001';
  end if;

  rate := public.overtime_multiplier_for(rec.shift_date);

  update public.overtime_records
  set status = 'approved',
      approved_hours = granted,
      multiplier_applied = rate,
      is_public_holiday = exists (
        select 1 from public.master_holidays h where h.holiday_date = rec.shift_date
      ),
      decided_at = now(),
      decided_by = auth.uid(),
      decision_note = nullif(btrim(coalesce(p_note, '')), '')
  where id = p_record_id;

  return granted;
end;
$$;

revoke all on function
  public.overtime_multiplier_for(date),
  public.request_overtime(uuid, numeric, text),
  public.decide_overtime(uuid, boolean, numeric, text)
from public, anon;

grant execute on function
  public.overtime_multiplier_for(date),
  public.request_overtime(uuid, numeric, text),
  public.decide_overtime(uuid, boolean, numeric, text)
to authenticated;
