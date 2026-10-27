/**
 * Hand-trimmed mirror of the Supabase schema (see supabase/migrations).
 * Regenerate the full version with:
 *   npx supabase gen types typescript --project-id dnobvrudkdtvdhynplny
 */

export type EmploymentStatus = 'PKWT' | 'PKWTT' | 'Daily Worker';

export type DocumentType =
  | 'ID Card'
  | 'Contract'
  | 'Certificate'
  | 'Tax Card'
  | 'Health Insurance'
  | 'Other';

/** Contract countdown buckets produced by the employee_contract_status view. */
export type AlertLevel = 'expired' | 'critical' | 'warning' | 'ok' | 'none';

export type EmployeeRow = {
  id: string;
  employee_id: string;
  full_name: string;
  phone: string | null;
  national_id: string | null;
  email: string | null;
  address: string | null;
  birth_date: string | null;
  department_id: string;
  user_id: string | null;
  portal_enabled: boolean;
  role: PortalRole;
  auto_schedule_shift_id: string | null;
  job_title: string;
  employment_status: EmploymentStatus;
  join_date: string;
  end_date: string | null;
  is_active: boolean;
  deactivated_at: string | null;
  deactivation_reason: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  created_by: string | null;
};

/** employees plus the resolved department name and the computed contract countdown. */
export type ContractStatusRow = EmployeeRow & {
  department: string;
  days_remaining: number | null;
  alert_level: AlertLevel;
};

export type DepartmentRow = {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
};

/** departments plus assigned headcount; employee_count includes alumni. */
export type DepartmentSummaryRow = DepartmentRow & {
  employee_count: number;
  active_employee_count: number;
};

export type EmployeeDocumentRow = {
  id: string;
  employee_id: string;
  document_type: DocumentType;
  file_path: string;
  file_name: string;
  mime_type: string | null;
  file_size: number | null;
  uploaded_at: string;
  uploaded_by: string | null;
};

export type PortalRole = 'employee' | 'hod';

export type RosterStatus = 'scheduled' | 'in_progress' | 'completed' | 'absent';

export type SwapStatus =
  | 'pending_target'
  | 'pending_hod'
  | 'approved'
  | 'rejected'
  | 'cancelled';

export type HotelSettingsRow = {
  id: boolean;
  hotel_name: string;
  latitude: number;
  longitude: number;
  geofence_radius_meters: number;
  early_clock_in_limit_mins: number;
  photo_retention_days: number;
  annual_leave_days: number;
  sick_cert_required_after_days: number;
  leave_coverage_threshold_pct: number;
  late_penalty_threshold: number;
  late_penalty_pct: number;
  payroll_cutoff_day: number;
  overtime_multiplier: number;
  public_holiday_multiplier: number;
  timezone: string;
  updated_at: string;
  updated_by: string | null;
};

export type MasterShiftRow = {
  id: string;
  name: string;
  code: string;
  start_time: string;
  end_time: string;
  is_overnight: boolean;
  grace_period_mins: number;
  is_active: boolean;
  sort_order: number;
  created_at: string;
};

export type RosterRow = {
  id: string;
  employee_id: string;
  shift_id: string;
  shift_date: string;
  expected_clock_in: string;
  expected_clock_out: string;
  status: RosterStatus;
  note: string | null;
  published_by: string | null;
  created_at: string;
  updated_at: string;
};

export type AttendanceLogRow = {
  id: string;
  roster_id: string;
  clock_in_time: string;
  clock_in_lat: number;
  clock_in_long: number;
  clock_in_distance_meters: number | null;
  clock_in_photo_path: string;
  clock_out_time: string | null;
  clock_out_lat: number | null;
  clock_out_long: number | null;
  clock_out_distance_meters: number | null;
  clock_out_photo_path: string | null;
  is_late: boolean;
  late_by_minutes: number;
  early_leave_minutes: number;
  overtime_minutes: number;
  worked_minutes: number | null;
  photos_purged_at: string | null;
  created_at: string;
};

export type ShiftSwapRow = {
  id: string;
  /** NULL once the roster it described has been deleted; the snapshot below remains. */
  requester_roster_id: string | null;
  target_roster_id: string | null;
  reason: string | null;
  requester_employee_id: string | null;
  requester_name: string | null;
  requester_shift_date: string | null;
  requester_shift_code: string | null;
  target_employee_id: string | null;
  target_name: string | null;
  target_shift_date: string | null;
  target_shift_code: string | null;
  department_id: string | null;
  status: SwapStatus;
  target_responded_at: string | null;
  decided_at: string | null;
  decided_by: string | null;
  decision_note: string | null;
  created_at: string;
};

/** rosters joined to employee, department, shift definition and attendance. */
export type RosterDetailRow = {
  id: string;
  employee_id: string;
  shift_id: string;
  shift_date: string;
  expected_clock_in: string;
  expected_clock_out: string;
  status: RosterStatus;
  note: string | null;
  staff_number: string;
  full_name: string;
  job_title: string;
  department_id: string;
  department_name: string;
  shift_name: string;
  shift_code: string;
  start_time: string;
  end_time: string;
  is_overnight: boolean;
  grace_period_mins: number;
  attendance_id: string | null;
  clock_in_time: string | null;
  clock_out_time: string | null;
  is_late: boolean | null;
  late_by_minutes: number | null;
  worked_minutes: number | null;
  early_leave_minutes: number | null;
  overtime_minutes: number | null;
  clock_in_distance_meters: number | null;
  clock_out_distance_meters: number | null;
  clock_in_photo_path: string | null;
  clock_out_photo_path: string | null;
};

/** What `my_shift_swaps()` returns: the snapshot plus the resolved shift names. */
export type ShiftSwapDetailRow = {
  id: string;
  status: SwapStatus;
  reason: string | null;
  decision_note: string | null;
  created_at: string;
  target_responded_at: string | null;
  decided_at: string | null;
  requester_roster_id: string | null;
  target_roster_id: string | null;
  requester_employee_id: string | null;
  requester_name: string;
  department_id: string | null;
  requester_shift_date: string;
  requester_shift_name: string;
  requester_shift_code: string;
  target_employee_id: string | null;
  target_name: string;
  target_shift_date: string;
  target_shift_name: string;
  target_shift_code: string;
};

/** The `shift_swap_details` view: the raw snapshot, without shift names. */
export type ShiftSwapSummaryRow = Omit<
  ShiftSwapDetailRow,
  'requester_shift_name' | 'target_shift_name'
>;

export type SwappableShiftRow = {
  roster_id: string;
  employee_id: string;
  full_name: string;
  shift_date: string;
  shift_name: string;
  shift_code: string;
  start_time: string;
  end_time: string;
};

export type PortalIdentityRow = {
  id: string;
  user_id: string | null;
  staff_number: string;
  full_name: string;
  job_title: string;
  role: PortalRole;
  department_id: string;
  department_name: string;
  auto_schedule_shift_id: string | null;
  portal_enabled: boolean;
};

export type LeaveType = 'Annual' | 'Sick' | 'Unpaid';
export type LeaveStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';
export type OvertimeStatus = 'pending' | 'approved' | 'rejected' | 'cancelled';
export type PayrollPeriodStatus = 'open' | 'locked';

export type MasterHolidayRow = {
  id: string;
  holiday_date: string;
  description: string;
  multiplier: number | null;
  created_at: string;
};

export type JobLevelRow = {
  id: string;
  name: string;
  base_points: number;
  sort_order: number;
  created_at: string;
};

export type LeaveBalanceRow = {
  id: string;
  employee_id: string;
  year: number;
  annual_allocated: number;
  annual_used: number;
  sick_used: number;
  unpaid_used: number;
  created_at: string;
  updated_at: string;
};

/** What `my_leave_balance()` returns. */
export type MyLeaveBalanceRow = {
  year: number;
  annual_allocated: number;
  annual_used: number;
  annual_remaining: number;
  sick_used: number;
  unpaid_used: number;
};

export type LeaveRequestRow = {
  id: string;
  employee_id: string;
  department_id: string | null;
  leave_type: LeaveType;
  start_date: string;
  end_date: string;
  days_count: number;
  reason: string | null;
  document_path: string | null;
  status: LeaveStatus;
  decided_by: string | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
};

/** What `leave_coverage()` returns. */
export type LeaveCoverageRow = {
  total_staff: number;
  scheduled: number;
  on_leave: number;
  effective: number;
  ratio_pct: number;
  below_threshold: boolean;
};

export type OvertimeRecordRow = {
  id: string;
  roster_id: string;
  employee_id: string;
  department_id: string | null;
  requested_hours: number;
  approved_hours: number | null;
  multiplier_applied: number | null;
  is_public_holiday: boolean;
  reason: string | null;
  status: OvertimeStatus;
  requested_by: string | null;
  decided_by: string | null;
  decided_at: string | null;
  decision_note: string | null;
  created_at: string;
};

/** The `overtime_review` view: request plus what the clock actually recorded. */
export type OvertimeReviewRow = OvertimeRecordRow & {
  full_name: string;
  staff_number: string;
  shift_date: string;
  shift_name: string;
  shift_code: string;
  expected_clock_out: string;
  clock_out_time: string | null;
  actual_overtime_minutes: number;
  actual_overtime_hours: number;
  falls_on_holiday: boolean;
  holiday_description: string | null;
};

export type PayrollPeriodRow = {
  id: string;
  label: string;
  start_date: string;
  end_date: string;
  status: PayrollPeriodStatus;
  locked_at: string | null;
  locked_by: string | null;
  created_at: string;
};

export type ServiceChargePointRow = {
  id: string;
  employee_id: string;
  period_month: number;
  period_year: number;
  period_start: string;
  period_end: string;
  job_level: string | null;
  base_points: number;
  scheduled_days: number;
  worked_days: number;
  prorated_points: number;
  late_count: number;
  penalty_pct: number;
  penalty_deduction: number;
  final_points: number;
  generated_at: string;
};

/** One row of the Finance hand-off. */
export type PrePayrollRow = {
  staff_number: string;
  full_name: string;
  department: string;
  job_title: string;
  job_level: string;
  employment_status: string;
  scheduled_days: number;
  worked_days: number;
  late_count: number;
  total_late_minutes: number;
  total_worked_minutes: number;
  overtime_hours: number;
  overtime_weighted_hours: number;
  holiday_overtime_hours: number;
  annual_leave_days: number;
  sick_leave_days: number;
  unpaid_leave_days: number;
  service_charge_points: number;
};

export type HrProfileRow = {
  id: string;
  full_name: string;
  role: 'hr_admin' | 'hr_manager';
  created_at: string;
};

export type Database = {
  public: {
    Tables: {
      employees: {
        Row: EmployeeRow;
        Insert: Partial<EmployeeRow> & Pick<
          EmployeeRow,
          'employee_id' | 'full_name' | 'department_id' | 'job_title' | 'employment_status' | 'join_date'
        >;
        Update: Partial<EmployeeRow>;
        Relationships: [];
      };
      employee_documents: {
        Row: EmployeeDocumentRow;
        Insert: Partial<EmployeeDocumentRow> & Pick<
          EmployeeDocumentRow,
          'employee_id' | 'document_type' | 'file_path' | 'file_name'
        >;
        Update: Partial<EmployeeDocumentRow>;
        Relationships: [];
      };
      departments: {
        Row: DepartmentRow;
        Insert: Partial<DepartmentRow> & Pick<DepartmentRow, 'name'>;
        Update: Partial<DepartmentRow>;
        Relationships: [];
      };
      hotel_settings: {
        Row: HotelSettingsRow;
        Insert: Partial<HotelSettingsRow>;
        Update: Partial<HotelSettingsRow>;
        Relationships: [];
      };
      master_shifts: {
        Row: MasterShiftRow;
        Insert: Partial<MasterShiftRow> & Pick<MasterShiftRow, 'name' | 'code' | 'start_time' | 'end_time'>;
        Update: Partial<MasterShiftRow>;
        Relationships: [];
      };
      rosters: {
        Row: RosterRow;
        Insert: Partial<RosterRow> & Pick<RosterRow, 'employee_id' | 'shift_id' | 'shift_date'>;
        Update: Partial<RosterRow>;
        Relationships: [];
      };
      attendance_logs: {
        Row: AttendanceLogRow;
        Insert: Partial<AttendanceLogRow> & Pick<AttendanceLogRow, 'roster_id'>;
        Update: Partial<AttendanceLogRow>;
        Relationships: [];
      };
      shift_swaps: {
        Row: ShiftSwapRow;
        Insert: Partial<ShiftSwapRow> & Pick<ShiftSwapRow, 'requester_roster_id' | 'target_roster_id'>;
        Update: Partial<ShiftSwapRow>;
        Relationships: [];
      };
      master_holidays: {
        Row: MasterHolidayRow;
        Insert: Partial<MasterHolidayRow> & Pick<MasterHolidayRow, 'holiday_date' | 'description'>;
        Update: Partial<MasterHolidayRow>;
        Relationships: [];
      };
      job_levels: {
        Row: JobLevelRow;
        Insert: Partial<JobLevelRow> & Pick<JobLevelRow, 'name' | 'base_points'>;
        Update: Partial<JobLevelRow>;
        Relationships: [];
      };
      leave_balances: {
        Row: LeaveBalanceRow;
        Insert: Partial<LeaveBalanceRow> & Pick<LeaveBalanceRow, 'employee_id' | 'year'>;
        Update: Partial<LeaveBalanceRow>;
        Relationships: [];
      };
      leave_requests: {
        Row: LeaveRequestRow;
        Insert: Partial<LeaveRequestRow>;
        Update: Partial<LeaveRequestRow>;
        Relationships: [];
      };
      overtime_records: {
        Row: OvertimeRecordRow;
        Insert: Partial<OvertimeRecordRow>;
        Update: Partial<OvertimeRecordRow>;
        Relationships: [];
      };
      payroll_periods: {
        Row: PayrollPeriodRow;
        Insert: Partial<PayrollPeriodRow> & Pick<PayrollPeriodRow, 'label' | 'start_date' | 'end_date'>;
        Update: Partial<PayrollPeriodRow>;
        Relationships: [];
      };
      service_charge_points: {
        Row: ServiceChargePointRow;
        Insert: Partial<ServiceChargePointRow>;
        Update: Partial<ServiceChargePointRow>;
        Relationships: [];
      };
      hr_profiles: {
        Row: HrProfileRow;
        Insert: Partial<HrProfileRow> & Pick<HrProfileRow, 'id' | 'full_name'>;
        Update: Partial<HrProfileRow>;
        Relationships: [];
      };
    };
    Views: {
      employee_contract_status: {
        Row: ContractStatusRow;
        Relationships: [];
      };
      department_summary: {
        Row: DepartmentSummaryRow;
        Relationships: [];
      };
      roster_details: {
        Row: RosterDetailRow;
        Relationships: [];
      };
      shift_swap_details: {
        Row: ShiftSwapSummaryRow;
        Relationships: [];
      };
      portal_identity: {
        Row: PortalIdentityRow;
        Relationships: [];
      };
      overtime_review: {
        Row: OvertimeReviewRow;
        Relationships: [];
      };
    };
    Functions: {
      is_hr_staff: { Args: Record<string, never>; Returns: boolean };
      clock_in: {
        Args: { p_roster_id: string; p_lat: number; p_long: number; p_photo_path: string };
        Returns: { distance_meters: number; is_late: boolean; late_by_minutes: number };
      };
      clock_out: {
        Args: { p_roster_id: string; p_lat: number; p_long: number; p_photo_path: string };
        Returns: {
          distance_meters: number;
          worked_minutes: number;
          early_leave_minutes: number;
          overtime_minutes: number;
          outside_zone: boolean;
        };
      };
      request_shift_swap: {
        Args: { p_requester_roster_id: string; p_target_roster_id: string; p_reason?: string | null };
        Returns: string;
      };
      respond_shift_swap: { Args: { p_swap_id: string; p_accept: boolean }; Returns: string };
      cancel_shift_swap: { Args: { p_swap_id: string }; Returns: string };
      decide_shift_swap: {
        Args: { p_swap_id: string; p_approve: boolean; p_note?: string | null };
        Returns: string;
      };
      generate_backoffice_rosters: { Args: { p_week_start?: string | null }; Returns: number };
      swappable_shifts: { Args: Record<string, never>; Returns: SwappableShiftRow[] };
      my_shift_swaps: { Args: Record<string, never>; Returns: ShiftSwapDetailRow[] };
      my_leave_balance: { Args: { p_year?: number | null }; Returns: MyLeaveBalanceRow[] };
      leave_coverage: {
        Args: { p_department_id: string; p_date: string };
        Returns: LeaveCoverageRow[];
      };
      request_leave: {
        Args: {
          p_leave_type: string;
          p_start_date: string;
          p_end_date: string;
          p_reason?: string | null;
          p_document_path?: string | null;
        };
        Returns: string;
      };
      decide_leave_request: {
        Args: { p_request_id: string; p_approve: boolean; p_note?: string | null };
        Returns: string;
      };
      cancel_leave_request: { Args: { p_request_id: string }; Returns: string };
      request_overtime: {
        Args: { p_roster_id: string; p_hours: number; p_reason?: string | null };
        Returns: string;
      };
      decide_overtime: {
        Args: {
          p_record_id: string;
          p_approve: boolean;
          p_approved_hours?: number | null;
          p_note?: string | null;
        };
        Returns: number;
      };
      overtime_multiplier_for: { Args: { p_date: string }; Returns: number };
      payroll_period_range: {
        Args: { p_month: number; p_year: number };
        Returns: Array<{ start_date: string; end_date: string }>;
      };
      set_payroll_period_lock: { Args: { p_period_id: string; p_locked: boolean }; Returns: string };
      generate_service_charge_points: { Args: { p_month: number; p_year: number }; Returns: number };
      pre_payroll_timesheet: { Args: { p_start: string; p_end: string }; Returns: PrePayrollRow[] };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
