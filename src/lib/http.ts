/** 303 keeps the browser from re-POSTing when the admin refreshes. */
export function redirectBack(
  path: string,
  params: Record<string, string | undefined> = {},
): Response {
  const url = new URL(path, 'http://placeholder');
  for (const [key, value] of Object.entries(params)) {
    if (value) url.searchParams.set(key, value);
  }
  const location = `${url.pathname}${url.search}`;
  return new Response(null, { status: 303, headers: { Location: location } });
}

export function jsonError(message: string, status = 400): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/**
 * The attendance endpoints serve two callers: the PWA, which posts a form and
 * expects a 303 back to a page, and API clients, which expect a status code.
 * PRD v2.0 §3.1 specifies 403 for a geofence rejection, so honour that when the
 * caller actually asked for JSON.
 */
export function wantsJson(request: Request): boolean {
  const accept = request.headers.get('Accept') ?? '';
  if (request.headers.get('X-Requested-With') === 'XMLHttpRequest') return true;
  // A browser navigation leads with text/html; only treat an explicit
  // JSON preference as an API call.
  return accept.includes('application/json') && !accept.includes('text/html');
}

/** Maps the SQLSTATE our attendance functions raise onto an HTTP status. */
export function statusForDbError(code: string | undefined): number {
  switch (code) {
    case 'P0001': // outside the geofence
    case '42501': // someone else's shift
    case '28000': // no linked employee record
      return 403;
    case 'P0003': // before the early clock-in window opens
    case '23505': // already clocked in / out
      return 409;
    case 'P0002': // no such shift or no clock-in yet
      return 404;
    default:
      return 400;
  }
}
