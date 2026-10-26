export interface DepartmentFormValues {
  name: string;
  description: string | null;
}

export type DepartmentErrors = Record<string, string>;

export type DepartmentParseResult =
  | { ok: true; values: DepartmentFormValues }
  | { ok: false; errors: DepartmentErrors; raw: Record<string, string> };

export const MAX_DEPARTMENT_NAME_LENGTH = 100;

export function parseDepartmentForm(form: FormData): DepartmentParseResult {
  const raw = {
    name: String(form.get('name') ?? '').trim(),
    description: String(form.get('description') ?? '').trim(),
  };

  const errors: DepartmentErrors = {};

  if (!raw.name) {
    errors.name = 'Department name is required.';
  } else if (raw.name.length > MAX_DEPARTMENT_NAME_LENGTH) {
    errors.name = `Department name must be ${MAX_DEPARTMENT_NAME_LENGTH} characters or fewer.`;
  }

  if (raw.description.length > 1000) {
    errors.description = 'Description must be 1000 characters or fewer.';
  }

  if (Object.keys(errors).length > 0) return { ok: false, errors, raw };

  return {
    ok: true,
    values: { name: raw.name, description: raw.description || null },
  };
}

/**
 * Turns the two constraints that can realistically fire into HR-readable text.
 * 23505 is the case-insensitive unique index; 23503 is an employee still pointing
 * at the department (the FK is ON DELETE RESTRICT).
 */
export function describeDepartmentError(
  error: { code?: string; message: string },
  name?: string,
): string {
  if (error.code === '23505') {
    return name
      ? `A department named "${name}" already exists.`
      : 'A department with that name already exists.';
  }
  if (error.code === '23503') {
    return 'Employees are still assigned to this department. Reassign them first.';
  }
  if (error.code === '23514') return 'Department name cannot be blank.';
  return error.message;
}
