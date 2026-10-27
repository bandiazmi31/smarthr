import type { PrePayrollRow } from '../types/database';

export const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
] as const;

export function monthLabel(month: number, year: number): string {
  return `${MONTH_NAMES[month - 1] ?? month} ${year}`;
}

/** Column order for both the on-screen table and the Finance export. */
export const PRE_PAYROLL_COLUMNS: Array<{
  key: keyof PrePayrollRow;
  header: string;
  numeric: boolean;
  width: number;
}> = [
  { key: 'staff_number', header: 'Staff Number', numeric: false, width: 14 },
  { key: 'full_name', header: 'Full Name', numeric: false, width: 26 },
  { key: 'department', header: 'Department', numeric: false, width: 24 },
  { key: 'job_title', header: 'Job Title', numeric: false, width: 24 },
  { key: 'job_level', header: 'Job Level', numeric: false, width: 14 },
  { key: 'employment_status', header: 'Employment Status', numeric: false, width: 18 },
  { key: 'scheduled_days', header: 'Scheduled Days', numeric: true, width: 15 },
  { key: 'worked_days', header: 'Worked Days', numeric: true, width: 13 },
  { key: 'late_count', header: 'Late Instances', numeric: true, width: 15 },
  { key: 'total_late_minutes', header: 'Late Minutes', numeric: true, width: 14 },
  { key: 'total_worked_minutes', header: 'Worked Minutes', numeric: true, width: 15 },
  { key: 'overtime_hours', header: 'Overtime Hours', numeric: true, width: 15 },
  { key: 'overtime_weighted_hours', header: 'Overtime Hours (Weighted)', numeric: true, width: 24 },
  { key: 'holiday_overtime_hours', header: 'Holiday Overtime Hours', numeric: true, width: 22 },
  { key: 'annual_leave_days', header: 'Annual Leave Days', numeric: true, width: 18 },
  { key: 'sick_leave_days', header: 'Sick Leave Days', numeric: true, width: 16 },
  { key: 'unpaid_leave_days', header: 'Unpaid Leave Days', numeric: true, width: 18 },
  { key: 'service_charge_points', header: 'Service Charge Points', numeric: true, width: 21 },
];

export function totalsFor(rows: PrePayrollRow[]) {
  return rows.reduce(
    (acc, row) => ({
      scheduledDays: acc.scheduledDays + Number(row.scheduled_days),
      workedDays: acc.workedDays + Number(row.worked_days),
      lateCount: acc.lateCount + Number(row.late_count),
      overtimeHours: acc.overtimeHours + Number(row.overtime_hours),
      points: acc.points + Number(row.service_charge_points),
    }),
    { scheduledDays: 0, workedDays: 0, lateCount: 0, overtimeHours: 0, points: 0 },
  );
}
