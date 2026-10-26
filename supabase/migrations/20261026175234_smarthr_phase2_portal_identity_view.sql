-- Who the signed-in portal user is, in one read: middleware resolves this on
-- every request, so it should not need a second round trip for the department.
create view public.portal_identity
with (security_invoker = true)
as
select
  e.id,
  e.user_id,
  e.employee_id as staff_number,
  e.full_name,
  e.job_title,
  e.role,
  e.department_id,
  d.name as department_name,
  e.auto_schedule_shift_id,
  e.portal_enabled
from public.employees e
join public.departments d on d.id = e.department_id
where e.is_active;

comment on view public.portal_identity is 'Active employees with their department resolved. Filtered by user_id to identify the caller.';

grant select on public.portal_identity to authenticated;
