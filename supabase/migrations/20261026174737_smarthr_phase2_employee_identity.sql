-- Phase 2 introduces two new kinds of user: operational staff using the mobile
-- portal, and HODs scheduling their own department. Both are employees, so the
-- identity hangs off the employees row rather than a parallel table.
alter table public.employees
  add column user_id uuid unique references auth.users (id) on delete set null,
  add column portal_enabled boolean not null default false,
  add column role text not null default 'employee' check (role in ('employee', 'hod'));

comment on column public.employees.user_id is 'Linked Supabase Auth account. Set by trigger when the employee signs up with the email on their record.';
comment on column public.employees.portal_enabled is 'HR opt-in. An employee cannot link an account until this is true and an email is on file.';
comment on column public.employees.role is 'Portal role. hod additionally schedules and approves for their own department.';

create index employees_user_id_idx on public.employees (user_id);
create index employees_hod_idx on public.employees (department_id) where role = 'hod';

-- Self sign-up is matched to an existing, HR-enabled employee record by email.
-- Signing up without one succeeds but links nothing, so RLS grants nothing.
create or replace function app_private.link_employee_account()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.employees
  set user_id = new.id
  where user_id is null
    and portal_enabled
    and is_active
    and email is not null
    and lower(btrim(email)) = lower(btrim(new.email));

  return new;
end;
$$;

create trigger link_employee_account_on_signup
  after insert on auth.users
  for each row execute function app_private.link_employee_account();

-- Scope helpers. All SECURITY DEFINER so policies on employees can call them
-- without recursing through employees' own RLS.
create or replace function app_private.current_employee_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from public.employees where user_id = auth.uid() and is_active limit 1;
$$;

create or replace function app_private.current_department_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select department_id from public.employees where user_id = auth.uid() and is_active limit 1;
$$;

create or replace function app_private.is_hod()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.employees
    where user_id = auth.uid() and is_active and role = 'hod'
  );
$$;

create or replace function app_private.is_linked_employee()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.employees where user_id = auth.uid() and is_active
  );
$$;

revoke all on function
  app_private.current_employee_id(),
  app_private.current_department_id(),
  app_private.is_hod(),
  app_private.is_linked_employee()
from public, anon;

grant execute on function
  app_private.current_employee_id(),
  app_private.current_department_id(),
  app_private.is_hod(),
  app_private.is_linked_employee()
to authenticated;

-- Widen reads: an employee sees themselves, a HOD sees their department.
-- HR keeps the existing full-access policy; permissive policies are OR'd.
create policy employees_select_self on public.employees
  for select to authenticated
  using (user_id = auth.uid());

create policy employees_select_own_department on public.employees
  for select to authenticated
  using (app_private.is_hod() and department_id = app_private.current_department_id());

-- Everyone in the portal needs to resolve department names.
create policy departments_select_portal on public.departments
  for select to authenticated
  using (app_private.is_linked_employee());

-- Writes to employees stay HR-only: nobody promotes themselves to hod.
