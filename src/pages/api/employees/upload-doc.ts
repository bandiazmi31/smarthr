import type { APIRoute } from 'astro';
import {
  ALLOWED_DOCUMENT_MIME_TYPES,
  DOCUMENT_TYPES,
  MAX_DOCUMENT_BYTES,
} from '../../../lib/constants';
import { jsonError, redirectBack } from '../../../lib/http';
import { DOCUMENT_BUCKET } from '../../../lib/supabase';
import type { DocumentType } from '../../../types/database';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Keeps the storage key printable and free of path traversal. */
function sanitizeFileName(name: string): string {
  const cleaned = name
    .normalize('NFKD')
    .replace(/[^\w.\- ]+/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^[.\-]+/, '')
    .slice(-120);
  return cleaned || 'document';
}

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const employeeId = String(form.get('employee_id') ?? '');
  const documentType = String(form.get('document_type') ?? '') as DocumentType;
  const file = form.get('file');

  if (!UUID.test(employeeId)) return jsonError('A valid employee id is required.');
  const back = `/hr/employees/edit/${employeeId}`;

  if (!DOCUMENT_TYPES.includes(documentType)) {
    return redirectBack(back, { error: 'Choose a valid document type.' });
  }

  if (!(file instanceof File) || file.size === 0) {
    return redirectBack(back, { error: 'Select a file to upload.' });
  }

  if (file.size > MAX_DOCUMENT_BYTES) {
    return redirectBack(back, {
      error: `That file is ${(file.size / 1024 / 1024).toFixed(1)} MB; the limit is ${
        MAX_DOCUMENT_BYTES / 1024 / 1024
      } MB.`,
    });
  }

  if (!ALLOWED_DOCUMENT_MIME_TYPES.includes(file.type as never)) {
    return redirectBack(back, { error: 'Only PDF, JPG and PNG files are accepted.' });
  }

  // The employee must exist and be visible under this admin's RLS context before
  // anything lands in storage.
  const { data: employee } = await locals.supabase
    .from('employees')
    .select('id')
    .eq('id', employeeId)
    .maybeSingle();

  if (!employee) return redirectBack('/hr/employees', { error: 'not_found' });

  const fileName = sanitizeFileName(file.name);
  const path = `${employeeId}/${crypto.randomUUID()}-${fileName}`;

  const { error: uploadError } = await locals.supabase.storage
    .from(DOCUMENT_BUCKET)
    .upload(path, file, { contentType: file.type, upsert: false });

  if (uploadError) {
    return redirectBack(back, { error: `Upload failed: ${uploadError.message}` });
  }

  const { error: insertError } = await locals.supabase.from('employee_documents').insert({
    employee_id: employeeId,
    document_type: documentType,
    file_path: path,
    file_name: fileName,
    mime_type: file.type,
    file_size: file.size,
    uploaded_by: locals.actor.userId,
  });

  if (insertError) {
    // Don't leave an orphan object behind if the metadata row failed.
    await locals.supabase.storage.from(DOCUMENT_BUCKET).remove([path]);
    return redirectBack(back, { error: `Upload failed: ${insertError.message}` });
  }

  return redirectBack(back, { ok: 'uploaded' });
};
