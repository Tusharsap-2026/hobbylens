// POST /functions/v1/identify
// Body: {"image_base64": "...", "category": "plant|cat|dog|bird|auto",
//        "hint": {"category": "plant", "confidence": 0.82, "labels": [...]}}   (hint optional)
// Auth: the app's access token (guest or registered).
import { requireUser } from "../_shared/auth.ts";
import { loadConfig } from "../_shared/config.ts";
import { buildEngines } from "../_shared/engines/index.ts";
import { clientIpHash, handler, json, readJson } from "../_shared/http.ts";
import { identify } from "../_shared/identify_core.ts";
import { decodeImage } from "../_shared/image.ts";
import { serviceClient, SupabaseStore } from "../_shared/store_supabase.ts";
import { HttpError, type Kind, KINDS, type RequestedCategory } from "../_shared/types.ts";

const config = loadConfig();
const engines = buildEngines(config);
const db = serviceClient();
const store = new SupabaseStore(db);

Deno.serve(handler(async (req) => {
  const user = await requireUser(req, db);
  const body = await readJson(req, Math.ceil(config.maxImageBytes * 1.4) + 4096);

  const category = String(body.category ?? "auto") as RequestedCategory;
  if (![...KINDS, "auto"].includes(category)) {
    throw new HttpError(400, "bad_category", "category must be plant, cat, dog, bird or auto");
  }
  const image = decodeImage(body.image_base64, config.maxImageBytes);

  // deno-lint-ignore no-explicit-any
  const rawHint = body.hint as any;
  const hint = rawHint && typeof rawHint === "object"
    ? {
      category: [...KINDS, "other"].includes(rawHint.category) ? rawHint.category as Kind | "other" : undefined,
      confidence: Number.isFinite(Number(rawHint.confidence)) ? Number(rawHint.confidence) : undefined,
      labels: Array.isArray(rawHint.labels) ? rawHint.labels.slice(0, 10) : undefined,
    }
    : null;

  const result = await identify({
    userId: user.id,
    ipHash: await clientIpHash(req, config.ipHashSalt),
    category,
    hint,
    image,
  }, { store, ...engines, config });

  return json(result);
}));
