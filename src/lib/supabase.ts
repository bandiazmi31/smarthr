import { createServerClient, parseCookieHeader } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { AstroCookies } from 'astro';
import type { Database } from '../types/database';

const supabaseUrl = import.meta.env.SUPABASE_URL;
const supabaseAnonKey = import.meta.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing SUPABASE_URL / SUPABASE_ANON_KEY. Copy .env.example to .env and fill both in.',
  );
}

export type SmartHrClient = SupabaseClient<Database>;

/**
 * One client per request. Session tokens live in HTTP-only cookies and are read
 * from the incoming request; token refreshes are written straight back onto the
 * outgoing response by `setAll`.
 */
export function createSupabaseServerClient(ctx: {
  request: Request;
  cookies: AstroCookies;
}): SmartHrClient {
  return createServerClient<Database>(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        return parseCookieHeader(ctx.request.headers.get('Cookie') ?? '');
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          ctx.cookies.set(name, value, {
            ...options,
            path: options.path ?? '/',
            httpOnly: true,
            secure: import.meta.env.PROD,
            sameSite: 'lax',
          });
        }
      },
    },
  });
}

export const DOCUMENT_BUCKET = 'employee-documents';

/** How long a document link stays valid once minted. */
export const SIGNED_URL_TTL_SECONDS = 60 * 5;
