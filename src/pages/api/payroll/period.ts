import type { APIRoute } from 'astro';
import { monthLabel } from '../../../lib/payroll';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BACK = '/hr/payroll';

/** Creates a cut-off period from the configured cut-off day, or locks/reopens one. */
export const POST: APIRoute = async ({ request, locals }) => {
  const { supabase } = locals;
  const form = await request.formData();
  const action = String(form.get('action') ?? '');

  if (action === 'lock' || action === 'unlock') {
    const id = String(form.get('id') ?? '');
    if (!UUID.test(id)) return jsonError('A valid period is required.');

    const { error } = await supabase.rpc('set_payroll_period_lock', {
      p_period_id: id,
      p_locked: action === 'lock',
    } as never);

    if (error) return redirectBack(BACK, { error: error.message });
    return redirectBack(BACK, { ok: action === 'lock' ? 'period_locked' : 'period_reopened' });
  }

  if (action !== 'create') return jsonError('Unknown action.');

  const month = Number.parseInt(String(form.get('month') ?? ''), 10);
  const year = Number.parseInt(String(form.get('year') ?? ''), 10);

  if (!Number.isInteger(month) || month < 1 || month > 12) {
    return redirectBack(BACK, { error: 'Choose a valid month.' });
  }
  if (!Number.isInteger(year) || year < 2000 || year > 2100) {
    return redirectBack(BACK, { error: 'Choose a valid year.' });
  }

  const { data: rangeRows, error: rangeError } = await supabase.rpc('payroll_period_range', {
    p_month: month,
    p_year: year,
  } as never);

  if (rangeError) return redirectBack(BACK, { error: rangeError.message });

  const range = ((rangeRows ?? []) as Array<{ start_date: string; end_date: string }>)[0];
  if (!range) return redirectBack(BACK, { error: 'Could not work out that period.' });

  const { error } = await supabase.from('payroll_periods').insert({
    label: monthLabel(month, year),
    start_date: range.start_date,
    end_date: range.end_date,
  });

  if (error) {
    return redirectBack(BACK, {
      error: error.code === '23505' ? 'That period already exists.' : error.message,
    });
  }

  return redirectBack(BACK, { ok: 'period_created' });
};
