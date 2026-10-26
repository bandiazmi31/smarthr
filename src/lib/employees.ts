import { EMPLOYMENT_STATUSES } from './constants';
import type { EmploymentStatus, PortalRole } from '../types/database';

export interface EmployeeFormValues {
  employee_id: string;
  full_name: string;
  phone: string | null;
  national_id: string | null;
  email: string | null;
  address: string | null;
  birth_date: string | null;
  department_id: string;
  job_title: string;
  employment_status: EmploymentStatus;
  join_date: string;
  end_date: string | null;
  notes: string | null;
  portal_enabled: boolean;
  role: PortalRole;
  auto_schedule_shift_id: string | null;
}

export type FieldErrors = Record<string, string>;

export type ParseResult =
  | { ok: true; values: EmployeeFormValues }
  | { ok: false; errors: FieldErrors; raw: Record<string, string> };

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function text(form: FormData, key: string): string {
  const value = form.get(key);
  return typeof value === 'string' ? value.trim() : '';
}

function nullable(value: string): string | null {
  return value.length > 0 ? value : null;
}

function isValidDate(value: string): boolean {
  if (!ISO_DATE.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

/**
 * Validates an employee create/update submission. Mirrors the CHECK constraints
 * in the database so the admin gets field-level feedback instead of a 500.
 */
export function parseEmployeeForm(form: FormData): ParseResult {
  const raw = {
    employee_id: text(form, 'employee_id'),
    full_name: text(form, 'full_name'),
    phone: text(form, 'phone'),
    national_id: text(form, 'national_id'),
    email: text(form, 'email'),
    address: text(form, 'address'),
    birth_date: text(form, 'birth_date'),
    department_id: text(form, 'department_id'),
    job_title: text(form, 'job_title'),
    employment_status: text(form, 'employment_status'),
    join_date: text(form, 'join_date'),
    end_date: text(form, 'end_date'),
    notes: text(form, 'notes'),
    // An unchecked checkbox is simply absent from the payload.
    portal_enabled: form.get('portal_enabled') === 'on' ? 'on' : '',
    role: text(form, 'role') || 'employee',
    auto_schedule_shift_id: text(form, 'auto_schedule_shift_id'),
  };

  const errors: FieldErrors = {};

  if (!raw.employee_id) errors.employee_id = 'Staff number is required.';
  else if (raw.employee_id.length > 50) errors.employee_id = 'Staff number must be 50 characters or fewer.';

  if (!raw.full_name) errors.full_name = 'Full name is required.';
  else if (raw.full_name.length > 150) errors.full_name = 'Full name must be 150 characters or fewer.';

  // Departments come from master data, so an unknown value is a stale form, not a typo.
  if (!raw.department_id) errors.department_id = 'Department is required.';
  else if (!UUID.test(raw.department_id)) {
    errors.department_id = 'That department no longer exists. Pick one from the list.';
  }

  if (!raw.job_title) errors.job_title = 'Job title is required.';

  if (!EMPLOYMENT_STATUSES.includes(raw.employment_status as EmploymentStatus)) {
    errors.employment_status = 'Choose an employment status.';
  }

  if (!raw.join_date) errors.join_date = 'Join date is required.';
  else if (!isValidDate(raw.join_date)) errors.join_date = 'Join date must be a real date.';

  if (raw.end_date && !isValidDate(raw.end_date)) {
    errors.end_date = 'Contract end date must be a real date.';
  }

  if (raw.birth_date && !isValidDate(raw.birth_date)) {
    errors.birth_date = 'Date of birth must be a real date.';
  }

  if (
    !errors.join_date &&
    !errors.end_date &&
    raw.end_date &&
    raw.end_date < raw.join_date
  ) {
    errors.end_date = 'Contract end date cannot fall before the join date.';
  }

  // A fixed-term contract without an end date can never raise a renewal alert,
  // which is the whole point of Phase 1.
  if (raw.employment_status === 'PKWT' && !raw.end_date) {
    errors.end_date = 'PKWT contracts must have an end date so renewal alerts can fire.';
  }

  if (raw.email && !EMAIL.test(raw.email)) errors.email = 'Enter a valid email address.';

  if (raw.phone && !/^[+\d][\d\s()-]{5,24}$/.test(raw.phone)) {
    errors.phone = 'Enter a valid phone number.';
  }

  if (raw.national_id && !/^[A-Za-z0-9]{6,20}$/.test(raw.national_id)) {
    errors.national_id = 'National ID (NIK/passport) must be 6-20 letters or digits.';
  }

  // The portal links an account by matching this email, so it cannot be blank.
  if (raw.portal_enabled === 'on' && !raw.email) {
    errors.portal_enabled = 'Portal access needs an email address on the record.';
  }

  if (raw.role !== 'employee' && raw.role !== 'hod') {
    errors.role = 'Choose a portal role.';
  }

  if (raw.auto_schedule_shift_id && !UUID.test(raw.auto_schedule_shift_id)) {
    errors.auto_schedule_shift_id = 'Pick a shift from the list.';
  }

  if (Object.keys(errors).length > 0) return { ok: false, errors, raw };

  return {
    ok: true,
    values: {
      employee_id: raw.employee_id,
      full_name: raw.full_name,
      phone: nullable(raw.phone),
      national_id: nullable(raw.national_id),
      email: nullable(raw.email),
      address: nullable(raw.address),
      birth_date: nullable(raw.birth_date),
      department_id: raw.department_id,
      job_title: raw.job_title,
      employment_status: raw.employment_status as EmploymentStatus,
      join_date: raw.join_date,
      end_date: nullable(raw.end_date),
      notes: nullable(raw.notes),
      portal_enabled: raw.portal_enabled === 'on',
      role: raw.role as PortalRole,
      auto_schedule_shift_id: nullable(raw.auto_schedule_shift_id),
    },
  };
}

/**
 * Maps a Postgres error onto the field that caused it, so the message lands next
 * to the input the admin has to change rather than at the top of the form.
 */
export function describeDbError(error: { code?: string; message: string }): FieldErrors {
  if (error.code === '23505') {
    return {
      employee_id: error.message.includes('employees_employee_id_key')
        ? 'That staff number is already used by another employee record.'
        : 'A record with those details already exists.',
    };
  }

  if (error.code === '23503') {
    return { department_id: 'That department no longer exists. Pick one from the list.' };
  }

  if (error.code === '23514') {
    if (error.message.includes('fixed_term_needs_end_date')) {
      return { end_date: 'PKWT contracts must have an end date.' };
    }
    if (error.message.includes('end_date_after_join')) {
      return { end_date: 'Contract end date cannot fall before the join date.' };
    }
    return { employee_id: 'The record failed a database validation rule.' };
  }

  return { employee_id: error.message };
}
