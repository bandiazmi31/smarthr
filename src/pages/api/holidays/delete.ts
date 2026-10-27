import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  if (!UUID.test(id)) return jsonError('A valid holiday is required.');

  const { error } = await locals.supabase.from('master_holidays').delete().eq('id', id);
  if (error) return redirectBack('/hr/holidays', { error: error.message });

  return redirectBack('/hr/holidays', { ok: 'holiday_removed' });
};
