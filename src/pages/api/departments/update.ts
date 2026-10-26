import type { APIRoute } from 'astro';
import { describeDepartmentError, parseDepartmentForm } from '../../../lib/departments';
import { setFormFlash } from '../../../lib/flash';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals, cookies }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');

  if (!UUID.test(id)) return jsonError('A valid department id is required.');

  const parsed = parseDepartmentForm(form);

  if (!parsed.ok) {
    setFormFlash(cookies, { errors: parsed.errors, values: parsed.raw });
    return redirectBack('/hr/departments', { edit: id });
  }

  const { data, error } = await locals.supabase
    .from('departments')
    .update(parsed.values)
    .eq('id', id)
    .select('id')
    .maybeSingle();

  if (error) {
    setFormFlash(cookies, {
      errors: { name: describeDepartmentError(error, parsed.values.name) },
      values: { name: parsed.values.name, description: parsed.values.description ?? '' },
    });
    return redirectBack('/hr/departments', { edit: id });
  }

  if (!data) return redirectBack('/hr/departments', { error: 'department_not_found' });

  return redirectBack('/hr/departments', { ok: 'department_updated' });
};
