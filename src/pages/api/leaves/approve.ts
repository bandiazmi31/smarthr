import type { APIRoute } from 'astro';
import { describeLeaveError } from '../../../lib/leave';
import { jsonError, redirectBack, statusForDbError, wantsJson } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** HOD or HR decision. Approval is where the balance is decremented. */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  const decision = String(form.get('decision') ?? '');
  const note = String(form.get('note') ?? '').trim().slice(0, 300);
  const back = String(form.get('back') ?? '/hod/leave');
  const target = back.startsWith('/') && !back.startsWith('//') ? back : '/hod/leave';

  if (!UUID.test(id)) return jsonError('A valid request is required.');
  if (decision !== 'approve' && decision !== 'reject') return jsonError('Unknown decision.');

  const { error } = await locals.supabase.rpc('decide_leave_request', {
    p_request_id: id,
    p_approve: decision === 'approve',
    p_note: note || null,
  } as never);

  if (error) {
    const message = describeLeaveError(error);
    if (wantsJson(request)) return jsonError(message, statusForDbError(error.code));
    return redirectBack(target, { error: message });
  }

  return redirectBack(target, {
    ok: decision === 'approve' ? 'leave_approved' : 'leave_rejected',
  });
};
