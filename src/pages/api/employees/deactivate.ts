import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Soft delete. The row and its documents are never removed: is_active flips to
 * false, which drops the employee from the active directory and contract alerts
 * while preserving the audit trail. Passing action=reactivate reverses it.
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  const reactivate = String(form.get('action') ?? '') === 'reactivate';
  const reason = String(form.get('deactivation_reason') ?? '').trim().slice(0, 300);

  if (!UUID.test(id)) return jsonError('A valid employee id is required.');

  const { data, error } = await locals.supabase
    .from('employees')
    .update(
      reactivate
        ? { is_active: true }
        : { is_active: false, deactivation_reason: reason || null },
    )
    .eq('id', id)
    .select('id')
    .maybeSingle();

  if (error) return redirectBack(`/hr/employees/edit/${id}`, { error: error.message });
  if (!data) return redirectBack('/hr/employees', { error: 'not_found' });

  return redirectBack(`/hr/employees/edit/${id}`, {
    ok: reactivate ? 'reactivated' : 'deactivated',
  });
};
