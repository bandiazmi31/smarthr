import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const BACK = '/hr/holidays';
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const holidayDate = String(form.get('holiday_date') ?? '').trim();
  const description = String(form.get('description') ?? '').trim().slice(0, 120);
  const rawMultiplier = String(form.get('multiplier') ?? '').trim();

  if (!ISO_DATE.test(holidayDate)) return redirectBack(BACK, { error: 'Choose a valid date.' });
  if (!description) return redirectBack(BACK, { error: 'A description is required.' });

  let multiplier: number | null = null;
  if (rawMultiplier) {
    const parsed = Number.parseFloat(rawMultiplier);
    if (!Number.isFinite(parsed) || parsed < 1 || parsed > 10) {
      return redirectBack(BACK, { error: 'The multiplier must be between 1 and 10.' });
    }
    multiplier = parsed;
  }

  const { error } = await locals.supabase
    .from('master_holidays')
    .insert({ holiday_date: holidayDate, description, multiplier });

  if (error) {
    return redirectBack(BACK, {
      error: error.code === '23505' ? 'That date is already recorded as a holiday.' : error.message,
    });
  }

  return redirectBack(BACK, { ok: 'holiday_saved' });
};
