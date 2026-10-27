-- shift_swaps referenced rosters with ON DELETE CASCADE, so re-publishing a week
-- and clearing a cell destroyed the approval history for that shift. PRD v2.0 §2
-- calls shift_swaps an "audit trail" and goal 3 wants "a clear 3-step digital
-- approval trail", so it must outlive the roster rows it describes.
--
-- Fix: snapshot the human-readable facts when the request is made, and let the
-- roster references go NULL instead of taking the record with them.
alter table public.shift_swaps
  add column requester_name text,
  add column requester_shift_date date,
  add column requester_shift_code text,
  add column target_name text,
  add column target_shift_date date,
  add column target_shift_code text,
  add column department_id uuid references public.departments (id) on delete set null,
  add column requester_employee_id uuid references public.employees (id) on delete set null,
  add column target_employee_id uuid references public.employees (id) on delete set null;

-- Backfill from the rows that still exist.
update public.shift_swaps sw
set requester_name        = re.full_name,
    requester_shift_date  = rr.shift_date,
    requester_shift_code  = rs.code,
    requester_employee_id = rr.employee_id,
    department_id         = re.department_id
from public.rosters rr
join public.employees re on re.id = rr.employee_id
join public.master_shifts rs on rs.id = rr.shift_id
where rr.id = sw.requester_roster_id and sw.requester_name is null;

update public.shift_swaps sw
set target_name        = te.full_name,
    target_shift_date  = tr.shift_date,
    target_shift_code  = ts.code,
    target_employee_id = tr.employee_id
from public.rosters tr
join public.employees te on te.id = tr.employee_id
join public.master_shifts ts on ts.id = tr.shift_id
where tr.id = sw.target_roster_id and sw.target_name is null;

-- Now the references may be dropped without losing the record.
alter table public.shift_swaps
  drop constraint shift_swaps_requester_roster_id_fkey,
  drop constraint shift_swaps_target_roster_id_fkey,
  alter column requester_roster_id drop not null,
  alter column target_roster_id drop not null;

alter table public.shift_swaps
  add constraint shift_swaps_requester_roster_id_fkey
    foreign key (requester_roster_id) references public.rosters (id) on delete set null,
  add constraint shift_swaps_target_roster_id_fkey
    foreign key (target_roster_id) references public.rosters (id) on delete set null;

-- The distinct-rosters check must tolerate NULLs now.
alter table public.shift_swaps drop constraint shift_swaps_distinct_rosters;
alter table public.shift_swaps add constraint shift_swaps_distinct_rosters
  check (
    requester_roster_id is null
    or target_roster_id is null
    or requester_roster_id <> target_roster_id
  );
