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
  created_at: string;
};

export type ShiftSwapRow = {
  id: string;
  requester_roster_id: string;
  target_roster_id: string;
  reason: string | null;
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

export type ShiftSwapDetailRow = {
  id: string;
  status: SwapStatus;
  reason: string | null;
  decision_note: string | null;
  created_at: string;
  target_responded_at: string | null;
  decided_at: string | null;
  requester_roster_id: string;
  target_roster_id: string;
  requester_employee_id: string;
  requester_name: string;
  department_id: string;
  requester_shift_date: string;
  requester_shift_name: string;
  requester_shift_code: string;
  target_employee_id: string;
  target_name: string;
  target_shift_date: string;
  target_shift_name: string;
  target_shift_code: string;
};

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
        Row: ShiftSwapDetailRow;
        Relationships: [];
      };
      portal_identity: {
        Row: PortalIdentityRow;
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
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
