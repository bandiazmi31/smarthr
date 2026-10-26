import type { APIRoute } from 'astro';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

function parseCoordinate(value: string, limit: number): number | null {
  const n = Number.parseFloat(value);
  if (!Number.isFinite(n) || Math.abs(n) > limit) return null;
  return Math.round(n * 1e6) / 1e6;
}

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();

  const hotelName = String(form.get('hotel_name') ?? '').trim();
  const latitude = parseCoordinate(String(form.get('latitude') ?? ''), 90);
  const longitude = parseCoordinate(String(form.get('longitude') ?? ''), 180);
  const radius = Number.parseInt(String(form.get('geofence_radius_meters') ?? ''), 10);
  const timezone = String(form.get('timezone') ?? '').trim();

  if (!hotelName) return redirectBack('/hr/settings', { error: 'Hotel name is required.' });
  if (latitude === null) return redirectBack('/hr/settings', { error: 'Latitude must be between -90 and 90.' });
  if (longitude === null) return redirectBack('/hr/settings', { error: 'Longitude must be between -180 and 180.' });
  if (!Number.isFinite(radius) || radius < 10 || radius > 5000) {
    return redirectBack('/hr/settings', { error: 'Geofence radius must be between 10 and 5000 metres.' });
  }

  // Reject a timezone the runtime cannot resolve, rather than storing something
  // that would silently shift every rostered time.
  try {
    new Intl.DateTimeFormat('en', { timeZone: timezone });
  } catch {
    return redirectBack('/hr/settings', { error: 'That is not a recognised IANA timezone.' });
  }

  const { error } = await locals.supabase
    .from('hotel_settings')
    .update({
      hotel_name: hotelName,
      latitude,
      longitude,
      geofence_radius_meters: radius,
      timezone,
      updated_at: new Date().toISOString(),
      updated_by: locals.actor.userId,
    })
    .eq('id', true);

  if (error) return redirectBack('/hr/settings', { error: error.message });

  return redirectBack('/hr/settings', { ok: 'settings_saved' });
};
