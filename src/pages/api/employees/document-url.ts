import type { APIRoute } from 'astro';
import { jsonError } from '../../../lib/http';
import { DOCUMENT_BUCKET, SIGNED_URL_TTL_SECONDS } from '../../../lib/supabase';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Mints a short-lived signed URL on click and redirects to it, so no credentialed
 * link is ever written into the page HTML or left to go stale in the browser.
 */
export const GET: APIRoute = async ({ url, locals }) => {
  const id = url.searchParams.get('id') ?? '';
  if (!UUID.test(id)) return jsonError('A valid document id is required.');

  const { data: doc } = await locals.supabase
    .from('employee_documents')
    .select('file_path, file_name')
    .eq('id', id)
    .maybeSingle();

  if (!doc) return jsonError('Document not found.', 404);

  const { data, error } = await locals.supabase.storage
    .from(DOCUMENT_BUCKET)
    .createSignedUrl(doc.file_path, SIGNED_URL_TTL_SECONDS);

  if (error || !data) return jsonError('Could not open that document.', 502);

  return new Response(null, {
    status: 302,
    headers: { Location: data.signedUrl, 'Cache-Control': 'private, no-store' },
  });
};
