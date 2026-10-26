import type { APIRoute } from 'astro';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

/** Only ever bounce back into this app, never to an attacker-supplied host. */
function safeRedirect(target: string | null): string | null {
  if (!target || !target.startsWith('/') || target.startsWith('//')) return null;
  return target;
}

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const email = String(form.get('email') ?? '').trim();
  const password = String(form.get('password') ?? '');
  const requestedRedirect = safeRedirect(String(form.get('redirect') ?? ''));

  if (!email || !password) {
    return redirectBack('/login', { error: 'invalid_credentials', email });
  }

  const { data, error } = await locals.supabase.auth.signInWithPassword({ email, password });

  if (error || !data.user) {
    return redirectBack('/login', { error: 'invalid_credentials', email });
  }

  // Authentication alone is not authorization: the account must be on the HR
  // roster or linked to an active employee record.
  const [hrResult, employeeResult] = await Promise.all([
    locals.supabase.from('hr_profiles').select('id').eq('id', data.user.id).maybeSingle(),
    locals.supabase
      .from('portal_identity')
      .select('id, role')
      .eq('user_id', data.user.id)
      .maybeSingle(),
  ]);

  if (!hrResult.data && !employeeResult.data) {
    await locals.supabase.auth.signOut();
    return redirectBack('/login', { error: 'not_authorized', email });
  }

  const home = hrResult.data
    ? '/hr/employees'
    : employeeResult.data?.role === 'hod'
      ? '/hod/roster'
      : '/mobile';

  return redirectBack(requestedRedirect ?? home);
};

export const GET: APIRoute = () => redirectBack('/login');
