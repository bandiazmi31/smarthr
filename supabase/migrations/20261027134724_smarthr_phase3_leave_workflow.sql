-- Creates this year's balance row on demand, seeded from current policy.
create or replace function app_private.ensure_leave_balance(p_employee_id uuid, p_year integer)
returns public.leave_balances
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  row_out public.leave_balances;
begin
  select * into row_out
  from public.leave_balances
  where employee_id = p_employee_id and year = p_year;

  if found then
    return row_out;
  end if;

  insert into public.leave_balances (employee_id, year, annual_allocated)
  values (p_employee_id, p_year, (select annual_leave_days from public.hotel_settings where id))
  on conflict (employee_id, year) do nothing;

  select * into row_out
  from public.leave_balances
  where employee_id = p_employee_id and year = p_year;

  return row_out;
end;
$$;

create or replace function public.my_leave_balance(p_year integer default null)
returns table (
  year integer,
  annual_allocated numeric,
  annual_used numeric,
  annual_remaining numeric,
  sick_used numeric,
  unpaid_used numeric
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  tz text;
  target_year integer;
  bal public.leave_balances;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  select timezone into tz from public.hotel_settings where id;
  target_year := coalesce(p_year, extract(year from (now() at time zone coalesce(tz, 'UTC')))::integer);

  bal := app_private.ensure_leave_balance(me, target_year);

  return query
  select bal.year, bal.annual_allocated, bal.annual_used,
         bal.annual_allocated - bal.annual_used,
         bal.sick_used, bal.unpaid_used;
end;
$$;

-- PRD v3 §3.1. Ratio is (scheduled - approved leave) / total department staff,
-- exactly as specified, so the HOD sees the number the document describes.
-- NOTE: the authorisation guard is added in 20261027135030.
create or replace function public.leave_coverage(p_department_id uuid, p_date date)
returns table (
  total_staff integer,
  scheduled integer,
  on_leave integer,
  effective integer,
  ratio_pct integer,
  below_threshold boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with staff as (
    select count(*)::integer as n
    from public.employees e
    where e.is_active and e.department_id = p_department_id
  ),
  sched as (
    select count(*)::integer as n
    from public.rosters r
    join public.employees e on e.id = r.employee_id
    where e.department_id = p_department_id
      and r.shift_date = p_date
      and r.status <> 'absent'
  ),
  away as (
    select count(distinct lr.employee_id)::integer as n
    from public.leave_requests lr
    where lr.department_id = p_department_id
      and lr.status = 'approved'
      and p_date between lr.start_date and lr.end_date
  )
  select
    staff.n, sched.n, away.n,
    greatest(0, sched.n - away.n),
    case when staff.n = 0 then 0
         else floor(greatest(0, sched.n - away.n)::numeric * 100 / staff.n)::integer end,
    case when staff.n = 0 then false
         else floor(greatest(0, sched.n - away.n)::numeric * 100 / staff.n)
              < (select leave_coverage_threshold_pct from public.hotel_settings where id) end
  from staff, sched, away;
$$;

create or replace function public.request_leave(
  p_leave_type text,
  p_start_date date,
  p_end_date date,
  p_reason text default null,
  p_document_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  dept uuid := app_private.current_department_id();
  cfg record;
  tz text;
  today date;
  days numeric;
  bal public.leave_balances;
  new_id uuid;
begin
  if me is null then
    raise exception 'No employee record is linked to this account.' using errcode = '28000';
  end if;

  if p_leave_type not in ('Annual', 'Sick', 'Unpaid') then
    raise exception 'Unknown leave type.' using errcode = 'P0001';
  end if;

  if p_end_date < p_start_date then
    raise exception 'The end date cannot fall before the start date.' using errcode = 'P0001';
  end if;

  select * into cfg from public.hotel_settings where id;
  tz := coalesce(cfg.timezone, 'UTC');
  today := (now() at time zone tz)::date;

  -- Sick leave is routinely filed after the fact; planned leave is not.
  if p_leave_type = 'Sick' then
    if p_start_date < today - 30 then
      raise exception 'Sick leave cannot be backdated more than 30 days.' using errcode = 'P0001';
    end if;
  elsif p_start_date < today then
    raise exception 'Leave cannot start in the past.' using errcode = 'P0001';
  end if;

  days := (p_end_date - p_start_date) + 1;

  -- PRD v3 §4.1: a longer sick absence needs a medical certificate.
  if p_leave_type = 'Sick'
     and days > cfg.sick_cert_required_after_days
     and coalesce(btrim(p_document_path), '') = '' then
    raise exception
      'Sick leave of more than % day(s) needs a medical certificate attached.',
      cfg.sick_cert_required_after_days
      using errcode = 'P0004';
  end if;

  if exists (
    select 1 from public.leave_requests lr
    where lr.employee_id = me
      and lr.status in ('pending', 'approved')
      and daterange(lr.start_date, lr.end_date, '[]')
          && daterange(p_start_date, p_end_date, '[]')
  ) then
    raise exception 'You already have a leave request covering those dates.'
      using errcode = '23505';
  end if;

  if p_leave_type = 'Annual' then
    bal := app_private.ensure_leave_balance(me, extract(year from p_start_date)::integer);
    if bal.annual_allocated - bal.annual_used < days then
      raise exception
        'Not enough annual leave: % day(s) remaining, % requested.',
        bal.annual_allocated - bal.annual_used, days
        using errcode = 'P0005';
    end if;
  end if;

  insert into public.leave_requests (
    employee_id, department_id, leave_type, start_date, end_date,
    days_count, reason, document_path
  ) values (
    me, dept, p_leave_type, p_start_date, p_end_date,
    days, nullif(btrim(coalesce(p_reason, '')), ''),
    nullif(btrim(coalesce(p_document_path, '')), '')
  )
  returning id into new_id;

  return new_id;
end;
$$;

-- HOD or HR decision. Approval is where the balance actually moves.
create or replace function public.decide_leave_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  req public.leave_requests;
  bal public.leave_balances;
begin
  select * into req from public.leave_requests where id = p_request_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  if not (
    app_private.is_hr_staff()
    or (app_private.is_hod() and req.department_id = app_private.current_department_id())
  ) then
    raise exception 'Only the department head or HR can decide this.' using errcode = '42501';
  end if;

  if req.status <> 'pending' then
    raise exception 'This request has already been decided.' using errcode = 'P0001';
  end if;

  if not p_approve then
    update public.leave_requests
    set status = 'rejected', decided_at = now(), decided_by = auth.uid(),
        decision_note = nullif(btrim(coalesce(p_note, '')), '')
    where id = p_request_id;
    return 'rejected';
  end if;

  bal := app_private.ensure_leave_balance(
    req.employee_id, extract(year from req.start_date)::integer
  );

  -- Re-check at approval: another request may have consumed the balance since.
  if req.leave_type = 'Annual'
     and bal.annual_allocated - bal.annual_used < req.days_count then
    raise exception
      'Not enough annual leave left to approve this: % day(s) remaining, % requested.',
      bal.annual_allocated - bal.annual_used, req.days_count
      using errcode = 'P0005';
  end if;

  update public.leave_balances
  set annual_used = annual_used + case when req.leave_type = 'Annual' then req.days_count else 0 end,
      sick_used   = sick_used   + case when req.leave_type = 'Sick'   then req.days_count else 0 end,
      unpaid_used = unpaid_used + case when req.leave_type = 'Unpaid' then req.days_count else 0 end,
      updated_at = now()
  where id = bal.id;

  update public.leave_requests
  set status = 'approved', decided_at = now(), decided_by = auth.uid(),
      decision_note = nullif(btrim(coalesce(p_note, '')), '')
  where id = p_request_id;

  return 'approved';
end;
$$;

-- The requester withdraws while pending; HR may cancel an approved one, which
-- returns the days to the balance.
create or replace function public.cancel_leave_request(p_request_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := app_private.current_employee_id();
  req public.leave_requests;
begin
  select * into req from public.leave_requests where id = p_request_id;
  if not found then
    raise exception 'That request could not be found.' using errcode = 'P0002';
  end if;

  if req.status = 'pending' then
    if not (req.employee_id = me or app_private.is_hr_staff()) then
      raise exception 'Only the requester or HR can withdraw this.' using errcode = '42501';
    end if;
  elsif req.status = 'approved' then
    if not app_private.is_hr_staff() then
      raise exception 'Only HR can cancel leave that has already been approved.'
        using errcode = '42501';
    end if;

    update public.leave_balances b
    set annual_used = greatest(0, b.annual_used - case when req.leave_type = 'Annual' then req.days_count else 0 end),
        sick_used   = greatest(0, b.sick_used   - case when req.leave_type = 'Sick'   then req.days_count else 0 end),
        unpaid_used = greatest(0, b.unpaid_used - case when req.leave_type = 'Unpaid' then req.days_count else 0 end),
        updated_at = now()
    where b.employee_id = req.employee_id
      and b.year = extract(year from req.start_date)::integer;
  else
    raise exception 'This request is already closed.' using errcode = 'P0001';
  end if;

  update public.leave_requests
  set status = 'cancelled', decided_at = now(), decided_by = auth.uid()
  where id = p_request_id;

  return 'cancelled';
end;
$$;

revoke all on function
  public.my_leave_balance(integer),
  public.leave_coverage(uuid, date),
  public.request_leave(text, date, date, text, text),
  public.decide_leave_request(uuid, boolean, text),
  public.cancel_leave_request(uuid)
from public, anon;

grant execute on function
  public.my_leave_balance(integer),
  public.leave_coverage(uuid, date),
  public.request_leave(text, date, date, text, text),
  public.decide_leave_request(uuid, boolean, text),
  public.cancel_leave_request(uuid)
to authenticated;
