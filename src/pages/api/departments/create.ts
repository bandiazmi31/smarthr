import type { APIRoute } from 'astro';
import { describeDepartmentError, parseDepartmentForm } from '../../../lib/departments';
import { setFormFlash } from '../../../lib/flash';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

export const POST: APIRoute = async ({ request, locals, cookies }) => {
  const form = await request.formData();
  const parsed = parseDepartmentForm(form);

  if (!parsed.ok) {
    setFormFlash(cookies, { errors: parsed.errors, values: parsed.raw });
    return redirectBack('/hr/departments');
  }

  const { error } = await locals.supabase.from('departments').insert(parsed.values);

  if (error) {
    // The unique index is case-insensitive, so this is the duplicate_name path.
    setFormFlash(cookies, {
      errors: { name: describeDepartmentError(error, parsed.values.name) },
      values: { name: parsed.values.name, description: parsed.values.description ?? '' },
    });
    return redirectBack('/hr/departments');
  }

  return redirectBack('/hr/departments', { ok: 'department_created' });
};
