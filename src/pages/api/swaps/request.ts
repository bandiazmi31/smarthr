import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BACK = '/mobile/swaps';

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const requester = String(form.get('requester_roster_id') ?? '');
  const target = String(form.get('target_roster_id') ?? '');
  const reason = String(form.get('reason') ?? '').trim().slice(0, 200);

  if (!UUID.test(requester) || !UUID.test(target)) {
    return jsonError('Two valid shifts are required.');
  }

  // request_shift_swap enforces ownership, same-department, and future-dated.
  const { error } = await locals.supabase.rpc('request_shift_swap', {
    p_requester_roster_id: requester,
    p_target_roster_id: target,
    p_reason: reason || null,
  } as never);

  if (error) {
    const duplicate = error.code === '23505';
    return redirectBack(BACK, {
      error: duplicate
        ? 'One of those shifts already has an open swap request.'
        : error.message,
    });
  }

  return redirectBack(BACK, { ok: 'swap_requested' });
};
