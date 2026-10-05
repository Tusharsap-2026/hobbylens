// POST /functions/v1/delete-account
// Deletes every photo the user owns, then the user. Database rows go with the user through
// ON DELETE CASCADE (profile, identifications, collection, reminders, flags, events).
import { requireUser } from "../_shared/auth.ts";
import { handler, json } from "../_shared/http.ts";
import { serviceClient, SupabaseStore } from "../_shared/store_supabase.ts";
import { HttpError } from "../_shared/types.ts";

const db = serviceClient();
const store = new SupabaseStore(db);

Deno.serve(handler(async (req) => {
  const user = await requireUser(req, db);

  const { data: paths, error } = await db.rpc("user_photo_paths", { p_user_id: user.id });
  if (error) throw error;
  const list = ((paths ?? []) as Array<{ path: string }>).map((p) => p.path);
  // Files first: if this fails the account still exists and the user can simply retry.
  await store.removePhotos(list);

  const { error: delErr } = await db.auth.admin.deleteUser(user.id);
  if (delErr) throw new HttpError(500, "delete_failed", "could not delete the account, please retry", true);

  return json({ deleted: true, photosRemoved: list.length });
}));
