// Deletes clock-in/out selfies once they pass the retention window
// (PRD v2.0: 90 days). Runs as an Edge Function rather than in Postgres for one
// reason: deleting a row from storage.objects leaves the underlying file behind,
// so the bytes are only reclaimed through the Storage API.
//
// The service-role key is injected by the platform and never leaves it — it is
// not in the repo, not in .env, and not reachable by the Astro app, which still
// runs purely on the anon key under RLS.
import { createClient } from 'jsr:@supabase/supabase-js@2.49.4';

const BUCKET = 'attendance-photos';
/** Storage caps a remove() call; stay well inside it. */
const BATCH = 200;

Deno.serve(async (request: Request): Promise<Response> => {
  // Invoked by pg_cron, so authenticate with a shared secret rather than a JWT.
  const expected = Deno.env.get('PURGE_SECRET');
  if (!expected || request.headers.get('x-purge-secret') !== expected) {
    return Response.json({ error: 'Forbidden' }, { status: 403 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const { data: due, error: selectError } = await supabase.rpc(
    'attendance_photos_to_purge',
    { p_limit: BATCH },
  );

  if (selectError) {
    return Response.json({ error: selectError.message }, { status: 500 });
  }

  const rows = (due ?? []) as Array<{
    id: string;
    clock_in_photo_path: string | null;
    clock_out_photo_path: string | null;
  }>;

  if (rows.length === 0) {
    return Response.json({ purged: 0, objects_removed: 0 });
  }

  const paths = rows
    .flatMap((row) => [row.clock_in_photo_path, row.clock_out_photo_path])
    .filter((path): path is string => Boolean(path));

  const { error: removeError } = await supabase.storage.from(BUCKET).remove(paths);

  // Don't mark anything purged if the objects are still there; the next run
  // retries rather than losing track of them.
  if (removeError) {
    return Response.json({ error: removeError.message }, { status: 502 });
  }

  const { data: marked, error: markError } = await supabase.rpc(
    'mark_attendance_photos_purged',
    { p_ids: rows.map((row) => row.id) },
  );

  if (markError) {
    return Response.json({ error: markError.message }, { status: 500 });
  }

  return Response.json({
    purged: marked ?? 0,
    objects_removed: paths.length,
    // Signals to the caller that another batch is waiting.
    more: rows.length === BATCH,
  });
});
