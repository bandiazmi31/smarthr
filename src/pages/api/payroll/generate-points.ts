import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const BACK = '/hr/payroll';

/** Recomputes the month's service-charge snapshot (PRD v3 §4.3). */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const month = Number.parseInt(String(form.get('month') ?? ''), 10);
  const year = Number.parseInt(String(form.get('year') ?? ''), 10);

  if (!Number.isInteger(month) || month < 1 || month > 12) {
    return jsonError('Choose a valid month.');
  }
  if (!Number.isInteger(year) || year < 2000 || year > 2100) {
    return jsonError('Choose a valid year.');
  }

  const { data, error } = await locals.supabase.rpc('generate_service_charge_points', {
    p_month: month,
    p_year: year,
  } as never);

  if (error) return redirectBack(BACK, { error: error.message });

  return redirectBack(BACK, { ok: 'points_generated', n: String(data ?? 0) });
};
