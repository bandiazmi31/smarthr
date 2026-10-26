import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * HOD (or HR) decision. Approving swaps employee_id across the two rosters
 * inside decide_shift_swap, so the roster updates automatically.
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');
  const decision = String(form.get('decision') ?? '');
  const note = String(form.get('note') ?? '').trim().slice(0, 300);
  const back = String(form.get('back') ?? '/mobile/swaps');

  if (!UUID.test(id)) return jsonError('A valid request is required.');
  if (decision !== 'approve' && decision !== 'reject') return jsonError('Unknown decision.');

  // Only ever bounce back inside this app.
  const target = back.startsWith('/') && !back.startsWith('//') ? back : '/mobile/swaps';

  const { error } = await locals.supabase.rpc('decide_shift_swap', {
    p_swap_id: id,
    p_approve: decision === 'approve',
    p_note: note || null,
  } as never);

  if (error) return redirectBack(target, { error: error.message });

  return redirectBack(target, {
    ok: decision === 'approve' ? 'swap_approved' : 'swap_rejected',
  });
};
