// Writes contract fixtures for the Flutter app's tests from the REAL gateway code and database:
// the app's parsers are then tested against exactly what the server sends.
// Run via: MAKE_FIXTURES=1 tools/db/integration.sh
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { identify } from "../_shared/identify_core.ts";
import { SupabaseStore } from "../_shared/store_supabase.ts";
import type { EngineResult } from "../_shared/types.ts";
import { fakeJpeg, FixedEngine } from "../tests/fakes.ts";

const pgrstPort = Number(Deno.env.get("PGRST_PORT") ?? "54401");
const secret = Deno.env.get("PGRST_JWT_SECRET") ?? "";
const outDir = Deno.env.get("FIXTURE_DIR") ?? "../../app/test/fixtures";

async function hs256(payload: Record<string, unknown>): Promise<string> {
  const enc = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const head = `${enc({ alg: "HS256", typ: "JWT" })}.${enc(payload)}`;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(head)));
  let bin = "";
  for (const b of sig) bin += String.fromCharCode(b);
  return `${head}.${btoa(bin).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")}`;
}

const proxy = Deno.serve({ port: 0, onListen: () => {} }, (req) => {
  const u = new URL(req.url);
  return fetch(`http://127.0.0.1:${pgrstPort}${u.pathname.replace(/^\/rest\/v1/, "")}${u.search}`, {
    method: req.method,
    headers: req.headers,
    body: req.body,
  });
});
const url = `http://127.0.0.1:${proxy.addr.port}`;
const db = createClient(url, await hs256({ role: "service_role", exp: Math.floor(Date.now() / 1000) + 3600 }), {
  auth: { persistSession: false },
});
const store = Object.assign(Object.create(new SupabaseStore(db)), { uploadTempPhoto: () => Promise.resolve() });
const USER = "44444444-4444-4444-8444-444444444444";
const config = {
  confidentThreshold: 0.6,
  dailyLimitPerUser: 10,
  dailyLimitPerIp: 0,
  photoRetentionHours: 24,
  engineTimeoutMs: 2000,
};
let n = 0;
const newId = () => `00000000-0000-4000-a000-00000000000${++n}`;

async function run(name: string, category: "plant" | "cat" | "auto", result: EngineResult) {
  const engine = new FixedEngine(result.engine, result);
  const res = await identify(
    { userId: USER, ipHash: null, category, image: fakeJpeg() },
    { store, plantEngine: engine, visionEngine: engine, config, newId, log: () => {}, now: () => 1_000 },
  );
  await Deno.writeTextFile(`${outDir}/${name}.json`, JSON.stringify(res, null, 2) + "\n");
}

await Deno.mkdir(outDir, { recursive: true });
await run("identify_confident_plant", "plant", {
  engine: "plantid",
  detectedKind: "plant",
  recognised: true,
  costUsd: 0.05625,
  candidates: [
    { name: "Epipremnum aureum", commonNames: ["Golden pothos"], probability: 0.91 },
    { name: "Philodendron hederaceum", commonNames: ["Heartleaf philodendron"], probability: 0.05 },
    { name: "Dracaena trifasciata", commonNames: ["Snake plant"], probability: 0.02 },
  ],
});
await run("identify_low_confidence", "plant", {
  engine: "plantid",
  detectedKind: "plant",
  recognised: true,
  costUsd: 0.05625,
  candidates: [
    { name: "Aglaonema commutatum", commonNames: ["Chinese evergreen"], probability: 0.42 },
    { name: "Dieffenbachia seguine", commonNames: ["Dumb cane"], probability: 0.31 },
  ],
});
await run("identify_cat_vet", "cat", {
  engine: "vision:gemini",
  detectedKind: "cat",
  recognised: true,
  costUsd: 0.0015,
  healthConcern: true,
  candidates: [
    { name: "Persian", commonNames: ["Persian cat"], band: "high" },
    { name: "Mixed breed cat", commonNames: ["Domestic cat"], band: "low" },
  ],
});
await run("identify_not_recognised", "auto", {
  engine: "vision:gemini",
  detectedKind: "other",
  recognised: false,
  costUsd: 0.0015,
  candidates: [],
});

// Shop search and accessories exactly as PostgREST returns them to the app.
const { data: shops, error: e1 } = await db.rpc("nearby_shops", {
  p_lat: 22.3596,
  p_lng: 91.8215,
  p_radius_km: 3,
  p_kind: "plant",
  p_taxon_id: (await db.from("taxa").select("id").eq("key", "money_plant").single()).data!.id,
});
if (e1) throw e1;
await Deno.writeTextFile(`${outDir}/nearby_shops.json`, JSON.stringify(shops, null, 2) + "\n");

const { data: acc, error: e2 } = await db.rpc("accessories_for", {
  p_taxon_id: (await db.from("taxa").select("id").eq("key", "snake_plant").single()).data!.id,
});
if (e2) throw e2;
await Deno.writeTextFile(`${outDir}/accessories.json`, JSON.stringify(acc, null, 2) + "\n");

const { data: care, error: e3 } = await db.rpc("care_for", {
  p_taxon_id: (await db.from("taxa").select("id").eq("key", "cat_persian").single()).data!.id,
});
if (e3) throw e3;
await Deno.writeTextFile(`${outDir}/care_for.json`, JSON.stringify(care, null, 2) + "\n");

await proxy.shutdown();
console.log("fixtures written to", outDir);
