-- Pin the trigger functions' search_path so a caller-set path cannot redirect
-- the functions they resolve.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.sync_deactivated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
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

-- is_hr_staff must be SECURITY DEFINER (it reads hr_profiles past that table's own
-- RLS), but in `public` it is also reachable as /rest/v1/rpc/is_hr_staff. Move it to
-- an unexposed schema: policies can still call it, the REST API cannot.
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
grant usage on schema app_private to authenticated;

create or replace function app_private.is_hr_staff()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.hr_profiles where id = auth.uid());
$$;

revoke all on function app_private.is_hr_staff() from public, anon;
grant execute on function app_private.is_hr_staff() to authenticated;

-- Repoint every policy at the relocated function.
drop policy hr_profiles_select_self_or_staff on public.hr_profiles;
create policy hr_profiles_select_self_or_staff on public.hr_profiles
  for select to authenticated
  using (id = auth.uid() or app_private.is_hr_staff());

drop policy employees_select on public.employees;
create policy employees_select on public.employees
  for select to authenticated using (app_private.is_hr_staff());

drop policy employees_insert on public.employees;
create policy employees_insert on public.employees
  for insert to authenticated with check (app_private.is_hr_staff());

drop policy employees_update on public.employees;
create policy employees_update on public.employees
  for update to authenticated
  using (app_private.is_hr_staff()) with check (app_private.is_hr_staff());

drop policy employee_documents_select on public.employee_documents;
create policy employee_documents_select on public.employee_documents
  for select to authenticated using (app_private.is_hr_staff());

drop policy employee_documents_insert on public.employee_documents;
create policy employee_documents_insert on public.employee_documents
  for insert to authenticated with check (app_private.is_hr_staff());

drop policy employee_documents_delete on public.employee_documents;
create policy employee_documents_delete on public.employee_documents
  for delete to authenticated using (app_private.is_hr_staff());

drop policy "employee_documents_read" on storage.objects;
create policy "employee_documents_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'employee-documents' and app_private.is_hr_staff());

drop policy "employee_documents_write" on storage.objects;
create policy "employee_documents_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'employee-documents' and app_private.is_hr_staff());

drop policy "employee_documents_remove" on storage.objects;
create policy "employee_documents_remove" on storage.objects
  for delete to authenticated
  using (bucket_id = 'employee-documents' and app_private.is_hr_staff());

drop function public.is_hr_staff();
