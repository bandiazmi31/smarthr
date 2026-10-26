import { defineMiddleware } from 'astro:middleware';
import { ANONYMOUS, buildActor, type Actor } from './lib/actor';
import { createSupabaseServerClient } from './lib/supabase';

/** Routes reachable without a session. */
const PUBLIC_PATHS = new Set([
  '/login',
  '/mobile/register',
  '/api/auth/login',
  '/api/auth/logout',
  '/api/auth/register',
]);

const UNSAFE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function isPublic(pathname: string): boolean {
  return PUBLIC_PATHS.has(pathname);
}

/**
 * Session cookies are SameSite=Lax, so a cross-site form POST never carries
 * them. This rejects such a request outright rather than letting it run
 * unauthenticated.
 */
function isCrossSiteWrite(request: Request, origin: string): boolean {
  if (!UNSAFE_METHODS.has(request.method)) return false;
  const stated = request.headers.get('Origin');
  return stated !== null && stated !== origin;
}

/** Which actors each area admits. */
function isAllowed(pathname: string, actor: Actor): boolean {
  if (pathname.startsWith('/hr/') || pathname.startsWith('/api/employees/')) return actor.isHr;
  if (pathname.startsWith('/api/departments/') || pathname.startsWith('/api/settings/')) {
    return actor.isHr;
  }
  if (pathname.startsWith('/hod/') || pathname.startsWith('/api/rosters/')) {
    return actor.isHr || actor.isHod;
  }
  if (pathname.startsWith('/mobile/') || pathname.startsWith('/api/attendance/')) {
    return actor.employee !== null;
  }
  // Swaps are used by staff (request/respond) and by HODs (approve) alike.
  if (pathname.startsWith('/api/swaps/')) return actor.employee !== null || actor.isHr;
  return true;
}

export const onRequest = defineMiddleware(async (context, next) => {
  if (isCrossSiteWrite(context.request, context.url.origin)) {
    return new Response('Cross-site request blocked', { status: 403 });
  }

  const supabase = createSupabaseServerClient(context);
  context.locals.supabase = supabase;
  context.locals.actor = ANONYMOUS;

  const pathname = context.url.pathname;

  // getUser() revalidates the cookie JWT against Supabase Auth rather than
  // trusting whatever the browser sent us.
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    const [hrResult, employeeResult] = await Promise.all([
      supabase.from('hr_profiles').select('*').eq('id', user.id).maybeSingle(),
      supabase.from('portal_identity').select('*').eq('user_id', user.id).maybeSingle(),
    ]);

    const actor = buildActor({
      userId: user.id,
      email: user.email ?? null,
      hrProfile: hrResult.data ?? null,
      employee: employeeResult.data ?? null,
    });

    if (actor.kind === 'anonymous' && !isPublic(pathname)) {
      // Authenticated, but linked to nothing: no HR roster entry and no
      // employee record. Signing up alone grants nothing.
      await supabase.auth.signOut();
      return context.redirect('/login?error=not_authorized', 303);
    }

    context.locals.actor = actor;
  }

  const actor = context.locals.actor;
  const signedIn = actor.kind !== 'anonymous';

  if (signedIn && (pathname === '/login' || pathname === '/mobile/register')) {
    return context.redirect(actor.home, 303);
  }

  if (!signedIn && !isPublic(pathname)) {
    if (pathname.startsWith('/api/')) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    const target = `${pathname}${context.url.search}`;
    return context.redirect(`/login?redirect=${encodeURIComponent(target)}`, 303);
  }

  if (signedIn && !isAllowed(pathname, actor)) {
    if (pathname.startsWith('/api/')) {
      return new Response(JSON.stringify({ error: 'Not permitted' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    return context.redirect(`${actor.home}?error=not_permitted`, 303);
  }

  const response = await next();
  // Never let a proxy or CDN cache a page rendered for a specific session.
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
});
