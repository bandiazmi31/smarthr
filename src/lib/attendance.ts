import { jsonError, redirectBack } from './http';

export const ATTENDANCE_BUCKET = 'attendance-photos';

/** 3 MB, matching the bucket's own limit. */
export const MAX_PHOTO_BYTES = 3 * 1024 * 1024;

const DATA_URL = /^data:(image\/jpeg|image\/png);base64,([A-Za-z0-9+/=]+)$/;

export interface DecodedPhoto {
  bytes: Uint8Array;
  contentType: 'image/jpeg' | 'image/png';
  extension: 'jpg' | 'png';
}

export type PhotoResult =
  | { ok: true; photo: DecodedPhoto }
  | { ok: false; error: string };

/**
 * The camera hands us a data URL rather than a file, so the payload is decoded
 * and size-checked here before anything reaches storage.
 */
export function decodePhoto(value: unknown): PhotoResult {
  if (typeof value !== 'string' || value.length === 0) {
    return { ok: false, error: 'A selfie is required to clock in or out.' };
  }

  const match = DATA_URL.exec(value.trim());
  if (!match) return { ok: false, error: 'That photo format is not supported.' };

  const contentType = match[1] as 'image/jpeg' | 'image/png';

  let bytes: Uint8Array;
  try {
    const binary = atob(match[2]!);
    bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
  } catch {
    return { ok: false, error: 'That photo could not be read.' };
  }

  if (bytes.byteLength === 0) return { ok: false, error: 'That photo is empty.' };
  if (bytes.byteLength > MAX_PHOTO_BYTES) {
    return { ok: false, error: 'That photo is too large. Try again.' };
  }

  return {
    ok: true,
    photo: { bytes, contentType, extension: contentType === 'image/png' ? 'png' : 'jpg' },
  };
}

export interface ParsedCoordinates {
  latitude: number;
  longitude: number;
}

export function parseCoordinates(form: FormData): ParsedCoordinates | null {
  const latitude = Number.parseFloat(String(form.get('latitude') ?? ''));
  const longitude = Number.parseFloat(String(form.get('longitude') ?? ''));

  if (!Number.isFinite(latitude) || Math.abs(latitude) > 90) return null;
  if (!Number.isFinite(longitude) || Math.abs(longitude) > 180) return null;

  return {
    latitude: Math.round(latitude * 1e6) / 1e6,
    longitude: Math.round(longitude * 1e6) / 1e6,
  };
}

/** Storage key. The leading folder is the employee id, which the bucket policy enforces. */
export function photoPath(
  employeeId: string,
  rosterId: string,
  kind: 'in' | 'out',
  extension: string,
): string {
  return `${employeeId}/${rosterId}-${kind}-${crypto.randomUUID()}.${extension}`;
}

export { jsonError, redirectBack };
