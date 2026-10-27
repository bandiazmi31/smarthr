-- Phase 3 policy knobs. Same principle as Phase 2: configuration lives in
-- hotel_settings rather than being hard-coded in a function or an endpoint.
alter table public.hotel_settings
  add column annual_leave_days integer not null default 12
    check (annual_leave_days between 0 and 365),
  add column sick_cert_required_after_days integer not null default 1
    check (sick_cert_required_after_days between 0 and 30),
  add column leave_coverage_threshold_pct integer not null default 60
    check (leave_coverage_threshold_pct between 0 and 100),
  add column late_penalty_threshold integer not null default 3
    check (late_penalty_threshold between 0 and 31),
  add column late_penalty_pct numeric(5, 2) not null default 10.00
    check (late_penalty_pct between 0 and 100),
  add column payroll_cutoff_day integer not null default 20
    check (payroll_cutoff_day between 1 and 28),
  add column overtime_multiplier numeric(4, 2) not null default 1.50
    check (overtime_multiplier between 1 and 10),
  add column public_holiday_multiplier numeric(4, 2) not null default 2.00
    check (public_holiday_multiplier between 1 and 10);

comment on column public.hotel_settings.payroll_cutoff_day is 'PRD v3 4.4: periods run from this day of one month to the same day of the next.';
comment on column public.hotel_settings.leave_coverage_threshold_pct is 'PRD v3 3.1: a leave approval below this coverage ratio is flagged to the HOD.';

-- National holidays drive the overtime multiplier (PRD v3 4.2).
create table public.master_holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date not null,
  description text not null,
  -- Lets a specific holiday override the hotel-wide rate.
  multiplier numeric(4, 2) check (multiplier between 1 and 10),
  created_at timestamptz not null default now(),
  constraint master_holidays_description_not_blank check (length(btrim(description)) > 0)
);

create unique index master_holidays_date_key on public.master_holidays (holiday_date);

comment on table public.master_holidays is 'National public holidays. A shift falling on one of these earns the holiday multiplier instead of the ordinary overtime rate.';

-- Service-charge base points by job level (PRD v3 4.3).
create table public.job_levels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  base_points numeric(6, 2) not null check (base_points >= 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  constraint job_levels_name_not_blank check (length(btrim(name)) > 0)
);

create unique index job_levels_name_lower_key on public.job_levels (lower(name));

insert into public.job_levels (name, base_points, sort_order) values
  ('Manager',    3, 1),
  ('Supervisor', 2, 2),
  ('Staff',      1, 3);

-- Every employee earning service charge needs a level. NULL = not eligible,
-- which is a real case (daily workers, outsourced roles).
alter table public.employees
  add column job_level_id uuid references public.job_levels (id) on delete restrict;

comment on column public.employees.job_level_id is 'Drives the service-charge base points. NULL = not part of the service-charge pool.';

create index employees_job_level_idx on public.employees (job_level_id);

-- Default the existing roster to Staff, with the obvious seniors promoted.
update public.employees
set job_level_id = (select id from public.job_levels where name = 'Staff')
where job_level_id is null and employment_status in ('PKWT', 'PKWTT');

update public.employees
set job_level_id = (select id from public.job_levels where name = 'Manager')
where job_title ilike '%manager%' or job_title ilike '%chief%';

update public.employees
set job_level_id = (select id from public.job_levels where name = 'Supervisor')
where job_title ilike '%supervisor%' or job_title ilike '%head %';

alter table public.master_holidays enable row level security;
alter table public.job_levels enable row level security;

-- Readable by anyone in the portal (staff see why a shift paid more); HR writes.
create policy master_holidays_select on public.master_holidays
  for select to authenticated
  using (app_private.is_hr_staff() or app_private.is_linked_employee());

create policy master_holidays_write on public.master_holidays
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

create policy job_levels_select on public.job_levels
  for select to authenticated
  using (app_private.is_hr_staff() or app_private.is_linked_employee());

create policy job_levels_write on public.job_levels
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());
