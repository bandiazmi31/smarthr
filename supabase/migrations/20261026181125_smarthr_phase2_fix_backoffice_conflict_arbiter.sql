-- rosters_one_shift_per_day had to become DEFERRABLE so a same-day swap can pass
-- through a momentarily duplicate state. Postgres refuses a deferrable constraint
-- as an ON CONFLICT arbiter ("55000: ON CONFLICT does not support deferrable
-- unique constraints"), which broke this function outright. An anti-join gives
-- the same idempotence without needing an arbiter.
create or replace function public.generate_backoffice_rosters(p_week_start date default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  tz text;
  week_start date;
  created integer;
begin
  select timezone into tz from public.hotel_settings where id;
  tz := coalesce(tz, 'UTC');

  -- Default: the Monday of the coming week, in the hotel's own timezone.
  week_start := coalesce(
    p_week_start,
    (date_trunc('week', ((now() at time zone tz)::date + 7)::timestamp))::date
  );

  insert into public.rosters (employee_id, shift_id, shift_date, expected_clock_in, expected_clock_out, note)
  select
    e.id,
    e.auto_schedule_shift_id,
    week_start + g.offset_days,
    now(),  -- both timestamps are overwritten by the rosters_apply_window trigger
    now(),
    'Auto-generated backoffice schedule'
  from public.employees e
  cross join generate_series(0, 4) as g(offset_days)
  where e.is_active
    and e.auto_schedule_shift_id is not null
    -- Never disturb a day that already has a shift, hand-made or auto.
    and not exists (
      select 1 from public.rosters r
      where r.employee_id = e.id
        and r.shift_date = week_start + g.offset_days
    );

  get diagnostics created = row_count;
  return created;
end;
$$;
