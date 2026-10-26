import type { AlertLevel } from '../types/database';

export type StatusFilter = 'active' | 'inactive' | 'all';
export type AlertFilter = 'all' | 'attention' | 'expiring' | 'expired';

export interface EmployeeFilters {
  search: string;
  department: string;
  employment: string;
  status: StatusFilter;
  alert: AlertFilter;
  page: number;
  perPage: number;
}

export const DEFAULT_PER_PAGE = 25;

/** Alert buckets each filter maps to, matching the employee_contract_status view. */
const ALERT_LEVELS: Record<Exclude<AlertFilter, 'all'>, AlertLevel[]> = {
  attention: ['expired', 'critical', 'warning'],
  expiring: ['critical', 'warning'],
  expired: ['expired'],
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function one(url: URL, key: string): string {
  return (url.searchParams.get(key) ?? '').trim();
}

export function parseFilters(url: URL): EmployeeFilters {
  const status = one(url, 'status');
  const alert = one(url, 'alert');
  const page = Number.parseInt(one(url, 'page') || '1', 10);
  // Carries a departments.id; anything else is a stale or hand-edited link.
  const department = one(url, 'department');

  return {
    search: one(url, 'q').slice(0, 80),
    department: UUID.test(department) ? department : '',
    employment: one(url, 'employment'),
    status: status === 'inactive' || status === 'all' ? status : 'active',
    alert:
      alert === 'attention' || alert === 'expiring' || alert === 'expired' ? alert : 'all',
    page: Number.isFinite(page) && page > 0 ? page : 1,
    perPage: DEFAULT_PER_PAGE,
  };
}

/** PostgREST treats , . ( ) * as syntax inside or(); keep them out of the pattern. */
function sanitizePattern(term: string): string {
  return term.replace(/[,.()*%\\]/g, ' ').trim();
}

/**
 * Narrows an employee_contract_status query to the current filters, used by both
 * the directory page and the CSV export so the two can never disagree.
 *
 * The builder is threaded through untyped: PostgREST's column generics are keyed
 * to each call site's select(), and there is no public type that expresses
 * "same builder, extra predicates". The returned type is the caller's own.
 */
export function applyFilters<Q>(query: Q, filters: EmployeeFilters): Q {
  let next = query as any;

  if (filters.status !== 'all') {
    next = next.eq('is_active', filters.status === 'active');
  }

  if (filters.department) next = next.eq('department_id', filters.department);
  if (filters.employment) next = next.eq('employment_status', filters.employment);

  if (filters.alert !== 'all') {
    next = next.in('alert_level', ALERT_LEVELS[filters.alert]);
  }

  const term = sanitizePattern(filters.search);
  if (term) {
    next = next.or(
      ['full_name', 'employee_id', 'job_title', 'department']
        .map((column) => `${column}.ilike.%${term}%`)
        .join(','),
    );  // `department` here is the view's resolved name, so search still matches it.
  }

  return next as Q;
}

/** Rebuilds the current query string with one value changed. */
export function filterHref(
  url: URL,
  patch: Record<string, string | number | null>,
): string {
  const params = new URLSearchParams(url.search);
  for (const [key, value] of Object.entries(patch)) {
    if (value === null || value === '') params.delete(key);
    else params.set(key, String(value));
  }
  // Any filter change invalidates the current page offset.
  if (!('page' in patch)) params.delete('page');
  const query = params.toString();
  return query ? `${url.pathname}?${query}` : url.pathname;
}
