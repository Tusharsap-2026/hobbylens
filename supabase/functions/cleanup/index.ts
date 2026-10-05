// POST /functions/v1/cleanup   (called hourly by a scheduled job, not by the app)
// Header: Authorization: Bearer <CLEANUP_SECRET>
// 1. Deletes temporary identification photos older than their 24-hour expiry.
// 2. Deletes guest (anonymous) accounts not seen for ANON_USER_TTL_DAYS days.
import { safeEqual } from "../_shared/auth.ts";
import { bearer, handler, json } from "../_shared/http.ts";
import { serviceClient, SupabaseStore } from "../_shared/store_supabase.ts";
import { HttpError } from "../_shared/types.ts";

const db = serviceClient();
const store = new SupabaseStore(db);
const secret = Deno.env.get("CLEANUP_SECRET") ?? "";
const anonTtlDays = Number(Deno.env.get("ANON_USER_TTL_DAYS") ?? "30");

Deno.serve(handler(async (req) => {
  if (secret.length < 24 || !safeEqual(bearer(req), secret)) {
    throw new HttpError(401, "unauthorised", "bad cleanup secret");
  }

  // Files are removed before the rows are cleared, so a failure leaves the row in place and
  // the next run tries again; no photo is ever left behind without a record pointing to it.
  const { data: expired, error } = await db
    .from("identifications")
    .select("id, photo_path")
    .not("photo_path", "is", null)
    .lt("photo_expires_at", new Date().toISOString())
    .order("photo_expires_at")
    .limit(500);
  if (error) throw error;
  const rows = (expired ?? []) as Array<{ id: string; photo_path: string }>;
  if (rows.length > 0) {
    await store.removePhotos(rows.map((r) => r.photo_path));
    const { error: upErr } = await db
      .from("identifications")
      .update({ photo_path: null, photo_expires_at: null })
      .in("id", rows.map((r) => r.id));
    if (upErr) throw upErr;
  }

  const { data: stale, error: e2 } = await db.rpc("stale_anonymous_users", { p_days: anonTtlDays, p_limit: 200 });
  if (e2) throw e2;
  let guestsDeleted = 0;
  for (const row of (stale ?? []) as Array<{ user_id: string }>) {
    const { data: owned, error: e3 } = await db.rpc("user_photo_paths", { p_user_id: row.user_id });
    if (e3) throw e3;
    await store.removePhotos(((owned ?? []) as Array<{ path: string }>).map((p) => p.path));
    const { error: delErr } = await db.auth.admin.deleteUser(row.user_id);
    if (delErr) console.error("guest delete failed", row.user_id, delErr);
    else guestsDeleted++;
  }

  return json({ photosRemoved: rows.length, guestsDeleted });
}));
