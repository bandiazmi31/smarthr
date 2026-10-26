import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BACK = '/mobile/swaps';

/** The colleague accepts or declines; the requester withdraws. */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  const decision = String(form.get('decision') ?? '');

  if (!UUID.test(id)) return jsonError('A valid request is required.');

  if (decision === 'cancel') {
    const { error } = await locals.supabase.rpc('cancel_shift_swap', { p_swap_id: id } as never);
    if (error) return redirectBack(BACK, { error: error.message });
    return redirectBack(BACK, { ok: 'swap_cancelled' });
  }

  if (decision !== 'accept' && decision !== 'decline') {
    return jsonError('Unknown decision.');
  }

  const { error } = await locals.supabase.rpc('respond_shift_swap', {
    p_swap_id: id,
    p_accept: decision === 'accept',
  } as never);

  if (error) return redirectBack(BACK, { error: error.message });

  return redirectBack(BACK, {
    ok: decision === 'accept' ? 'swap_accepted' : 'swap_declined',
  });
};
