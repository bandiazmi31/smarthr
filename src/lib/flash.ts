import type { AstroCookies } from 'astro';
import type { FieldErrors } from './employees';

const COOKIE = 'smarthr_form';
const MAX_FIELD_LENGTH = 500;
/** Browsers cap a cookie at ~4 KB; stay well clear of it. */
const MAX_COOKIE_BYTES = 3500;

export interface FormFlash {
  errors: FieldErrors;
  values: Record<string, string>;
}

/**
 * Hands a rejected submission back to the form page across a redirect, so the
 * admin sees field-level errors on top of what they actually typed.
 */
export function setFormFlash(cookies: AstroCookies, flash: FormFlash): void {
  const values: Record<string, string> = {};
  for (const [key, value] of Object.entries(flash.values)) {
    if (value) values[key] = value.slice(0, MAX_FIELD_LENGTH);
  }

  const payload = JSON.stringify({ errors: flash.errors, values });
  if (new TextEncoder().encode(payload).length > MAX_COOKIE_BYTES) {
    // Too large to round-trip: keep the errors, drop the echoed values.
    cookies.set(COOKIE, JSON.stringify({ errors: flash.errors, values: {} }), options());
    return;
  }

  cookies.set(COOKIE, payload, options());
}

/** Reads the flash and clears it, so a refresh shows a clean form. */
export function takeFormFlash(cookies: AstroCookies): FormFlash | null {
  const cookie = cookies.get(COOKIE);
  if (!cookie) return null;

  cookies.delete(COOKIE, { path: '/' });

  try {
    const parsed = cookie.json() as FormFlash;
    if (!parsed || typeof parsed !== 'object') return null;
    return { errors: parsed.errors ?? {}, values: parsed.values ?? {} };
  } catch {
    return null;
  }
}

function options() {
  return {
    path: '/',
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: import.meta.env.PROD,
    maxAge: 120,
  };
}
