import type { APIRoute } from 'astro';
import {
  ATTENDANCE_BUCKET,
  decodePhoto,
  parseCoordinates,
  photoPath,
} from '../../../lib/attendance';
import { jsonError, redirectBack, statusForDbError, wantsJson } from '../../../lib/http';

export const prerender = false;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BACK = '/mobile/clock-in';

export const POST: APIRoute = async ({ request, locals }) => {
  const { supabase, actor } = locals;
  const employee = actor.employee;
  if (!employee) return jsonError('No employee record is linked to this account.', 403);

  const form = await request.formData();
  const rosterId = String(form.get('roster_id') ?? '');
  if (!UUID.test(rosterId)) return jsonError('A valid shift is required.');

  const coords = parseCoordinates(form);
  if (!coords) {
    return redirectBack(BACK, { error: 'Your location could not be read. Try again.' });
  }

  const decoded = decodePhoto(form.get('photo'));
  if (!decoded.ok) return redirectBack(BACK, { error: decoded.error });

  const path = photoPath(employee.id, rosterId, 'in', decoded.photo.extension);

  // Upload first: a stored photo with no log is recoverable, a log pointing at
  // nothing is not.
  const { error: uploadError } = await supabase.storage
    .from(ATTENDANCE_BUCKET)
    .upload(path, decoded.photo.bytes, {
      contentType: decoded.photo.contentType,
      upsert: false,
    });

  if (uploadError) {
    return redirectBack(BACK, { error: `Could not save your photo: ${uploadError.message}` });
  }

  // The geofence check lives inside clock_in(), so it cannot be skipped by
  // calling the database directly.
  const { data, error } = await supabase.rpc('clock_in', {
    p_roster_id: rosterId,
    p_lat: coords.latitude,
    p_long: coords.longitude,
    p_photo_path: path,
  } as never);

  if (error) {
    await supabase.storage.from(ATTENDANCE_BUCKET).remove([path]);
    if (wantsJson(request)) {
      return jsonError(error.message, statusForDbError(error.code));
    }
    return redirectBack(BACK, { error: error.message });
  }

  const result = data as { is_late: boolean; late_by_minutes: number } | null;

  if (wantsJson(request)) {
    return new Response(JSON.stringify({ ok: true, ...result }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return redirectBack('/mobile', {
    ok: result?.is_late ? 'clocked_in_late' : 'clocked_in',
    n: result?.is_late ? String(result.late_by_minutes) : undefined,
  });
};
