# Smart HR — Hotel HRIS

Hotel HR system in two parts:

- **Phase 1 — Centralized HRIS.** One register for active staff and alumni, a
  document archive, contract-expiry alerts, department master data, CSV export.
- **Phase 2 — Shift & Attendance Engine.** Weekly rostering for HODs, a mobile
  staff portal (PWA) with geofenced clock-in and a live selfie, peer-to-peer
  shift swaps with HOD approval, and a weekly cron that auto-rosters backoffice
  staff.

**Stack:** Astro (Node SSR) · Supabase (Postgres + Auth + Storage + pg_cron) ·
Tailwind CSS v4

---

## Who can sign in

| Actor | How the account exists | Lands on | Can do |
| --- | --- | --- | --- |
| HR admin | Row in `hr_profiles` (created by SQL script) | `/hr/employees` | Everything |
| HOD | Employee with `role = 'hod'` and a linked account | `/hod/roster` | Roster + approve swaps for **their own department** |
| Employee | Employee with `portal_enabled` and a linked account | `/mobile` | Own shifts, clock in/out, request swaps |

Staff activate themselves at `/mobile/register` using the email on their employee
record; a database trigger links the new auth user to that record. Signing up
without a matching, HR-enabled record succeeds but grants nothing, because every
policy keys off the link.

If staff have no mailbox — or "Confirm email" is on without SMTP — run
`scripts/create-employee-logins.sql` instead. It creates the accounts directly and
the same trigger does the linking.

---

## What Phase 1 does

| Capability | Where |
| --- | --- |
| HR-only sign-in, HTTP-only cookie sessions | `/login`, `src/middleware.ts` |
| Department master data, with delete blocked while in use | `/hr/departments` |
| Employee register: create, read, update, soft delete | `/hr/employees`, `/hr/employees/create`, `/hr/employees/edit/[id]` |
| Document archive (PDF/JPG/PNG → private bucket) | employee detail page |
| Contract alerts for expiry within 30 days | dashboard stat cards + alert panel |
| CSV/Excel export, honouring the active filters | `Export CSV` button |

## What Phase 2 does

| Capability | Where |
| --- | --- |
| Weekly roster grid, one shift per staff member per day | `/hod/roster` |
| Geofence anchor, radius, timezone, shift definitions | `/hr/settings` |
| Staff portal: today's shift, this week, hours and lateness | `/mobile` |
| Clock in/out with GPS + live selfie, no gallery uploads | `/mobile/clock-in` |
| Selfies auto-deleted after 90 days | `purge-attendance-photos` Edge Function |
| Shift swaps: colleague accepts, then HOD approves | `/mobile/swaps` |
| Mon–Fri backoffice rosters generated every Sunday | `pg_cron` → `generate_backoffice_rosters()` |

Out of scope by design (Phase 3+): payroll and service-charge distribution,
leave/PTO workflows.

---

## Running it

```bash
npm install
cp .env.example .env     # fill in SUPABASE_URL and SUPABASE_ANON_KEY
npm run dev              # http://localhost:4321
```

```bash
npm run build && node ./dist/server/entry.mjs   # production, standalone Node server
```

The server reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the environment at
runtime. Neither has a `PUBLIC_` prefix, so neither reaches the browser bundle.

---

## Supabase setup

1. Apply the migrations in `supabase/migrations/` in filename order (Supabase CLI,
   or paste each into the SQL editor).
2. Create the first HR login: edit the email/password/name at the top of
   `scripts/create-hr-admin.sql` and run it in the SQL editor. It needs the `auth`
   schema, which the anon key cannot reach.
3. Optional: run `supabase/seed.sql` for the standard hotel departments plus a demo
   roster spanning every contract state. At minimum you need one department, since
   every employee must reference one.
4. In the dashboard, under **Authentication → Sign In / Providers**:
   - **Turn "Confirm email" off** (or configure SMTP). Staff activation at
     `/mobile/register` uses `signUp`, and with confirmation on, the built-in SMTP
     rate-limits almost immediately. Leaving it on is supported — activation then
     redirects to "check your email" — but it needs real mailboxes.
   - Enable leaked-password protection.
   - Leave email sign-up **enabled**: Phase 2 staff activation depends on it, and an
     account with no matching employee record gets no data.
5. Set the real geofence coordinate on `/hr/settings`. The migration ships a
   placeholder, and clock-in will reject everyone until it is correct.
6. To enable the 90-day selfie purge: set a `PURGE_SECRET` on the
   `purge-attendance-photos` Edge Function, then run
   `scripts/enable-photo-retention.sql`. Until both are done the function refuses
   every request, so nothing is ever deleted by accident.

### Schema

- **`departments`** — the organisational units. Names are unique case-insensitively
  (a unique index on `lower(name)`), so "F&B" and "f&b" cannot coexist. Employees
  reference it via `employees.department_id` with `ON DELETE RESTRICT`, so a
  department in use cannot be deleted; the app checks the headcount first only to
  produce a readable message.
- **`employees`** — one row per person, active or alumni. `is_active` is the soft
  delete; nothing is ever hard-deleted from the app. A `PKWT` row is required by
  CHECK constraint to carry an `end_date`, because a fixed-term contract with no end
  date can never raise a renewal alert.
- **`employee_documents`** — archive metadata. `file_path` holds the object path in
  the private bucket (the PRD calls this `file_url`); the app mints a short-lived
  signed URL per click instead of storing a public link.
- **`hr_profiles`** — the HR roster. This, not mere authentication, is what grants
  data access.
- **`employee_contract_status`** — view over `employees` joined to `departments`. It
  resolves `department` back to the name and adds `days_remaining` and `alert_level`
  (`expired` / `critical` ≤7d / `warning` ≤30d / `ok` / `none`), so the dashboard, the
  filters and the export all count the same way.
- **`department_summary`** — view adding `employee_count` and `active_employee_count`
  per department. Drives the list page and the delete guard.

### Phase 2 schema

- **`master_shifts`** — shift definitions (`Morning`, `Evening`, `Night`, …), each
  with a `code` for the grid, a grace period, and `is_overnight`.
- **`rosters`** — the assigned schedule. `UNIQUE (employee_id, shift_date)` is what
  delivers the PRD's "0 double-bookings per employee per day". `expected_clock_in`
  and `expected_clock_out` are **derived by trigger**, never supplied by the
  caller: an overnight shift adds a day to the end, and both ends resolve in the
  hotel's own timezone.
- **`attendance_logs`** — one row per worked shift: both timestamps, both
  coordinates, both distances, both selfie paths, lateness, overtime, early leave.
- **`shift_swaps`** — `pending_target → pending_hod → approved | rejected`, plus
  `cancelled`. Partial unique indexes stop a shift joining two live swaps at once.
- **`hotel_settings`** — single row holding the geofence anchor, radius and timezone.
- **`roster_details`** / **`shift_swap_details`** / **`portal_identity`** — read
  models for the admin screens.

### Core Phase 2 logic

**Night shifts.** `app_private.apply_roster_window()` computes
`expected_clock_out = (shift_date + 1 day) + end_time` whenever the shift is
flagged overnight, resolved through `hotel_settings.timezone`. A night shift
rostered for 27 Oct runs 27 Oct 23:00 → 28 Oct 07:00 local, and stays filed under
the day it started.

**Geofencing.** `app_private.haversine_meters()` computes great-circle distance;
`clock_in()` rejects anything beyond `geofence_radius_meters` with
*"You are outside the designated clock-in zone."* The check lives in the database,
not the API, so it holds for any caller — the browser's own distance calculation is
advisory only and spoofing it changes nothing.

**Clock-in window.** A shift can only be clocked into from
`hotel_settings.early_clock_in_limit_mins` (default 45) before it starts, so an
early arrival is not logged as premature overtime. The window is checked *before*
the geofence, so someone standing in the lobby an hour early gets the useful
message rather than a location error. Lateness is anything past the shift's
`grace_period_mins` (default 15).

**Photo retention.** Selfies are deleted after `photo_retention_days` (default 90);
the attendance times themselves are kept forever. This runs in an Edge Function
rather than in Postgres because deleting a row from `storage.objects` leaves the
file in the bucket — only the Storage API reclaims the space. See
`scripts/enable-photo-retention.sql`.

**API responses.** The attendance endpoints answer in the caller's content type.
A browser form gets a 303 back to the page; a caller sending
`Accept: application/json` gets a status code — 403 outside the geofence (PRD v2.0
§3.1), 409 too early or already clocked in, 404 unknown shift, 201/200 on success.

Clock-**out** records the distance but does not refuse it. Refusing would strand
someone who has already left the property, producing a worse record than one
flagged for the HOD; off-site clock-outs surface in the UI instead.

**Swaps.** `decide_shift_swap()` trades `employee_id` across the two rosters in a
single statement. `rosters_one_shift_per_day` is `DEFERRABLE` precisely because a
same-day trade passes through a momentarily duplicate state.

The request snapshots both names, dates and shift codes when it is made, and the
roster references are `ON DELETE SET NULL`. The approval trail is the point of the
feature, so it has to outlive the shifts it describes — re-publishing a week must
not erase who agreed to what.

### Security model

- Every table has RLS; every policy routes through `app_private.is_hr_staff()`, which
  checks for a `hr_profiles` row. The function lives in an unexposed schema so it is
  not callable over `/rest/v1/rpc`.
- The `employee-documents` bucket is private, capped at 10 MB, and limited to
  PDF/JPEG/PNG at the bucket level as well as in the upload handler.
- Session tokens live in `HttpOnly`, `SameSite=Lax`, `Secure`-in-production cookies.
  `src/middleware.ts` revalidates the JWT with Supabase on every request, rejects
  cross-site writes, and sets `Cache-Control: private, no-store` on every response.
- The app only ever holds the anon/publishable key. There is no service-role key in
  the codebase, so a compromised app process still cannot read past RLS.
- Phase 2 scoping: an employee reads only their own rows; a HOD only their own
  department; HR everything. Colleague names needed for swaps come from two narrow
  `SECURITY DEFINER` functions (`swappable_shifts`, `my_shift_swaps`) rather than
  widening RLS on `employees`, which holds national ID, address and phone.
- Attendance is written only through `clock_in()` / `clock_out()`; staff have no
  direct insert or update on `attendance_logs`. Selfies go to a private bucket, and
  an employee can delete an upload only while no log references it.

---

## Layout

```
src/
  middleware.ts              auth gate, CSRF guard, no-store headers
  lib/
    supabase.ts              per-request client, cookie wiring, bucket constants
    employees.ts             form parsing + validation mirroring the DB constraints
    departments.ts           department form parsing + constraint messages
    actor.ts                 who is signed in: HR, HOD, employee or nobody
    datetime.ts              week maths + hotel-timezone formatting
    roster.ts                publish-grid parsing
    attendance.ts            selfie decoding, coordinates, storage paths
    query.ts                 directory filters, shared by the page and the export
    flash.ts                 carries rejected submissions across a redirect
    constants.ts format.ts http.ts
  components/                EmployeeForm, AlertBadge, StatusPill, StatCard, Flash
  layouts/                   AppLayout (signed in), AuthLayout (login)
  pages/
    login.astro
    hod/roster.astro         weekly scheduling grid
    mobile/                  index · clock-in · swaps · register  (PWA)
    hr/settings.astro        geofence + shift definitions
    hr/departments/          index (form + table)
    hr/employees/            index · create · edit/[id]
    api/auth/                login · logout
    api/departments/         create · update · delete
    api/employees/           create · update · deactivate · upload-doc ·
                             delete-doc · document-url · export-csv
public/                      manifest.webmanifest, sw.js, offline.html, icons
supabase/migrations/         schema, RLS, storage buckets, functions, cron
supabase/seed.sql            demo roster
scripts/create-hr-admin.sql  bootstrap the first login
```

### Routes

The PRD's route table, as built:

| Route | Method | Purpose |
| --- | --- | --- |
| `/login` | GET | Sign-in page |
| `/hr/departments` | GET | Split-screen master data: form left, table right |
| `/hr/settings` | GET | Geofence, timezone, shift definitions |
| `/hod/roster` | GET | Weekly scheduling grid |
| `/mobile` | GET | Staff portal: today, this week, stats |
| `/mobile/clock-in` | GET | GPS + camera capture |
| `/mobile/swaps` | GET | Request, answer and approve swaps |
| `/mobile/register` | GET | Staff self-activation |
| `/hr/employees` | GET | Directory, stat cards, contract alerts, filters |
| `/hr/employees/create` | GET | New employee form |
| `/hr/employees/edit/[id]` | GET | Edit, documents, deactivate |
| `/api/auth/login` | POST | Verify credentials, set session cookies |
| `/api/auth/logout` | POST | End session, clear cookies |
| `/api/departments/create` | POST | Insert, rejecting duplicate names |
| `/api/departments/update` | POST | Rename / re-describe by id |
| `/api/departments/delete` | POST | Delete, blocked while employees are assigned |
| `/api/employees/create` | POST | Insert |
| `/api/employees/update` | POST | Update by id |
| `/api/employees/deactivate` | POST | Soft delete (`action=reactivate` reverses it) |
| `/api/employees/upload-doc` | POST | Upload to Storage, record metadata |
| `/api/employees/delete-doc` | POST | Remove a document |
| `/api/employees/document-url` | GET | Redirect to a fresh signed URL |
| `/api/employees/export-csv` | GET | CSV download honouring current filters |
| `/api/auth/register` | POST | Staff self-activation |
| `/api/settings/update` | POST | Geofence and timezone |
| `/api/rosters/generate` | POST | Reconcile one department-week |
| `/api/attendance/clock-in` | POST | Upload selfie, then `clock_in()` |
| `/api/attendance/clock-out` | POST | Upload selfie, then `clock_out()` |
| `/api/swaps/request` | POST | Open a swap |
| `/api/swaps/respond` | POST | Colleague accepts/declines; requester withdraws |
| `/api/swaps/approve` | POST | HOD decision; swaps the rosters |

Added beyond the PRD: `document-url` (needed because the bucket is private) and
`deactivate`'s reactivate mode (a soft delete that cannot be undone is a trap).

### Notes on the export

UTF-8 BOM and CRLF line endings so Excel opens Indonesian names correctly on a
double-click. Values starting `= + - @` are prefixed with `'` so a spreadsheet
treats them as text rather than a formula — which is why phone numbers appear as
`'+62 …` in the raw file.
