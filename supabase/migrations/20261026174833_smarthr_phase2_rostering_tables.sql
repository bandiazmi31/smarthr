-- Single-row property configuration: the geofence anchor and the timezone every
-- shift time is interpreted in.
create table public.hotel_settings (
  id boolean primary key default true check (id),
  hotel_name text not null default 'Smart HR Hotel',
  latitude numeric(9, 6) not null,
  longitude numeric(9, 6) not null,
  geofence_radius_meters integer not null default 100
    check (geofence_radius_meters between 10 and 5000),
  timezone text not null default 'Asia/Jakarta',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

comment on table public.hotel_settings is 'Exactly one row (id = true). Clock-in is rejected beyond geofence_radius_meters of this coordinate.';

-- Placeholder anchor; HR must set the real one on /hr/settings before rollout.
insert into public.hotel_settings (id, latitude, longitude) values (true, -6.175392, 106.827153);

-- Shift definitions. code is the short label the roster grid shows in each cell.
create table public.master_shifts (
  id uuid primary key default gen_random_uuid(),
  name varchar(60) not null,
  code varchar(6) not null,
  start_time time not null,
  end_time time not null,
  is_overnight boolean not null default false,
  grace_period_mins integer not null default 10 check (grace_period_mins between 0 and 120),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  -- An overnight shift must wrap past midnight; a day shift must not.
  constraint master_shifts_overnight_consistent check (
    (is_overnight and end_time <= start_time) or (not is_overnight and end_time > start_time)
  )
);

create unique index master_shifts_name_lower_key on public.master_shifts (lower(name));
create unique index master_shifts_code_lower_key on public.master_shifts (lower(code));

insert into public.master_shifts (name, code, start_time, end_time, is_overnight, grace_period_mins, sort_order) values
  ('Morning',   'M',  '07:00', '15:00', false, 10, 1),
  ('Evening',   'E',  '15:00', '23:00', false, 10, 2),
  ('Night',     'N',  '23:00', '07:00', true,  10, 3),
  ('Middle',    'MD', '11:00', '19:00', false, 10, 4),
  ('Backoffice','BO', '08:00', '17:00', false, 15, 5);

-- The assigned schedule. One shift per employee per logical day, enforced by the
-- unique constraint, which is what makes double-booking impossible.
create table public.rosters (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees (id) on delete cascade,
  shift_id uuid not null references public.master_shifts (id) on delete restrict,
  shift_date date not null,
  expected_clock_in timestamptz not null,
  expected_clock_out timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'in_progress', 'completed', 'absent')),
  note text,
  published_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rosters_one_shift_per_day unique (employee_id, shift_date),
  constraint rosters_window_ordered check (expected_clock_out > expected_clock_in)
);

comment on constraint rosters_one_shift_per_day on public.rosters is 'Phase 2 goal 1: zero overlaps or double-bookings per employee per day.';
comment on column public.rosters.shift_date is 'Logical day the shift belongs to. A night shift ends on the following calendar day.';

create index rosters_shift_date_idx on public.rosters (shift_date);
create index rosters_employee_date_idx on public.rosters (employee_id, shift_date);
create index rosters_window_idx on public.rosters (expected_clock_in);

-- Expected window is derived, never supplied by the caller: an overnight shift
-- rolls the end date forward one day, and both ends are resolved in the hotel's
-- own timezone rather than the server's.
create or replace function app_private.apply_roster_window()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  s record;
  tz text;
begin
  select start_time, end_time, is_overnight into s
  from public.master_shifts where id = new.shift_id;

  if not found then
    raise exception 'Unknown shift %', new.shift_id using errcode = '23503';
  end if;

  select timezone into tz from public.hotel_settings where id;
  tz := coalesce(tz, 'UTC');

  new.expected_clock_in := (new.shift_date + s.start_time) at time zone tz;
  new.expected_clock_out :=
    ((new.shift_date + case when s.is_overnight then 1 else 0 end) + s.end_time) at time zone tz;
  new.updated_at := now();

  return new;
end;
$$;

create trigger rosters_apply_window
  before insert or update of shift_id, shift_date on public.rosters
  for each row execute function app_private.apply_roster_window();

-- Clock-in / clock-out, one record per rostered shift.
create table public.attendance_logs (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null unique references public.rosters (id) on delete cascade,
  clock_in_time timestamptz not null default now(),
  clock_in_lat numeric(9, 6) not null,
  clock_in_long numeric(9, 6) not null,
  clock_in_distance_meters numeric(8, 2),
  clock_in_photo_path text not null,
  clock_out_time timestamptz,
  clock_out_lat numeric(9, 6),
  clock_out_long numeric(9, 6),
  clock_out_distance_meters numeric(8, 2),
  clock_out_photo_path text,
  is_late boolean not null default false,
  late_by_minutes integer not null default 0,
  early_leave_minutes integer not null default 0,
  overtime_minutes integer not null default 0,
  worked_minutes integer,
  created_at timestamptz not null default now(),
  constraint attendance_logs_out_after_in check (
    clock_out_time is null or clock_out_time >= clock_in_time
  )
);

create index attendance_logs_clock_in_idx on public.attendance_logs (clock_in_time);

-- Peer-to-peer shift trades: the target accepts first, then the HOD approves.
create table public.shift_swaps (
  id uuid primary key default gen_random_uuid(),
  requester_roster_id uuid not null references public.rosters (id) on delete cascade,
  target_roster_id uuid not null references public.rosters (id) on delete cascade,
  reason text,
  status text not null default 'pending_target'
    check (status in ('pending_target', 'pending_hod', 'approved', 'rejected', 'cancelled')),
  target_responded_at timestamptz,
  decided_at timestamptz,
  decided_by uuid references auth.users (id) on delete set null,
  decision_note text,
  created_at timestamptz not null default now(),
  constraint shift_swaps_distinct_rosters check (requester_roster_id <> target_roster_id)
);

-- A shift can only be caught up in one live swap at a time, from either side.
create unique index shift_swaps_open_requester_key on public.shift_swaps (requester_roster_id)
  where status in ('pending_target', 'pending_hod');
create unique index shift_swaps_open_target_key on public.shift_swaps (target_roster_id)
  where status in ('pending_target', 'pending_hod');

create index shift_swaps_status_idx on public.shift_swaps (status);
