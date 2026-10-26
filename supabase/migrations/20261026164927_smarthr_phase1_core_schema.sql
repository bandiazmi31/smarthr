-- Smart HR Phase 1: core HRIS schema
-- HR admin roster: a Supabase Auth user only gains data access once listed here.
create table public.hr_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role text not null default 'hr_admin' check (role in ('hr_admin', 'hr_manager')),
  created_at timestamptz not null default now()
);

comment on table public.hr_profiles is 'Allow-list of HR staff permitted to use Smart HR. Membership here, not mere authentication, grants access.';

-- Core employee entity (active + alumni).
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  employee_id text not null unique,
  full_name text not null,
  phone text,
  national_id text,
  email text,
  address text,
  birth_date date,
  department text not null,
  job_title text not null,
  employment_status text not null check (employment_status in ('PKWT', 'PKWTT', 'Daily Worker')),
  join_date date not null,
  end_date date,
  is_active boolean not null default true,
  deactivated_at timestamptz,
  deactivation_reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users (id) on delete set null,
  constraint employees_end_date_after_join check (end_date is null or end_date >= join_date),
  constraint employees_fixed_term_needs_end_date check (employment_status <> 'PKWT' or end_date is not null),
  constraint employees_employee_id_not_blank check (length(btrim(employee_id)) > 0),
  constraint employees_full_name_not_blank check (length(btrim(full_name)) > 0)
);

comment on column public.employees.employee_id is 'Internal hotel staff number, unique across active and alumni records.';
comment on column public.employees.is_active is 'Soft delete flag. False = alumni; the row is retained for the audit trail.';

create index employees_is_active_idx on public.employees (is_active);
create index employees_department_idx on public.employees (department);
create index employees_end_date_idx on public.employees (end_date) where is_active and end_date is not null;
create index employees_full_name_idx on public.employees (lower(full_name));

-- Digital document archive. Files live in the private 'employee-documents' storage bucket;
-- file_path holds the object path (the PRD's file_url) and signed URLs are minted per request.
create table public.employee_documents (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  document_type text not null check (
    document_type in ('ID Card', 'Contract', 'Certificate', 'Tax Card', 'Health Insurance', 'Other')
  ),
  file_path text not null unique,
  file_name text not null,
  mime_type text,
  file_size bigint,
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid references auth.users (id) on delete set null
);

create index employee_documents_employee_id_idx on public.employee_documents (employee_id);

-- Keep updated_at honest.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger employees_touch_updated_at
  before update on public.employees
  for each row execute function public.touch_updated_at();

-- Stamp/clear the soft-delete timestamp automatically.
create or replace function public.sync_deactivated_at()
returns trigger
language plpgsql
as $$
begin
  if new.is_active = false and (old.is_active is distinct from false) then
    new.deactivated_at := coalesce(new.deactivated_at, now());
  elsif new.is_active = true then
    new.deactivated_at := null;
    new.deactivation_reason := null;
  end if;
  return new;
end;
$$;

create trigger employees_sync_deactivated_at
  before update on public.employees
  for each row execute function public.sync_deactivated_at();
