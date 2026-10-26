import type { APIRoute } from 'astro';
import { redirectBack } from '../../../lib/http';

export const prerender = false;

export const POST: APIRoute = async ({ locals }) => {
  await locals.supabase.auth.signOut();
  return redirectBack('/login', { ok: 'signed_out' });
};
