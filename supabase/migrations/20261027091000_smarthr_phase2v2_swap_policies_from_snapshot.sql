-- The swap policies reached through rosters to decide who may read a request.
-- Once a roster can be NULL that hides the participant's own history, so the
-- policies now key off the snapshotted employee and department ids.
drop policy shift_swaps_select_participant on public.shift_swaps;
create policy shift_swaps_select_participant on public.shift_swaps
  for select to authenticated
  using (
    app_private.current_employee_id() in (requester_employee_id, target_employee_id)
  );

drop policy shift_swaps_select_department on public.shift_swaps;
create policy shift_swaps_select_department on public.shift_swaps
  for select to authenticated
  using (
    app_private.is_hod() and department_id = app_private.current_department_id()
  );

-- Same for the two workflow functions that identified the parties via rosters.
create or replace function public.respond_shift_swap(p_swap_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  sw record;
begin
  select * into sw from public.shift_swaps where id = p_swap_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  if me is null or sw.target_employee_id is distinct from me then
    raise exception 'Only the colleague being asked can answer this request.' using errcode = '42501';
  end if;

  if sw.status <> 'pending_target' then
    raise exception 'This request has already been answered.' using errcode = 'P0001';
  end if;

  update public.shift_swaps
  set status = case when p_accept then 'pending_hod' else 'rejected' end,
      target_responded_at = now()
  where id = p_swap_id;

  return case when p_accept then 'pending_hod' else 'rejected' end;
end;
$$;

create or replace function public.cancel_shift_swap(p_swap_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  sw record;
begin
  select * into sw from public.shift_swaps where id = p_swap_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  if me is null or sw.requester_employee_id is distinct from me then
    raise exception 'Only the requester can withdraw this.' using errcode = '42501';
  end if;

  if sw.status not in ('pending_target', 'pending_hod') then
    raise exception 'This request is already closed.' using errcode = 'P0001';
  end if;

  update public.shift_swaps set status = 'cancelled', decided_at = now() where id = p_swap_id;
  return 'cancelled';
end;
$$;

-- Rebuilt from the snapshot so it no longer drops rows when a participant's
-- employee record is unreadable to the caller, or a roster has been removed.
-- (The old join silently zeroed the staff dashboard's "swap waiting" badge.)
drop view public.shift_swap_details;

create view public.shift_swap_details
with (security_invoker = true)
as
select
  sw.id, sw.status, sw.reason, sw.decision_note, sw.created_at,
  sw.target_responded_at, sw.decided_at,
  sw.requester_roster_id, sw.target_roster_id,
  sw.requester_employee_id, sw.requester_name, sw.department_id,
  sw.requester_shift_date, sw.requester_shift_code,
  sw.target_employee_id, sw.target_name,
  sw.target_shift_date, sw.target_shift_code
from public.shift_swaps sw;

comment on view public.shift_swap_details is 'Swap requests as recorded at request time. Survives deletion of the rosters it describes.';

grant select on public.shift_swap_details to authenticated;
