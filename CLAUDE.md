# Smart HR — working notes

Hotel HRIS. Phase 1 = employee records; Phase 2 = rostering and attendance.
Astro SSR + Supabase. See `README.md` for setup and the route/schema tables; this
file records the decisions worth knowing before changing anything.

## Ground rules

- **No service-role key anywhere.** The app runs on the anon/publishable key and the
  signed-in admin's JWT. Every query is therefore subject to RLS. If something
  "needs" the service key, the policy is wrong — fix the policy.
- **Soft delete only.** `is_active = false` is how an employee leaves. There is no
  DELETE policy on `employees`; the audit trail is the point of the feature.
- **Departments are master data, not text.** `employees.department_id` is a FK with
  `ON DELETE RESTRICT`. Never reintroduce a free-text department field; the whole
  point is that the name exists in exactly one place.
- **The database is the source of truth for contract state.** `alert_level` and
  `days_remaining` come from the `employee_contract_status` view, not from JS date
  math, so the dashboard, filters and CSV can never disagree. Add new contract logic
  to the view.
- **Validate in both places.** `src/lib/employees.ts` mirrors the CHECK constraints so
  the admin gets a field-level message; the constraints are what actually guarantee it.
- **Attendance rules live in the database.** The geofence test, lateness, overtime
  and the swap state machine are all in `SECURITY DEFINER` functions, so they hold
  for any caller rather than only for requests that happen to go through the API.
  Put new attendance logic there, not in an endpoint.

## Patterns

- `src/middleware.ts` creates the one Supabase client per request and puts it on
  `locals.supabase`. Never construct another one inside a page or endpoint — it would
  read stale cookies if middleware had just refreshed the session.
- Forms POST to `/api/...`, which redirects 303 back to the page. Success messages
  travel as `?ok=<key>` (see `src/components/Flash.astro`); rejected submissions
  travel in a short-lived `smarthr_form` cookie (`src/lib/flash.ts`) so the form can
  re-render with both the errors and what was typed.
- Directory filters live in `src/lib/query.ts` and are shared by the page and the CSV
  export. Add a filter there, not in a page.
- `src/types/database.ts` must use `type`, not `interface`: postgrest-js requires the
  Row/Insert/Update shapes to satisfy `Record<string, unknown>`, and interfaces have
  no implicit index signature.

## Departments

- The `employee_contract_status` view re-exposes the joined name as `department`, so
  display code and the CSV export did not change when the FK landed. Only *filtering*
  moved to `department_id`. The `?department=` query param therefore carries a UUID,
  and `parseFilters` drops anything that isn't one.
- Deletion is guarded twice on purpose: `/api/departments/delete` reads
  `department_summary` to produce the PRD's message, and the FK stops it regardless —
  including if someone is assigned between the check and the delete.
- Uniqueness is the `departments_name_lower_key` index on `lower(name)`, not a plain
  `UNIQUE(name)`, so duplicates differing only in case are rejected (PRD §4.1).

## Phase 2: identity and scope

- There is no separate user table. `employees.user_id` links to `auth.users`;
  `portal_enabled` is HR's opt-in and `role` ('employee' | 'hod') is the portal
  role. HR admins remain in `hr_profiles`; an account can be both.
- `src/lib/actor.ts` resolves this once in middleware into `locals.actor`. Pages
  read `actor.isHr` / `actor.isHod` / `actor.employee`, never re-query identity.
- Route permissions are one function, `isAllowed()` in `src/middleware.ts`. Add new
  areas there rather than checking roles inside a page.
- The link happens in a trigger on `auth.users`, matching the signup email to an
  enabled employee record. An account with no match signs in to nothing.

## Phase 2: things that will bite you

- **Views are `security_invoker`, so a join to a row the caller cannot read drops
  the whole row.** This is why swaps use `swappable_shifts()` and
  `my_shift_swaps()` (both `SECURITY DEFINER`, exposing only names): a plain view
  silently returned zero colleagues. Reach for a narrow definer function before
  widening RLS on `employees` — that table holds national ID, address and phone.
- **`rosters_one_shift_per_day` is DEFERRABLE**, so a same-day swap can pass through
  a duplicate state inside `decide_shift_swap`. The cost: Postgres refuses a
  deferrable constraint as an `ON CONFLICT` arbiter, so anything upserting rosters
  must use a `NOT EXISTS` anti-join instead. `generate_backoffice_rosters` learned
  this the hard way.
- **Never write `expected_clock_in` / `expected_clock_out` by hand.** The
  `rosters_apply_window` trigger derives both from the shift definition and
  `hotel_settings.timezone`, including the +1 day for overnight shifts. Inserts
  still have to pass *something* for the NOT NULL columns; `now()` is conventional
  and is immediately overwritten.
- **A clock-in uploads the selfie before calling `clock_in()`.** If the call is then
  refused the API deletes the upload — which only works because of the
  `attendance_photos_remove_orphan` policy, scoped to objects no log references.
  Don't grant staff a broader delete on that bucket; the photos are evidence.
- **Supabase Auth rejects reserved TLDs** such as `.example`, so demo emails use
  `@smarthrhotel.com`. Staff activation also needs "Confirm email" off, or real
  mailboxes — otherwise the built-in SMTP rate-limits signup immediately.

## Phase 2 v2.0 additions

- `hotel_settings` now carries three policy knobs, not one: `geofence_radius_meters`,
  `early_clock_in_limit_mins` (45) and `photo_retention_days` (90). Put new
  attendance policy there rather than hard-coding it.
- `clock_in()` checks the early window **before** the geofence, deliberately: an
  employee waiting in the lobby should be told the shift has not opened, not that
  their location is wrong.
- The attendance endpoints content-negotiate. `wantsJson()` in `src/lib/http.ts`
  decides, and `statusForDbError()` maps the SQLSTATE the functions raise onto an
  HTTP status. If you add a new `raise exception`, give it a SQLSTATE and add it
  there, or API clients get a generic 400.
- `clock_in_photo_path` is now nullable — the retention job clears it. Anything
  rendering a selfie must handle null and check `photos_purged_at`.
- `supabase/functions` is excluded from `tsconfig.json`: it runs on Deno with its
  own globals and `jsr:` imports, so `astro check` cannot type-check it.
- The retention job is the one place a service-role key exists, and it is injected
  by the platform into the Edge Function — never in the repo, never in `.env`,
  never reachable by the Astro app. The ground rule above still holds for the app.
- **`shift_swaps` is an audit record, so it snapshots itself.** Both names, both
  dates, both shift codes, both employee ids and the department are written at
  request time; the roster FKs are `ON DELETE SET NULL`. They used to be
  `ON DELETE CASCADE`, which meant clearing a cell in the roster grid silently
  destroyed the approval history for that shift. Read swaps through
  `my_shift_swaps()` or the snapshot columns — never by joining `rosters`, which
  may be gone — and `decide_shift_swap` refuses cleanly when either side is NULL.

## Gotchas

- `@apply` in Tailwind v4 cannot reference a class defined in `@layer components`.
  The shared button base is declared with `@utility btn` in `src/styles/global.css`
  for exactly this reason.
- Creating an auth user by hand in SQL must set `confirmation_token`,
  `recovery_token`, `email_change*`, `phone_change*` and `reauthentication_token` to
  `''`, not NULL. GoTrue scans them into non-nullable strings, and a NULL turns every
  sign-in into `Database error querying schema`.
- Document links must go through `/api/employees/document-url`, never a stored URL —
  the bucket is private and signed URLs expire in five minutes.
- `describeDbError` returns a `FieldErrors` map, not a string, so a constraint
  violation renders next to the field that caused it. Add new constraint codes there
  rather than defaulting everything onto the staff-number field.
- Dropping a column that a view selects fails even with the view listed later in the
  same migration — drop the view first. The departments migration does exactly that.
- The login form must not default `redirect` to an HR path: HR, HOD and staff each
  have a different home and `/api/auth/login` already picks it. Hardcoding one
  bounced the other two through a "not permitted" redirect.
- The service worker caches only the offline shell. Attendance is live, geofenced
  and legally significant, so nothing under `/api` or `/mobile` may be served from
  cache.

## Checks

```bash
npx astro check   # types, including .astro frontmatter
npm run build
```
