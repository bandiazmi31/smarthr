import type { APIRoute } from 'astro';
import ExcelJS from 'exceljs';
import { PRE_PAYROLL_COLUMNS } from '../../../lib/payroll';
import { jsonError } from '../../../lib/http';
import type { PrePayrollRow } from '../../../types/database';

export const prerender = false;

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * PRD v3 §4.4: the Finance hand-off. The aggregation itself is one database
 * call (pre_payroll_timesheet), which also authorises the caller — this route
 * only shapes the result into a workbook.
 */
export const GET: APIRoute = async ({ url, locals }) => {
  const start = url.searchParams.get('start') ?? '';
  const end = url.searchParams.get('end') ?? '';

  if (!ISO_DATE.test(start) || !ISO_DATE.test(end)) {
    return jsonError('A valid start and end date are required.');
  }
  if (end < start) return jsonError('The end date cannot fall before the start date.');

  const { data, error } = await locals.supabase.rpc('pre_payroll_timesheet', {
    p_start: start,
    p_end: end,
  } as never);

  if (error) {
    return jsonError(error.message, error.code === '42501' ? 403 : 500);
  }

  const rows = (data ?? []) as PrePayrollRow[];

  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'Smart HR';
  workbook.created = new Date();

  const sheet = workbook.addWorksheet('Pre-Payroll', {
    views: [{ state: 'frozen', ySplit: 1 }],
  });

  sheet.columns = PRE_PAYROLL_COLUMNS.map((column) => ({
    header: column.header,
    key: column.key,
    width: column.width,
  }));

  sheet.getRow(1).font = { bold: true };
  sheet.getRow(1).fill = {
    type: 'pattern',
    pattern: 'solid',
    fgColor: { argb: 'FFE8EEF7' },
  };

  for (const row of rows) {
    sheet.addRow(
      Object.fromEntries(
        PRE_PAYROLL_COLUMNS.map((column) => [
          column.key,
          column.numeric ? Number(row[column.key]) : row[column.key],
        ]),
      ),
    );
  }

  // A totals row, so Finance can sanity-check the import at a glance.
  if (rows.length > 0) {
    const totals = sheet.addRow(
      Object.fromEntries(
        PRE_PAYROLL_COLUMNS.map((column) => {
          if (column.key === 'staff_number') return [column.key, 'TOTAL'];
          if (!column.numeric) return [column.key, ''];
          const sum = rows.reduce((acc, row) => acc + Number(row[column.key]), 0);
          return [column.key, Math.round(sum * 100) / 100];
        }),
      ),
    );
    totals.font = { bold: true };
    totals.border = { top: { style: 'thin' } };
  }

  sheet.autoFilter = {
    from: { row: 1, column: 1 },
    to: { row: 1, column: PRE_PAYROLL_COLUMNS.length },
  };

  const buffer = await workbook.xlsx.writeBuffer();
  const filename = `smart-hr-pre-payroll-${start}_to_${end}.xlsx`;

  return new Response(buffer as ArrayBuffer, {
    status: 200,
    headers: {
      'Content-Type':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'private, no-store',
    },
  });
};
