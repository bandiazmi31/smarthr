import type { APIRoute } from 'astro';
import {
  ATTENDANCE_BUCKET,
  decodePhoto,
  parseCoordinates,
  photoPath,
} from '../../../lib/attendance';
import { jsonError, redirectBack } from '../../../lib/http';

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

  const path = photoPath(employee.id, rosterId, 'out', decoded.photo.extension);

  const { error: uploadError } = await supabase.storage
    .from(ATTENDANCE_BUCKET)
    .upload(path, decoded.photo.bytes, {
      contentType: decoded.photo.contentType,
      upsert: false,
    });

  if (uploadError) {
    return redirectBack(BACK, { error: `Could not save your photo: ${uploadError.message}` });
  }

  // clock_out records distance but does not refuse an off-site finish: see the
  // function comment for why stranding someone is the worse failure.
  const { data, error } = await supabase.rpc('clock_out', {
    p_roster_id: rosterId,
    p_lat: coords.latitude,
    p_long: coords.longitude,
    p_photo_path: path,
  } as never);

  if (error) {
    await supabase.storage.from(ATTENDANCE_BUCKET).remove([path]);
    return redirectBack(BACK, { error: error.message });
  }

  const result = data as { worked_minutes: number; outside_zone: boolean } | null;

  return redirectBack('/mobile', {
    ok: result?.outside_zone ? 'clocked_out_offsite' : 'clocked_out',
    n: result ? String(result.worked_minutes) : undefined,
  });
};
