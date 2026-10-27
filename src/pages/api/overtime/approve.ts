import type { APIRoute } from 'astro';
import { describeOvertimeError } from '../../../lib/leave';
import { jsonError, redirectBack, statusForDbError, wantsJson } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * HOD signs off actual overtime against what was requested. The database caps
 * the approved hours by both the request and the clock, so a generous number
 * here cannot invent time that was never worked.
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  const decision = String(form.get('decision') ?? '');
  const rawHours = String(form.get('approved_hours') ?? '').trim();
  const note = String(form.get('note') ?? '').trim().slice(0, 300);
  const back = String(form.get('back') ?? '/hod/overtime');
  const target = back.startsWith('/') && !back.startsWith('//') ? back : '/hod/overtime';

  if (!UUID.test(id)) return jsonError('A valid overtime record is required.');
  if (decision !== 'approve' && decision !== 'reject') return jsonError('Unknown decision.');

  let approvedHours: number | null = null;
  if (decision === 'approve' && rawHours) {
    const parsed = Number.parseFloat(rawHours);
    if (!Number.isFinite(parsed) || parsed < 0 || parsed > 24) {
      return redirectBack(target, { error: 'Approved hours must be between 0 and 24.' });
    }
    approvedHours = parsed;
  }

  const { error } = await locals.supabase.rpc('decide_overtime', {
    p_record_id: id,
    p_approve: decision === 'approve',
    p_approved_hours: approvedHours,
    p_note: note || null,
  } as never);

  if (error) {
    const message = describeOvertimeError(error);
    if (wantsJson(request)) return jsonError(message, statusForDbError(error.code));
    return redirectBack(target, { error: message });
  }

  return redirectBack(target, {
    ok: decision === 'approve' ? 'overtime_approved' : 'overtime_rejected',
  });
};
