import type { APIRoute } from 'astro';
import { describeDbError, parseEmployeeForm } from '../../../lib/employees';
import { setFormFlash } from '../../../lib/flash';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

export const POST: APIRoute = async ({ request, locals, cookies }) => {
  const form = await request.formData();
  const parsed = parseEmployeeForm(form);

  if (!parsed.ok) {
    setFormFlash(cookies, { errors: parsed.errors, values: parsed.raw });
    return redirectBack('/hr/employees/create');
  }

  const { data, error } = await locals.supabase
    .from('employees')
    .insert({ ...parsed.values, created_by: locals.actor.userId })
    .select('id')
    .single();

  if (error) {
    setFormFlash(cookies, {
      errors: describeDbError(error),
      values: Object.fromEntries(
        Object.entries(parsed.values).map(([key, value]) => [key, value ?? '']),
      ),
    });
    return redirectBack('/hr/employees/create');
  }

  // Land on the record so the admin can attach the ID card and contract straight away.
  return redirectBack(`/hr/employees/edit/${data.id}`, { ok: 'created' });
};
