-- Department master data. Replaces the free-text employees.department column with
-- a foreign key, so nomenclature is standardised and a department in use cannot be
-- deleted out from under its employees.
create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name varchar(100) not null,
  description text,
  created_at timestamptz not null default now(),
  constraint departments_name_not_blank check (length(btrim(name)) > 0)
);

-- Case-insensitive uniqueness: "F&B" and "f&b" are the same department.
-- This subsumes a plain UNIQUE(name).
create unique index departments_name_lower_key on public.departments (lower(name));

comment on table public.departments is 'Standardised organisational units. Referenced by employees.department_id.';

-- Seed from the names already in use, one row per distinct name ignoring case.
insert into public.departments (name)
select distinct on (lower(btrim(department))) btrim(department)
from public.employees
where btrim(coalesce(department, '')) <> ''
order by lower(btrim(department));

-- Repoint employees at the new table.
alter table public.employees
  add column department_id uuid references public.departments (id) on delete restrict;

update public.employees e
set department_id = d.id
from public.departments d
where lower(d.name) = lower(btrim(e.department));

alter table public.employees alter column department_id set not null;

-- The view reads employees.department, so it has to go before the column does.
drop view public.employee_contract_status;

alter table public.employees drop column department;

create index employees_department_id_idx on public.employees (department_id);

-- Rebuilt to expose `department` as the resolved name, so every reader
-- (directory, alerts, CSV export) sees the same shape as before.
create view public.employee_contract_status
with (security_invoker = true)
as
select
  e.*,
  d.name as department,
  case when e.end_date is null then null else (e.end_date - current_date) end as days_remaining,
  case
    when e.end_date is null then 'none'
    when e.end_date < current_date then 'expired'
    when e.end_date - current_date <= 7 then 'critical'
    when e.end_date - current_date <= 30 then 'warning'
    else 'ok'
  end as alert_level
from public.employees e
join public.departments d on d.id = e.department_id;

comment on view public.employee_contract_status is 'Employees with resolved department name and contract countdown. alert_level: expired | critical (<=7d) | warning (<=30d) | ok | none (permanent staff).';

grant select on public.employee_contract_status to authenticated;

-- Headcount per department: drives the list page and the delete guard.
create view public.department_summary
with (security_invoker = true)
as
select
  d.id,
  d.name,
  d.description,
  d.created_at,
  count(e.id) as employee_count,
  count(e.id) filter (where e.is_active) as active_employee_count
from public.departments d
left join public.employees e on e.department_id = d.id
group by d.id, d.name, d.description, d.created_at;

comment on view public.department_summary is 'Departments with assigned headcount. employee_count includes alumni; a department is deletable only at 0.';

grant select on public.department_summary to authenticated;

-- Same gate as every other table: on the HR roster or nothing.
alter table public.departments enable row level security;

create policy departments_select on public.departments
  for select to authenticated using (app_private.is_hr_staff());

create policy departments_insert on public.departments
  for insert to authenticated with check (app_private.is_hr_staff());

create policy departments_update on public.departments
  for update to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

-- Deletion is allowed by policy but still blocked by the employees FK
-- (on delete restrict) whenever anyone is assigned.
create policy departments_delete on public.departments
  for delete to authenticated using (app_private.is_hr_staff());
