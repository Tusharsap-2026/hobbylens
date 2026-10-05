// Integration test: the gateway's database layer against a real PostgreSQL + PostgREST.
// Run through tools/db/integration.sh, which starts PostgREST on PGRST_PORT and sets
// PGRST_JWT_SECRET. A small proxy adds the /rest/v1 prefix that supabase-js expects.
import { strict as assert } from "node:assert";
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { identify } from "../_shared/identify_core.ts";
import { SupabaseStore } from "../_shared/store_supabase.ts";
import type { EngineResult } from "../_shared/types.ts";
import { fakeJpeg, FixedEngine } from "../tests/fakes.ts";

const pgrstPort = Number(Deno.env.get("PGRST_PORT") ?? "54401");
const secret = Deno.env.get("PGRST_JWT_SECRET") ?? "";

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

// Proxy: /rest/v1/... -> PostgREST /...
const proxy = Deno.serve({ port: 0, onListen: () => {} }, (req) => {
  const u = new URL(req.url);
  const target = `http://127.0.0.1:${pgrstPort}${u.pathname.replace(/^\/rest\/v1/, "")}${u.search}`;
  return fetch(target, { method: req.method, headers: req.headers, body: req.body });
});
const url = `http://127.0.0.1:${proxy.addr.port}`;

const serviceKey = await hs256({ role: "service_role", iss: "test", exp: Math.floor(Date.now() / 1000) + 3600 });
const db = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const store = new SupabaseStore(db);
const USER = "44444444-4444-4444-8444-444444444444";

Deno.test({
  name: "integration: database layer of the gateway",
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async (t) => {
    await t.step("quota counts up and stops at the limit", async () => {
      const subject = `u:it-${crypto.randomUUID()}`;
      assert.equal(await store.consumeQuota(subject, 2), 1);
      assert.equal(await store.consumeQuota(subject, 2), 2);
      assert.equal(await store.consumeQuota(subject, 2), null);
    });

    await t.step("taxon matching returns Bangla names", async () => {
      const t1 = await store.matchTaxon("plant", ["Sansevieria trifasciata", "Snake plant"]);
      assert.equal(t1?.key, "snake_plant");
      assert.equal(t1?.nameBn, "স্নেক প্ল্যান্ট");
      assert.equal(await store.matchTaxon("plant", ["Ficus elastica"]), null);
    });

    await t.step("care cards come back in display order, with the kind fallback", async () => {
      const own = await store.matchTaxon("plant", ["Rosa chinensis"]);
      const card = await store.careFor(own!.id);
      assert.deepEqual(card?.tips.map((x) => x.topic), ["light", "water", "soil", "fertiliser"]);
      const persian = await store.matchTaxon("cat", ["Persian"]);
      const fallback = await store.careFor(persian!.id);
      assert.equal(fallback?.isFallback, true);
    });

    await t.step("AI care is cached by lower-case name", async () => {
      await store.saveAiCare("plant", "Ficus Elastica", [{ topic: "light", en: "Bright light.", bn: "উজ্জ্বল আলো।" }], "test");
      const c = await store.cachedAiCare("plant", "ficus elastica");
      assert.equal(c?.status, "ai_generated");
    });

    await t.step("a full identification is stored with its matches", async () => {
      const plant = new FixedEngine(
        "plantid",
        {
          engine: "plantid",
          detectedKind: "plant",
          recognised: true,
          costUsd: 0.05625,
          candidates: [
            { name: "Epipremnum aureum", commonNames: ["Golden pothos"], probability: 0.88 },
            { name: "Ficus elastica", commonNames: ["Rubber plant"], probability: 0.06 },
          ],
        } satisfies EngineResult,
      );
      const res = await identify(
        { userId: USER, ipHash: null, category: "plant", image: fakeJpeg() },
        {
          store: Object.assign(Object.create(store), { uploadTempPhoto: () => Promise.resolve() }),
          plantEngine: plant,
          visionEngine: plant,
          config: {
            confidentThreshold: 0.6,
            dailyLimitPerUser: 10,
            dailyLimitPerIp: 0,
            photoRetentionHours: 24,
            engineTimeoutMs: 2000,
          },
          log: () => {},
        },
      );
      assert.equal(res.status, "confident");
      assert.equal(res.matches[0].nameBn, "মানি প্ল্যান্ট");
      assert.equal(res.matches[1].care?.status, "ai_generated", "cached AI care is attached to an unlisted species");

      const { data: row } = await db.from("identifications").select("status, cost_usd, photo_path").eq("id", res.identificationId)
        .single();
      assert.equal(row?.status, "confident");
      assert.equal(Number(row?.cost_usd), 0.05625);
      assert.equal(row?.photo_path, `${USER}/ident/${res.identificationId}.jpg`);
      const { data: m } = await db.from("identification_matches").select("rank, raw_name, taxon_id").eq(
        "identification_id",
        res.identificationId,
      ).order("rank");
      assert.equal(m?.length, 2);
      assert.equal(m?.[1].taxon_id, null);
    });

    await proxy.shutdown();
  },
});
