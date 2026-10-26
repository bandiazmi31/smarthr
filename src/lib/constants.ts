import type { AlertLevel, DocumentType, EmploymentStatus } from '../types/database';

/** Contracts entering this window show up on the dashboard alert panel. */
export const CONTRACT_ALERT_WINDOW_DAYS = 30;

export const EMPLOYMENT_STATUSES: readonly EmploymentStatus[] = [
  'PKWT',
  'PKWTT',
  'Daily Worker',
];

export const EMPLOYMENT_STATUS_LABELS: Record<EmploymentStatus, string> = {
  PKWT: 'PKWT (fixed-term)',
  PKWTT: 'PKWTT (permanent)',
  'Daily Worker': 'Daily Worker',
};

export const DOCUMENT_TYPES: readonly DocumentType[] = [
  'ID Card',
  'Contract',
  'Certificate',
  'Tax Card',
  'Health Insurance',
  'Other',
];

export const ALLOWED_DOCUMENT_MIME_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
] as const;

export const MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;

export const ALERT_LEVEL_LABELS: Record<AlertLevel, string> = {
  expired: 'Expired',
  critical: 'Expires this week',
  warning: 'Expiring soon',
  ok: 'Active',
  none: 'Permanent',
};
