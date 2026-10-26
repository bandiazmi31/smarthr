import type { APIRoute } from 'astro';
import { jsonError, redirectBack } from '../../../lib/http';
import { DOCUMENT_BUCKET } from '../../../lib/supabase';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const id = String(form.get('id') ?? '');

  if (!UUID.test(id)) return jsonError('A valid document id is required.');

  const { data: doc } = await locals.supabase
    .from('employee_documents')
    .select('id, employee_id, file_path')
    .eq('id', id)
    .maybeSingle();

  if (!doc) return redirectBack('/hr/employees', { error: 'not_found' });

  const back = `/hr/employees/edit/${doc.employee_id}`;

  const { error } = await locals.supabase.from('employee_documents').delete().eq('id', id);
  if (error) return redirectBack(back, { error: error.message });

  // Metadata is the source of truth; a leftover object is harmless but untidy.
  await locals.supabase.storage.from(DOCUMENT_BUCKET).remove([doc.file_path]);

  return redirectBack(back, { ok: 'doc_deleted' });
};
