import { isValidIsoDate, weekDates } from './datetime';

/** One cell of the publish grid: an employee, a date, and a chosen shift (or none). */
export interface RosterAssignment {
  employeeId: string;
  shiftDate: string;
  shiftId: string | null;
}

export type PublishParseResult =
  | { ok: true; weekStart: string; assignments: RosterAssignment[] }
  | { ok: false; error: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The grid posts one field per cell, named `cell:<employeeId>:<shiftDate>`.
 * Anything outside the submitted week, or naming an unknown employee, is
 * dropped rather than trusted — the form is just a client.
 */
export function parsePublishForm(
  form: FormData,
  allowedEmployeeIds: Set<string>,
): PublishParseResult {
  const weekStart = String(form.get('week_start') ?? '');
  if (!isValidIsoDate(weekStart)) return { ok: false, error: 'Invalid week.' };

  const validDates = new Set(weekDates(weekStart));
  const assignments: RosterAssignment[] = [];

  for (const [key, raw] of form.entries()) {
    if (!key.startsWith('cell:') || typeof raw !== 'string') continue;

    const [, employeeId, shiftDate] = key.split(':');
    if (!employeeId || !shiftDate) continue;
    if (!UUID.test(employeeId) || !allowedEmployeeIds.has(employeeId)) continue;
    if (!validDates.has(shiftDate)) continue;

    const value = raw.trim();
    if (value && !UUID.test(value)) continue;

    assignments.push({ employeeId, shiftDate, shiftId: value || null });
  }

  return { ok: true, weekStart, assignments };
}

/** Turns a Postgres error from publishing into something a HOD can act on. */
export function describeRosterError(error: { code?: string; message: string }): string {
  if (error.code === '23505') {
    return 'Someone already has two shifts on the same day. Reload the week and try again.';
  }
  if (error.code === '23503') {
    return 'That shift or employee no longer exists. Reload the week and try again.';
  }
  if (error.code === '42501') {
    return 'You can only schedule staff in your own department.';
  }
  return error.message;
}
