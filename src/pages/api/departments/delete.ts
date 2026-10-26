import type { APIRoute } from 'astro';
import { describeDepartmentError } from '../../../lib/departments';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');

  if (!UUID.test(id)) return jsonError('A valid department id is required.');

  const { data: summary } = await locals.supabase
    .from('department_summary')
    .select('name, employee_count')
    .eq('id', id)
    .maybeSingle();

  if (!summary) return redirectBack('/hr/departments', { error: 'department_not_found' });

  // Checked here for a useful message; the FK (ON DELETE RESTRICT) is what
  // actually guarantees it, including against a concurrent assignment.
  const assigned = Number(summary.employee_count);
  if (assigned > 0) {
    return redirectBack('/hr/departments', {
      error: `Cannot delete this department because ${assigned} employee${
        assigned === 1 ? ' is' : 's are'
      } currently assigned to it. Please reassign them first.`,
    });
  }

  const { error } = await locals.supabase.from('departments').delete().eq('id', id);

  if (error) {
    return redirectBack('/hr/departments', { error: describeDepartmentError(error) });
  }

  return redirectBack('/hr/departments', { ok: 'department_deleted' });
};
