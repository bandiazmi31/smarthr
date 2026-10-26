import type { APIRoute } from 'astro';
import { ALERT_LEVEL_LABELS } from '../../../lib/constants';
import { applyFilters, parseFilters } from '../../../lib/query';
import type { ContractStatusRow } from '../../../types/database';

export const prerender = false;

/** PostgREST caps a single response; walk pages until the set is exhausted. */
const PAGE_SIZE = 1000;
const MAX_ROWS = 20000;

const COLUMNS: Array<[header: string, value: (row: ContractStatusRow) => string]> = [
  ['Staff Number', (r) => r.employee_id],
  ['Full Name', (r) => r.full_name],
  ['National ID', (r) => r.national_id ?? ''],
  ['Date of Birth', (r) => r.birth_date ?? ''],
  ['Phone', (r) => r.phone ?? ''],
  ['Email', (r) => r.email ?? ''],
  ['Address', (r) => r.address ?? ''],
  ['Department', (r) => r.department],
  ['Job Title', (r) => r.job_title],
  ['Employment Status', (r) => r.employment_status],
  ['Join Date', (r) => r.join_date],
  ['Contract End Date', (r) => r.end_date ?? ''],
  ['Days Until Expiry', (r) => (r.days_remaining === null ? '' : String(r.days_remaining))],
  ['Contract Alert', (r) => ALERT_LEVEL_LABELS[r.alert_level] ?? r.alert_level],
  ['Record State', (r) => (r.is_active ? 'Active' : 'Alumni')],
  ['Deactivated At', (r) => r.deactivated_at ?? ''],
  ['Deactivation Reason', (r) => r.deactivation_reason ?? ''],
  ['Notes', (r) => r.notes ?? ''],
];

/**
 * Quotes per RFC 4180 and neutralises values a spreadsheet would execute as a
 * formula (=, +, -, @ and friends in a leading position).
 */
function csvCell(value: string): string {
  const guarded = /^[=+\-@\t\r]/.test(value) ? `'${value}` : value;
  return /[",\r\n]/.test(guarded) ? `"${guarded.replaceAll('"', '""')}"` : guarded;
}

export const GET: APIRoute = async ({ url, locals }) => {
  const filters = parseFilters(url);

  const rows: ContractStatusRow[] = [];
  for (let offset = 0; offset < MAX_ROWS; offset += PAGE_SIZE) {
    const { data, error } = await applyFilters(
      locals.supabase.from('employee_contract_status').select('*'),
      filters,
    )
      .order('is_active', { ascending: false })
      .order('full_name', { ascending: true })
      .range(offset, offset + PAGE_SIZE - 1);

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const page = (data ?? []) as ContractStatusRow[];
    rows.push(...page);
    if (page.length < PAGE_SIZE) break;
  }

  const lines = [
    COLUMNS.map(([header]) => csvCell(header)).join(','),
    ...rows.map((row) => COLUMNS.map(([, read]) => csvCell(read(row))).join(',')),
  ];

  // CRLF + UTF-8 BOM so Excel opens non-ASCII names correctly on a double-click.
  const csv = `﻿${lines.join('\r\n')}\r\n`;

  const scope = filters.status === 'all' ? 'all' : filters.status;
  const filename = `smart-hr-employees-${scope}-${new Date().toISOString().slice(0, 10)}.csv`;

  return new Response(csv, {
    status: 200,
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'private, no-store',
    },
  });
};
