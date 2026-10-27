import type { APIRoute } from 'astro';
import { describeLeaveError } from '../../../lib/leave';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  const back = String(form.get('back') ?? '/mobile/leave');
  const target = back.startsWith('/') && !back.startsWith('//') ? back : '/mobile/leave';

  if (!UUID.test(id)) return jsonError('A valid request is required.');

  const { error } = await locals.supabase.rpc('cancel_leave_request', {
    p_request_id: id,
  } as never);

  if (error) return redirectBack(target, { error: describeLeaveError(error) });

  return redirectBack(target, { ok: 'leave_cancelled' });
};
