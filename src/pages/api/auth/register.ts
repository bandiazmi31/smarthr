import type { APIRoute } from 'astro';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

const BACK = '/mobile/register';
const MIN_PASSWORD_LENGTH = 8;

/**
 * Employee self-activation. The account is only useful if a database trigger
 * finds a matching, HR-enabled employee record with the same email; without one
 * the user signs in to nothing, so this endpoint is safe to leave public.
 */
export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const email = String(form.get('email') ?? '').trim().toLowerCase();
  const password = String(form.get('password') ?? '');
  const confirm = String(form.get('confirm') ?? '');

  if (!email || !password) {
    return redirectBack(BACK, { error: 'Email and password are both required.', email });
  }

  if (password.length < MIN_PASSWORD_LENGTH) {
    return redirectBack(BACK, {
      error: `Choose a password of at least ${MIN_PASSWORD_LENGTH} characters.`,
      email,
    });
  }

  if (password !== confirm) {
    return redirectBack(BACK, { error: 'Those passwords do not match.', email });
  }

  const { data, error } = await locals.supabase.auth.signUp({ email, password });

  if (error) {
    return redirectBack(BACK, { error: error.message, email });
  }

  // Email confirmation on: no session yet, so send them to sign in afterwards.
  if (!data.session) {
    return redirectBack('/login', { ok: 'check_email', email });
  }

  const { data: linked } = await locals.supabase
    .from('portal_identity')
    .select('id')
    .eq('user_id', data.user?.id ?? '')
    .maybeSingle();

  if (!linked) {
    await locals.supabase.auth.signOut();
    return redirectBack(BACK, { error: 'no_matching_employee', email });
  }

  return redirectBack('/mobile', { ok: 'portal_activated' });
};
