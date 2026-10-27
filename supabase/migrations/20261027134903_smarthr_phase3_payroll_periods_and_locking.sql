-- PRD v3 §1 (Data Consistency): once HR triggers the cut-off, attendance and
-- overtime in that window are frozen, so finalised pre-payroll figures cannot
-- be changed underneath Finance.
create table public.payroll_periods (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  start_date date not null,
  end_date date not null,
  status text not null default 'open' check (status in ('open', 'locked')),
  locked_at timestamptz,
  locked_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint payroll_periods_range_ordered check (end_date >= start_date),
  constraint payroll_periods_range_key unique (start_date, end_date)
);

create index payroll_periods_lookup_idx on public.payroll_periods (start_date, end_date)
  where status = 'locked';

comment on table public.payroll_periods is 'Cut-off windows. A locked period freezes the attendance and overtime it covers.';

-- The cut-off window for a month, from hotel_settings.payroll_cutoff_day.
-- A period labelled March 2026 with a cut-off of 20 runs 20 Feb - 19 Mar.
create or replace function public.payroll_period_range(p_month integer, p_year integer)
returns table (start_date date, end_date date)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    (make_date(p_year, p_month, 1) - interval '1 month'
      + make_interval(days => (select payroll_cutoff_day from public.hotel_settings where id) - 1))::date,
    (make_date(p_year, p_month, 1)
      + make_interval(days => (select payroll_cutoff_day from public.hotel_settings where id) - 2))::date;
$$;

alter table public.payroll_periods enable row level security;

create policy payroll_periods_select on public.payroll_periods
  for select to authenticated
  using (app_private.is_hr_staff() or app_private.is_hod());

create policy payroll_periods_hr on public.payroll_periods
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

create or replace function app_private.date_is_locked(p_date date)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.payroll_periods
    where status = 'locked' and p_date between start_date and end_date
  );
$$;

grant execute on function app_private.date_is_locked(date) to authenticated;

-- Freeze attendance for locked periods. This guards the table itself, so it
-- holds for clock_in/clock_out and for an HR correction alike -- and, because
-- it is a trigger rather than a policy, for a direct admin connection too.
create or replace function app_private.reject_locked_attendance()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  shift date;
begin
  select r.shift_date into shift
  from public.rosters r
  where r.id = coalesce(new.roster_id, old.roster_id);

  if shift is not null and app_private.date_is_locked(shift) then
    raise exception
      'Payroll for % is locked. Reopen the period before changing attendance.', shift
      using errcode = 'P0007';
  end if;

  return new;
end;
$$;

create trigger attendance_logs_respect_payroll_lock
  before insert or update on public.attendance_logs
  for each row execute function app_private.reject_locked_attendance();

create or replace function app_private.reject_locked_overtime()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  shift date;
begin
  select r.shift_date into shift
  from public.rosters r
  where r.id = coalesce(new.roster_id, old.roster_id);

  if shift is not null and app_private.date_is_locked(shift) then
    raise exception
      'Payroll for % is locked. Reopen the period before changing overtime.', shift
      using errcode = 'P0007';
  end if;

  return new;
end;
$$;

create trigger overtime_records_respect_payroll_lock
  before insert or update on public.overtime_records
  for each row execute function app_private.reject_locked_overtime();

create or replace function public.set_payroll_period_lock(p_period_id uuid, p_locked boolean)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not app_private.is_hr_staff() then
    raise exception 'Only HR can lock or reopen a payroll period.' using errcode = '42501';
  end if;

  update public.payroll_periods
  set status    = case when p_locked then 'locked' else 'open' end,
      locked_at = case when p_locked then now() else null end,
      locked_by = case when p_locked then auth.uid() else null end
  where id = p_period_id;

  if not found then
    raise exception 'That period could not be found.' using errcode = 'P0002';
  end if;

  return case when p_locked then 'locked' else 'open' end;
end;
$$;

revoke all on function
  public.payroll_period_range(integer, integer),
  public.set_payroll_period_lock(uuid, boolean)
from public, anon;

grant execute on function
  public.payroll_period_range(integer, integer),
  public.set_payroll_period_lock(uuid, boolean)
to authenticated;
