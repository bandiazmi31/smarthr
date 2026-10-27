import type { LeaveStatus, LeaveType } from '../types/database';

export const LEAVE_TYPES: readonly LeaveType[] = ['Annual', 'Sick', 'Unpaid'];

export const LEAVE_TYPE_HINTS: Record<LeaveType, string> = {
  Annual: 'Deducted from your annual entitlement.',
  Sick: 'A medical certificate is required beyond the configured number of days.',
  Unpaid: 'Recorded but not deducted from annual leave.',
};

export const LEAVE_STATUS_LABELS: Record<LeaveStatus, string> = {
  pending: 'Awaiting decision',
  approved: 'Approved',
  rejected: 'Rejected',
  cancelled: 'Withdrawn',
};

export const LEAVE_STATUS_STYLES: Record<LeaveStatus, string> = {
  pending: 'bg-amber-100 text-amber-800',
  approved: 'bg-emerald-100 text-emerald-800',
  rejected: 'bg-rose-100 text-rose-800',
  cancelled: 'bg-slate-100 text-slate-600',
};

/** Inclusive calendar days, matching how the database counts a request. */
export function countLeaveDays(startDate: string, endDate: string): number {
  const start = Date.parse(`${startDate}T00:00:00Z`);
  const end = Date.parse(`${endDate}T00:00:00Z`);
  if (Number.isNaN(start) || Number.isNaN(end) || end < start) return 0;
  return Math.round((end - start) / 86_400_000) + 1;
}

export const ALLOWED_LEAVE_DOC_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
] as const;

export const MAX_LEAVE_DOC_BYTES = 10 * 1024 * 1024;

/**
 * The leave functions raise distinct SQLSTATEs so the UI can speak plainly
 * instead of surfacing a Postgres message.
 */
export function describeLeaveError(error: { code?: string; message: string }): string {
  switch (error.code) {
    case 'P0004':
      return error.message; // medical certificate required — already specific
    case 'P0005':
      return error.message; // not enough balance — already quantified
    case '23505':
      return 'You already have a leave request covering those dates.';
    case 'P0007':
      return 'That period is locked for payroll. Ask HR to reopen it first.';
    default:
      return error.message;
  }
}

/**
 * Overtime raises its own SQLSTATEs. Kept separate from describeLeaveError on
 * purpose: sharing it once made a duplicate overtime record report "You already
 * have a leave request covering those dates."
 */
export function describeOvertimeError(error: { code?: string; message: string }): string {
  switch (error.code) {
    case '23505':
      return 'Overtime has already been raised for this shift.';
    case 'P0006':
      return error.message; // nothing recorded yet — already specific
    case 'P0007':
      return 'That period is locked for payroll. Ask HR to reopen it first.';
    default:
      return error.message;
  }
}
