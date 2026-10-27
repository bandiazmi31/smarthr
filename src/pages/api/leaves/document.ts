import type { APIRoute } from 'astro';
import { jsonError } from '../../../lib/http';
import { SIGNED_URL_TTL_SECONDS } from '../../../lib/supabase';

export const prerender = false;

const BUCKET = 'leave-documents';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Medical certificates live in a private bucket, so the link is minted per
 * click. RLS on leave_requests decides whether this caller may see the row at
 * all, which is what gates the document.
 */
export const GET: APIRoute = async ({ url, locals }) => {
  const id = url.searchParams.get('id') ?? '';
  if (!UUID.test(id)) return jsonError('A valid request id is required.');

  const { data: req } = await locals.supabase
    .from('leave_requests')
    .select('document_path')
    .eq('id', id)
    .maybeSingle();

  if (!req?.document_path) return jsonError('No certificate is attached to that request.', 404);

  const { data, error } = await locals.supabase.storage
    .from(BUCKET)
    .createSignedUrl(req.document_path, SIGNED_URL_TTL_SECONDS);

  if (error || !data) return jsonError('Could not open that certificate.', 502);

  return new Response(null, {
    status: 302,
    headers: { Location: data.signedUrl, 'Cache-Control': 'private, no-store' },
  });
};
