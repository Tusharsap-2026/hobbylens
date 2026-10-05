import type { SupabaseClient } from "npm:@supabase/supabase-js@2.117.2";
import { bearer } from "./http.ts";
import { HttpError } from "./types.ts";

export interface Caller {
  id: string;
  isAnonymous: boolean;
}

/** Resolves the signed-in user (guest or registered) from the request's access token. */
export async function requireUser(req: Request, db: SupabaseClient): Promise<Caller> {
  const token = bearer(req);
  const { data, error } = await db.auth.getUser(token);
  if (error || !data?.user) throw new HttpError(401, "unauthorised", "sign-in required");
  return { id: data.user.id, isAnonymous: data.user.is_anonymous === true };
}

/** Constant-time comparison for shared secrets such as the cleanup job's token. */
export function safeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  let diff = ea.length ^ eb.length;
  for (let i = 0; i < Math.max(ea.length, eb.length); i++) diff |= (ea[i] ?? 0) ^ (eb[i] ?? 0);
  return diff === 0;
}
