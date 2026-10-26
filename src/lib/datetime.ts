/**
 * Everything schedule-related is expressed in the hotel's own timezone, not the
 * server's and not the browser's. A night shift that starts at 23:00 local must
 * read as 23:00 for the night auditor wherever the server happens to run.
 */

export const DAY_MS = 86_400_000;

export const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] as const;

/** ISO date (yyyy-mm-dd) for "today" in the given timezone. */
export function todayIn(timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

/** Monday of the week containing the given ISO date. */
export function weekStart(isoDate: string): string {
  const d = new Date(`${isoDate}T00:00:00Z`);
  // getUTCDay: 0 = Sunday, so Monday-based offset needs the wrap.
  const offset = (d.getUTCDay() + 6) % 7;
  return new Date(d.getTime() - offset * DAY_MS).toISOString().slice(0, 10);
}

export function addDays(isoDate: string, days: number): string {
  return new Date(new Date(`${isoDate}T00:00:00Z`).getTime() + days * DAY_MS)
    .toISOString()
    .slice(0, 10);
}

/** The seven ISO dates of the week starting at `monday`. */
export function weekDates(monday: string): string[] {
  return Array.from({ length: 7 }, (_, i) => addDays(monday, i));
}

export function isValidIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

/** "Mon 27 Oct" for a column heading. */
export function formatDayLabel(isoDate: string): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'UTC',
    weekday: 'short',
    day: '2-digit',
    month: 'short',
  }).format(new Date(`${isoDate}T00:00:00Z`));
}

export function formatWeekRange(monday: string): string {
  const sunday = addDays(monday, 6);
  const fmt = (iso: string) =>
    new Intl.DateTimeFormat('en-GB', {
      timeZone: 'UTC',
      day: '2-digit',
      month: 'short',
    }).format(new Date(`${iso}T00:00:00Z`));
  return `${fmt(monday)} – ${fmt(sunday)}`;
}

/** Clock time of an instant, rendered in the hotel timezone. */
export function formatTimeIn(timestamp: string | null, timeZone: string): string {
  if (!timestamp) return '—';
  const d = new Date(timestamp);
  if (Number.isNaN(d.getTime())) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(d);
}

export function formatDateTimeIn(timestamp: string | null, timeZone: string): string {
  if (!timestamp) return '—';
  const d = new Date(timestamp);
  if (Number.isNaN(d.getTime())) return '—';
  return new Intl.DateTimeFormat('en-GB', {
    timeZone,
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(d);
}

/** "07:00" from a Postgres time value like "07:00:00". */
export function trimSeconds(time: string): string {
  return time.slice(0, 5);
}

export function formatMinutes(total: number | null | undefined): string {
  if (total === null || total === undefined) return '—';
  const sign = total < 0 ? '-' : '';
  const abs = Math.abs(total);
  const h = Math.floor(abs / 60);
  const m = abs % 60;
  if (h === 0) return `${sign}${m}m`;
  return m === 0 ? `${sign}${h}h` : `${sign}${h}h ${m}m`;
}
