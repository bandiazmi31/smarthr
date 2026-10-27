import type { APIRoute } from 'astro';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

const BACK = '/hr/settings';

interface Field {
  name: string;
  min: number;
  max: number;
  integer: boolean;
  label: string;
}

/** Mirrors the CHECK constraints on hotel_settings, so the admin gets a message. */
const FIELDS: Field[] = [
  { name: 'annual_leave_days', min: 0, max: 365, integer: true, label: 'Annual leave days' },
  { name: 'sick_cert_required_after_days', min: 0, max: 30, integer: true, label: 'Sick certificate threshold' },
  { name: 'leave_coverage_threshold_pct', min: 0, max: 100, integer: true, label: 'Coverage threshold' },
  { name: 'payroll_cutoff_day', min: 1, max: 28, integer: true, label: 'Payroll cut-off day' },
  { name: 'late_penalty_threshold', min: 0, max: 31, integer: true, label: 'Late count before penalty' },
  { name: 'late_penalty_pct', min: 0, max: 100, integer: false, label: 'Point penalty' },
  { name: 'overtime_multiplier', min: 1, max: 10, integer: false, label: 'Overtime rate' },
  { name: 'public_holiday_multiplier', min: 1, max: 10, integer: false, label: 'Public holiday rate' },
];

export const POST: APIRoute = async ({ request, locals }) => {
  const form = await request.formData();
  const patch: Record<string, number> = {};

  for (const field of FIELDS) {
    const raw = String(form.get(field.name) ?? '').trim();
    const value = field.integer ? Number.parseInt(raw, 10) : Number.parseFloat(raw);

    if (!Number.isFinite(value) || value < field.min || value > field.max) {
      return redirectBack(BACK, {
        error: `${field.label} must be between ${field.min} and ${field.max}.`,
      });
    }

    patch[field.name] = value;
  }

  const { error } = await locals.supabase
    .from('hotel_settings')
    .update({ ...patch, updated_at: new Date().toISOString(), updated_by: locals.actor.userId })
    .eq('id', true);

  if (error) return redirectBack(BACK, { error: error.message });

  return redirectBack(BACK, { ok: 'settings_saved' });
};
