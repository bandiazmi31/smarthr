import type { HrProfileRow, PortalIdentityRow } from '../types/database';

/**
 * Who is making this request. An account can be both HR staff and a linked
 * employee; `kind` reports the highest privilege, while `isHr` / `isHod` /
 * `employee` stay independently available.
 */
export type ActorKind = 'anonymous' | 'hr' | 'hod' | 'employee';

export interface Actor {
  kind: ActorKind;
  userId: string | null;
  email: string | null;
  displayName: string;
  hrProfile: HrProfileRow | null;
  employee: PortalIdentityRow | null;
  isHr: boolean;
  isHod: boolean;
  /** Where this actor belongs after signing in. */
  home: string;
}

export const ANONYMOUS: Actor = {
  kind: 'anonymous',
  userId: null,
  email: null,
  displayName: '',
  hrProfile: null,
  employee: null,
  isHr: false,
  isHod: false,
  home: '/login',
};

export function buildActor(input: {
  userId: string;
  email: string | null;
  hrProfile: HrProfileRow | null;
  employee: PortalIdentityRow | null;
}): Actor {
  const { userId, email, hrProfile, employee } = input;
  const isHr = Boolean(hrProfile);
  const isHod = employee?.role === 'hod';

  const kind: ActorKind = isHr ? 'hr' : isHod ? 'hod' : employee ? 'employee' : 'anonymous';

  return {
    kind,
    userId,
    email,
    displayName: hrProfile?.full_name ?? employee?.full_name ?? email ?? '',
    hrProfile,
    employee,
    isHr,
    isHod,
    home: isHr ? '/hr/employees' : isHod ? '/hod/roster' : employee ? '/mobile' : '/login',
  };
}

/** True when the actor may act on this department's rosters and swaps. */
export function canManageDepartment(actor: Actor, departmentId: string): boolean {
  if (actor.isHr) return true;
  return actor.isHod && actor.employee?.department_id === departmentId;
}
