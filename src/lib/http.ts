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
