-- Access gate: authenticated AND on the HR roster.
create or replace function public.is_hr_staff()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.hr_profiles where id = auth.uid());
$$;

revoke all on function public.is_hr_staff() from public, anon;
grant execute on function public.is_hr_staff() to authenticated;

alter table public.hr_profiles enable row level security;
alter table public.employees enable row level security;
alter table public.employee_documents enable row level security;

-- HR staff may read the roster (to show "who am I"); nobody edits it from the app.
create policy hr_profiles_select_self_or_staff on public.hr_profiles
  for select to authenticated
  using (id = auth.uid() or public.is_hr_staff());

-- Employees: full CRUD for HR staff only. Hard deletes are intentionally not granted;
-- removal happens through the is_active soft delete.
create policy employees_select on public.employees
  for select to authenticated using (public.is_hr_staff());

create policy employees_insert on public.employees
  for insert to authenticated with check (public.is_hr_staff());

create policy employees_update on public.employees
  for update to authenticated
  using (public.is_hr_staff()) with check (public.is_hr_staff());

-- Documents follow their employee.
create policy employee_documents_select on public.employee_documents
  for select to authenticated using (public.is_hr_staff());

create policy employee_documents_insert on public.employee_documents
  for insert to authenticated with check (public.is_hr_staff());

create policy employee_documents_delete on public.employee_documents
  for delete to authenticated using (public.is_hr_staff());

-- Contract expiry intelligence, computed in the database so every caller agrees.
create view public.employee_contract_status
with (security_invoker = true)
as
select
  e.*,
  case when e.end_date is null then null else (e.end_date - current_date) end as days_remaining,
  case
    when e.end_date is null then 'none'
    when e.end_date < current_date then 'expired'
    when e.end_date - current_date <= 7 then 'critical'
    when e.end_date - current_date <= 30 then 'warning'
    else 'ok'
  end as alert_level
from public.employees e;

comment on view public.employee_contract_status is 'Employees with contract countdown. alert_level: expired | critical (<=7d) | warning (<=30d) | ok | none (permanent staff).';

grant select on public.employee_contract_status to authenticated;
