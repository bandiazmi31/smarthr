import type { APIRoute } from 'astro';
import { canManageDepartment } from '../../../lib/actor';
import { weekDates } from '../../../lib/datetime';
import { describeRosterError, parsePublishForm } from '../../../lib/roster';
import { jsonError, redirectBack } from '../../../lib/http';
import type { PortalIdentityRow, RosterRow } from '../../../types/database';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Replaces one department's scheduled shifts for one week. Shifts that have
 * already started are never touched, so republishing a week cannot erase
 * attendance that has already happened.
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const { supabase, actor } = locals;
  const form = await request.formData();
  const departmentId = String(form.get('department_id') ?? '');

  if (!UUID.test(departmentId)) return jsonError('A valid department is required.');
  if (!canManageDepartment(actor, departmentId)) {
    return jsonError('You can only schedule your own department.', 403);
  }

  const { data: staffRows, error: staffError } = await supabase
    .from('portal_identity')
    .select('id')
    .eq('department_id', departmentId);

  if (staffError) return jsonError(staffError.message, 500);

  const allowed = new Set((staffRows as Pick<PortalIdentityRow, 'id'>[]).map((row) => row.id));
  const parsed = parsePublishForm(form, allowed);
  if (!parsed.ok) return jsonError(parsed.error);

  const { weekStart, assignments } = parsed;
  const dates = weekDates(weekStart);
  const back = `/hod/roster?week=${weekStart}&department=${departmentId}`;

  // Existing rows for the week, so we can tell inserts from updates from deletes.
  const { data: existingRows, error: existingError } = await supabase
    .from('rosters')
    .select('id, employee_id, shift_id, shift_date, status')
    .in('employee_id', [...allowed])
    .gte('shift_date', dates[0]!)
    .lte('shift_date', dates[6]!);

  if (existingError) return redirectBack(back, { error: describeRosterError(existingError) });

  const existing = new Map<string, Pick<RosterRow, 'id' | 'shift_id' | 'status'>>();
  for (const row of existingRows ?? []) {
    existing.set(`${row.employee_id}:${row.shift_date}`, row);
  }

  const toInsert: Array<{ employee_id: string; shift_id: string; shift_date: string; published_by: string | null }> = [];
  const toUpdate: Array<{ id: string; shift_id: string }> = [];
  const toDelete: string[] = [];

  for (const cell of assignments) {
    const key = `${cell.employeeId}:${cell.shiftDate}`;
    const current = existing.get(key);

    // Anything past 'scheduled' is history: leave it exactly as it is.
    if (current && current.status !== 'scheduled') continue;

    if (!cell.shiftId) {
      if (current) toDelete.push(current.id);
      continue;
    }

    if (!current) {
      toInsert.push({
        employee_id: cell.employeeId,
        shift_id: cell.shiftId,
        shift_date: cell.shiftDate,
        published_by: actor.userId,
      });
    } else if (current.shift_id !== cell.shiftId) {
      toUpdate.push({ id: current.id, shift_id: cell.shiftId });
    }
  }

  if (toDelete.length > 0) {
    const { error } = await supabase.from('rosters').delete().in('id', toDelete);
    if (error) return redirectBack(back, { error: describeRosterError(error) });
  }

  for (const change of toUpdate) {
    const { error } = await supabase
      .from('rosters')
      .update({ shift_id: change.shift_id })
      .eq('id', change.id);
    if (error) return redirectBack(back, { error: describeRosterError(error) });
  }

  if (toInsert.length > 0) {
    // expected_clock_in/out are filled by the rosters_apply_window trigger, which
    // is also what rolls an overnight shift's end onto the next calendar day.
    const { error } = await supabase.from('rosters').insert(toInsert as never);
    if (error) return redirectBack(back, { error: describeRosterError(error) });
  }

  const changed = toInsert.length + toUpdate.length + toDelete.length;
  return redirectBack(back, {
    ok: changed === 0 ? 'roster_unchanged' : 'roster_published',
    n: String(changed),
  });
};
