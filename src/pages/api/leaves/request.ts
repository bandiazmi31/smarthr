import type { APIRoute } from 'astro';
import {
  ALLOWED_LEAVE_DOC_TYPES,
  MAX_LEAVE_DOC_BYTES,
  describeLeaveError,
} from '../../../lib/leave';
import { jsonError, redirectBack, statusForDbError, wantsJson } from '../../../lib/http';

export const prerender = false;

const BUCKET = 'leave-documents';
const BACK = '/mobile/leave';
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export const POST: APIRoute = async ({ request, locals }) => {
  const { supabase, actor } = locals;
  const employee = actor.employee;
  if (!employee) return jsonError('No employee record is linked to this account.', 403);

  const form = await request.formData();
  const leaveType = String(form.get('leave_type') ?? '').trim();
  const startDate = String(form.get('start_date') ?? '').trim();
  const endDate = String(form.get('end_date') ?? '').trim();
  const reason = String(form.get('reason') ?? '').trim().slice(0, 200);

  if (!ISO_DATE.test(startDate) || !ISO_DATE.test(endDate)) {
    return redirectBack(BACK, { error: 'Choose a valid start and end date.' });
  }

  // Upload the certificate first so its path can go on the request; a stray
  // upload is reclaimable via the orphan policy, a dangling path is not.
  let documentPath: string | null = null;
  const file = form.get('document');

  if (file instanceof File && file.size > 0) {
    if (file.size > MAX_LEAVE_DOC_BYTES) {
      return redirectBack(BACK, { error: 'That certificate is larger than 10 MB.' });
    }
    if (!ALLOWED_LEAVE_DOC_TYPES.includes(file.type as never)) {
      return redirectBack(BACK, { error: 'Certificates must be PDF, JPG or PNG.' });
    }

    const safeName = file.name
      .normalize('NFKD')
      .replace(/[^\w.\- ]+/g, '')
      .replace(/\s+/g, '-')
      .slice(-120) || 'certificate';

    documentPath = `${employee.id}/${crypto.randomUUID()}-${safeName}`;

    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(documentPath, file, { contentType: file.type, upsert: false });

    if (uploadError) {
      return redirectBack(BACK, { error: `Could not attach the certificate: ${uploadError.message}` });
    }
  }

  const { error } = await supabase.rpc('request_leave', {
    p_leave_type: leaveType,
    p_start_date: startDate,
    p_end_date: endDate,
    p_reason: reason || null,
    p_document_path: documentPath,
  } as never);

  if (error) {
    if (documentPath) await supabase.storage.from(BUCKET).remove([documentPath]);
    const message = describeLeaveError(error);
    if (wantsJson(request)) return jsonError(message, statusForDbError(error.code));
    return redirectBack(BACK, { error: message });
  }

  if (wantsJson(request)) {
    return new Response(JSON.stringify({ ok: true }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return redirectBack(BACK, { ok: 'leave_requested' });
};
