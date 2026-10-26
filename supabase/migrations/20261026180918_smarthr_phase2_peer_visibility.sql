-- Swapping needs an employee to see two things they otherwise cannot: a
-- colleague's upcoming shift, and a swap record whose other side belongs to
-- someone else. Both views are security_invoker, so RLS correctly strips the
-- colleague's employee row and the whole joined row disappears.
--
-- Rather than widening RLS on employees (which holds national_id, address and
-- phone), these SECURITY DEFINER functions expose only the few columns the
-- swap screens actually need.

create or replace function public.swappable_shifts()
returns table (
  roster_id uuid,
  employee_id uuid,
  full_name text,
  shift_date date,
  shift_name text,
  shift_code text,
  start_time time,
  end_time time
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.id, r.employee_id, e.full_name, r.shift_date,
         s.name::text, s.code::text, s.start_time, s.end_time
  from public.rosters r
  join public.employees e on e.id = r.employee_id
  join public.master_shifts s on s.id = r.shift_id
  where e.is_active
    and e.department_id = app_private.current_department_id()
    and e.id is distinct from app_private.current_employee_id()
    and r.status = 'scheduled'
    and r.expected_clock_in > now()
  order by r.shift_date, s.start_time;
$$;

comment on function public.swappable_shifts() is 'Colleagues'' upcoming scheduled shifts in the caller''s own department. Name only: no other personal data.';

create or replace function public.my_shift_swaps()
returns table (
  id uuid,
  status text,
  reason text,
  decision_note text,
  created_at timestamptz,
  target_responded_at timestamptz,
  decided_at timestamptz,
  requester_roster_id uuid,
  target_roster_id uuid,
  requester_employee_id uuid,
  requester_name text,
  department_id uuid,
  requester_shift_date date,
  requester_shift_name text,
  requester_shift_code text,
  target_employee_id uuid,
  target_name text,
  target_shift_date date,
  target_shift_name text,
  target_shift_code text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    sw.id, sw.status, sw.reason, sw.decision_note, sw.created_at,
    sw.target_responded_at, sw.decided_at,
    sw.requester_roster_id, sw.target_roster_id,
    rr.employee_id, re.full_name, re.department_id,
    rr.shift_date, rs.name::text, rs.code::text,
    tr.employee_id, te.full_name,
    tr.shift_date, ts.name::text, ts.code::text
  from public.shift_swaps sw
  join public.rosters rr on rr.id = sw.requester_roster_id
  join public.employees re on re.id = rr.employee_id
  join public.master_shifts rs on rs.id = rr.shift_id
  join public.rosters tr on tr.id = sw.target_roster_id
  join public.employees te on te.id = tr.employee_id
  join public.master_shifts ts on ts.id = tr.shift_id
  where
    -- A participant on either side, the department's HOD, or HR.
    app_private.current_employee_id() in (rr.employee_id, tr.employee_id)
    or (app_private.is_hod() and re.department_id = app_private.current_department_id())
    or app_private.is_hr_staff()
  order by sw.created_at desc;
$$;

comment on function public.my_shift_swaps() is 'Swap requests the caller may see: either participant, the department HOD, or HR.';

revoke all on function public.swappable_shifts(), public.my_shift_swaps() from public, anon;
grant execute on function public.swappable_shifts(), public.my_shift_swaps() to authenticated;
