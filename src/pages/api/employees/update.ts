import type { APIRoute } from 'astro';
import { describeDbError, parseEmployeeForm } from '../../../lib/employees';
import { setFormFlash } from '../../../lib/flash';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals, cookies }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');

  if (!UUID.test(id)) return jsonError('A valid employee id is required.');

  const parsed = parseEmployeeForm(form);

  if (!parsed.ok) {
    setFormFlash(cookies, { errors: parsed.errors, values: parsed.raw });
    return redirectBack(`/hr/employees/edit/${id}`);
  }

  const { error, data } = await locals.supabase
    .from('employees')
    .update(parsed.values)
    .eq('id', id)
    .select('id')
    .maybeSingle();

  if (error) {
    setFormFlash(cookies, {
      errors: describeDbError(error),
      values: Object.fromEntries(
        Object.entries(parsed.values).map(([key, value]) => [key, value ?? '']),
      ),
    });
    return redirectBack(`/hr/employees/edit/${id}`);
  }

  if (!data) return redirectBack('/hr/employees', { error: 'not_found' });

  return redirectBack(`/hr/employees/edit/${id}`, { ok: 'updated' });
};
