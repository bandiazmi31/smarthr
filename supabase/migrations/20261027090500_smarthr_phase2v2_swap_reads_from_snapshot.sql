-- Record the snapshot at request time, and read swaps back from it so a closed
-- request still renders after its shifts are re-published or deleted.
create or replace function public.request_shift_swap(
  p_requester_roster_id uuid,
  p_target_roster_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  mine record;
  theirs record;
  swap_id uuid;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  select r.*, e.department_id, e.full_name, s.code as shift_code into mine
  from public.rosters r
  join public.employees e on e.id = r.employee_id
  join public.master_shifts s on s.id = r.shift_id
  where r.id = p_requester_roster_id;

  if not found or mine.employee_id <> me then
    raise exception 'That is not one of your shifts.' using errcode = '42501';
  end if;

  select r.*, e.department_id, e.full_name, s.code as shift_code into theirs
  from public.rosters r
  join public.employees e on e.id = r.employee_id
  join public.master_shifts s on s.id = r.shift_id
  where r.id = p_target_roster_id;

  if not found then
    raise exception 'The colleague''s shift could not be found.' using errcode = 'P0002';
  end if;

  if theirs.employee_id = me then
    raise exception 'Pick a colleague''s shift, not your own.' using errcode = 'P0001';
  end if;

  if theirs.department_id <> mine.department_id then
    raise exception 'Shifts can only be swapped within the same department.' using errcode = 'P0001';
  end if;

  if mine.status <> 'scheduled' or theirs.status <> 'scheduled' then
    raise exception 'Only shifts that have not started can be swapped.' using errcode = 'P0001';
  end if;

  if mine.expected_clock_in <= now() or theirs.expected_clock_in <= now() then
    raise exception 'Both shifts must still be in the future.' using errcode = 'P0001';
  end if;

  insert into public.shift_swaps (
    requester_roster_id, target_roster_id, reason,
    requester_employee_id, requester_name, requester_shift_date, requester_shift_code,
    target_employee_id, target_name, target_shift_date, target_shift_code, department_id
  ) values (
    p_requester_roster_id, p_target_roster_id,
    nullif(btrim(coalesce(p_reason, '')), ''),
    mine.employee_id, mine.full_name, mine.shift_date, mine.shift_code,
    theirs.employee_id, theirs.full_name, theirs.shift_date, theirs.shift_code,
    mine.department_id
  )
  returning id into swap_id;

  return swap_id;
end;
$$;

create or replace function public.my_shift_swaps()
returns table (
  id uuid, status text, reason text, decision_note text,
  created_at timestamptz, target_responded_at timestamptz, decided_at timestamptz,
  requester_roster_id uuid, target_roster_id uuid,
  requester_employee_id uuid, requester_name text, department_id uuid,
  requester_shift_date date, requester_shift_name text, requester_shift_code text,
  target_employee_id uuid, target_name text,
  target_shift_date date, target_shift_name text, target_shift_code text
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
    sw.requester_employee_id, sw.requester_name, sw.department_id,
    sw.requester_shift_date,
    coalesce(rs.name, sw.requester_shift_code)::text, sw.requester_shift_code,
    sw.target_employee_id, sw.target_name,
    sw.target_shift_date,
    coalesce(ts.name, sw.target_shift_code)::text, sw.target_shift_code
  from public.shift_swaps sw
  left join public.master_shifts rs on lower(rs.code) = lower(sw.requester_shift_code)
  left join public.master_shifts ts on lower(ts.code) = lower(sw.target_shift_code)
  where
    app_private.current_employee_id() in (sw.requester_employee_id, sw.target_employee_id)
    or (app_private.is_hod() and sw.department_id = app_private.current_department_id())
    or app_private.is_hr_staff()
  order by sw.created_at desc;
$$;

-- decide_shift_swap still needs live rosters to perform the trade, but reads the
-- department from the snapshot so a half-deleted pair fails cleanly.
create or replace function public.decide_shift_swap(
  p_swap_id uuid,
  p_approve boolean,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sw record;
  requester_employee uuid;
  target_employee uuid;
begin
  select * into sw from public.shift_swaps where id = p_swap_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  if not (
    app_private.is_hr_staff()
    or (app_private.is_hod() and sw.department_id = app_private.current_department_id())
  ) then
    raise exception 'Only the department head or HR can decide this.' using errcode = '42501';
  end if;

  if sw.status <> 'pending_hod' then
    raise exception 'This request is not awaiting approval.' using errcode = 'P0001';
  end if;

  if not p_approve then
    update public.shift_swaps
    set status = 'rejected', decided_at = now(), decided_by = auth.uid(),
        decision_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = p_swap_id;
    return 'rejected';
  end if;

  -- Either shift may have been re-published away since the request was made.
  if sw.requester_roster_id is null or sw.target_roster_id is null then
    raise exception 'One of these shifts no longer exists. Ask for a fresh request.'
      using errcode = 'P0001';
  end if;

  select employee_id into requester_employee from public.rosters where id = sw.requester_roster_id;
  select employee_id into target_employee from public.rosters where id = sw.target_roster_id;

  if requester_employee is null or target_employee is null then
    raise exception 'One of these shifts no longer exists. Ask for a fresh request.'
      using errcode = 'P0001';
  end if;

  set constraints public.rosters_one_shift_per_day deferred;

  update public.rosters
  set employee_id = case
        when id = sw.requester_roster_id then target_employee
        else requester_employee
      end,
      updated_at = now()
  where id in (sw.requester_roster_id, sw.target_roster_id);

  update public.shift_swaps
  set status = 'approved', decided_at = now(), decided_by = auth.uid(),
      decision_note = nullif(btrim(coalesce(p_note, '')), '')
  where id = p_swap_id;

  return 'approved';
end;
$$;
