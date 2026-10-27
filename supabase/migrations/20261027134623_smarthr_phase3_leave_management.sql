-- Annual quota per employee per year. One row is created lazily the first time
-- an employee touches leave in a given year, from the current policy.
create table public.leave_balances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  year integer not null check (year between 2000 and 2100),
  annual_allocated numeric(6, 2) not null default 0 check (annual_allocated >= 0),
  annual_used numeric(6, 2) not null default 0 check (annual_used >= 0),
  sick_used numeric(6, 2) not null default 0 check (sick_used >= 0),
  unpaid_used numeric(6, 2) not null default 0 check (unpaid_used >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint leave_balances_employee_year_key unique (employee_id, year)
);

comment on column public.leave_balances.annual_allocated is 'Entitlement for the year, seeded from hotel_settings.annual_leave_days and adjustable by HR for carry-over.';

create table public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  department_id uuid references public.departments (id) on delete set null,
  leave_type text not null check (leave_type in ('Annual', 'Sick', 'Unpaid')),
  start_date date not null,
  end_date date not null,
  days_count numeric(6, 2) not null check (days_count > 0),
  reason text,
  -- Medical certificate, in the private leave-documents bucket.
  document_path text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  decided_by uuid references auth.users (id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  constraint leave_requests_range_ordered check (end_date >= start_date)
);

create index leave_requests_employee_idx on public.leave_requests (employee_id, start_date);
create index leave_requests_department_idx on public.leave_requests (department_id, status);
create index leave_requests_range_idx on public.leave_requests (start_date, end_date);

comment on column public.leave_requests.days_count is 'Calendar days in the range, inclusive. Deliberately not working-days-only: a future range may have no roster published yet, which would make the leave cost nothing.';

-- Private bucket for medical certificates.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('leave-documents', 'leave-documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "leave_documents_write_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'leave-documents'
    and (storage.foldername(name))[1] = app_private.current_employee_id()::text
  );

create policy "leave_documents_read_own" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'leave-documents'
    and (storage.foldername(name))[1] = app_private.current_employee_id()::text
  );

create policy "leave_documents_read_hr" on storage.objects
  for select to authenticated
  using (bucket_id = 'leave-documents' and app_private.is_hr_staff());

create policy "leave_documents_read_hod" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'leave-documents'
    and app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id::text = (storage.foldername(name))[1]
        and e.department_id = app_private.current_department_id()
    )
  );

-- Same orphan rule as the attendance selfies: an upload nothing references yet
-- may be cleaned up, a referenced certificate may not.
create or replace function app_private.leave_doc_is_referenced(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.leave_requests where document_path = p_name);
$$;

revoke all on function app_private.leave_doc_is_referenced(text) from public, anon;
grant execute on function app_private.leave_doc_is_referenced(text) to authenticated;

create policy "leave_documents_remove_orphan" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'leave-documents'
    and (storage.foldername(name))[1] = app_private.current_employee_id()::text
    and not app_private.leave_doc_is_referenced(name)
  );

alter table public.leave_balances enable row level security;
alter table public.leave_requests enable row level security;

create policy leave_balances_select_self on public.leave_balances
  for select to authenticated
  using (employee_id = app_private.current_employee_id());

create policy leave_balances_select_department on public.leave_balances
  for select to authenticated
  using (
    app_private.is_hod()
    and exists (
      select 1 from public.employees e
      where e.id = leave_balances.employee_id
        and e.department_id = app_private.current_department_id()
    )
  );

create policy leave_balances_hr on public.leave_balances
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

create policy leave_requests_select_self on public.leave_requests
  for select to authenticated
  using (employee_id = app_private.current_employee_id());

create policy leave_requests_select_department on public.leave_requests
  for select to authenticated
  using (app_private.is_hod() and department_id = app_private.current_department_id());

create policy leave_requests_hr on public.leave_requests
  for all to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

-- Writes go through the workflow functions in the next migration, never
-- straight from the app.
