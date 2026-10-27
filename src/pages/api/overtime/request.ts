import type { APIRoute } from 'astro';
import { describeOvertimeError } from '../../../lib/leave';
import { jsonError, redirectBack, statusForDbError, wantsJson } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const rosterId = String(form.get('roster_id') ?? '');
  const hours = Number.parseFloat(String(form.get('hours') ?? ''));
  const reason = String(form.get('reason') ?? '').trim().slice(0, 200);
  const back = String(form.get('back') ?? '/mobile');
  const target = back.startsWith('/') && !back.startsWith('//') ? back : '/mobile';

  if (!UUID.test(rosterId)) return jsonError('A valid shift is required.');
  if (!Number.isFinite(hours) || hours <= 0 || hours > 24) {
    return redirectBack(target, { error: 'Overtime hours must be between 0 and 24.' });
  }

  const { error } = await locals.supabase.rpc('request_overtime', {
    p_roster_id: rosterId,
    p_hours: hours,
    p_reason: reason || null,
  } as never);

  if (error) {
    const message = describeOvertimeError(error);
    if (wantsJson(request)) return jsonError(message, statusForDbError(error.code));
    return redirectBack(target, { error: message });
  }

  return redirectBack(target, { ok: 'overtime_requested' });
};
