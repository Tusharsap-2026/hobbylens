// POST /functions/v1/care-tips
// Body: {"kind": "plant", "scientific_name": "Ficus elastica", "common_name": "Rubber plant"}
// For species outside the curated list. Returns cached AI-written tips, generating them once.
// The app must label these as "AI-generated, not reviewed by an expert".
import { requireUser } from "../_shared/auth.ts";
import { loadConfig } from "../_shared/config.ts";
import { buildVisionEngine } from "../_shared/engines/index.ts";
import { handler, json, readJson } from "../_shared/http.ts";
import { serviceClient, SupabaseStore } from "../_shared/store_supabase.ts";
import { HttpError, type Kind, KINDS } from "../_shared/types.ts";

const config = loadConfig();
const vision = buildVisionEngine(config);
const db = serviceClient();
const store = new SupabaseStore(db);

Deno.serve(handler(async (req) => {
  const user = await requireUser(req, db);
  const body = await readJson(req, 4096);
  const kind = String(body.kind ?? "") as Kind;
  const scientificName = String(body.scientific_name ?? "").trim();
  const commonName = String(body.common_name ?? "").trim().slice(0, 120);
  if (!KINDS.includes(kind)) throw new HttpError(400, "bad_kind", "kind must be plant, cat, dog or bird");
  if (scientificName.length < 3 || scientificName.length > 120 || !/^[\p{L}\p{N} .'×()-]+$/u.test(scientificName)) {
    throw new HttpError(400, "bad_name", "scientific_name is not valid");
  }

  const cached = await store.cachedAiCare(kind, scientificName);
  if (cached) return json({ care: cached, cached: true });

  if ((await store.consumeQuota(`care:${user.id}`, config.careDailyLimitPerUser)) === null) {
    throw new HttpError(429, "quota_exceeded", "daily limit for new care tips reached");
  }
  const { tips } = await vision.careTips(kind, scientificName, commonName, AbortSignal.timeout(config.engineTimeoutMs * 2));
  await store.saveAiCare(kind, scientificName, tips, vision.name);
  return json({ care: { status: "ai_generated", isFallback: false, tips }, cached: false });
}));
