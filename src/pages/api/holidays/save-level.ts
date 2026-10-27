import type { APIRoute } from 'astro';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

const BACK = '/hr/holidays';

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const name = String(form.get('name') ?? '').trim().slice(0, 60);
  const basePoints = Number.parseFloat(String(form.get('base_points') ?? ''));

  if (!name) return redirectBack(BACK, { error: 'A level name is required.' });
  if (!Number.isFinite(basePoints) || basePoints < 0) {
    return redirectBack(BACK, { error: 'Base points must be zero or more.' });
  }

  const { error } = await locals.supabase
    .from('job_levels')
    .insert({ name, base_points: basePoints, sort_order: 99 });

  if (error) {
    return redirectBack(BACK, {
      error: error.code === '23505' ? 'That level already exists.' : error.message,
    });
  }

  return redirectBack(BACK, { ok: 'level_saved' });
};
