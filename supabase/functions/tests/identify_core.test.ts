import { strict as assert } from "node:assert";
import { type Deps, identify } from "../_shared/identify_core.ts";
import { HttpError } from "../_shared/types.ts";
import { fakeJpeg, FakeStore, FixedEngine } from "./fakes.ts";

const CONFIG: Deps["config"] = {
  confidentThreshold: 0.6,
  dailyLimitPerUser: 10,
  dailyLimitPerIp: 0,
  photoRetentionHours: 24,
  engineTimeoutMs: 200,
};

function deps(store: FakeStore, plant: FixedEngine, vision: FixedEngine, config = CONFIG): Deps {
  let id = 0;
  return { store, plantEngine: plant, visionEngine: vision, config, newId: () => `id-${++id}`, log: () => {} };
}

const visionUnused = new FixedEngine("vision:test", new Error("vision should not be called"));
const req = (over: Partial<Parameters<typeof identify>[0]> = {}) => ({
  userId: "user-1",
  ipHash: null,
  category: "plant" as const,
  image: fakeJpeg(),
  ...over,
});

Deno.test("a confident plant match carries Bangla name, care and pet safety", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0.05625,
    candidates: [
      { name: "Epipremnum aureum", commonNames: ["Golden pothos"], probability: 0.93 },
      { name: "Philodendron hederaceum", commonNames: ["Heartleaf philodendron"], probability: 0.04 },
    ],
  });
  const res = await identify(req(), deps(store, plant, visionUnused));

  assert.equal(res.status, "confident");
  assert.equal(res.matches.length, 2);
  assert.equal(res.matches[0].nameBn, "মানি প্ল্যান্ট");
  assert.equal(res.matches[0].petSafety, "toxic_both");
  assert.equal(res.matches[0].confidenceBand, "high");
  assert.equal(res.matches[0].care?.tips.length, 1);
  assert.equal(res.matches[1].taxonId, null, "an unlisted species is still returned, without our taxon");
  assert.equal(res.matches[1].nameEn, "Heartleaf philodendron");
  assert.deepEqual(res.quota, { used: 1, limit: 10 });
  assert.equal(store.saved[0].costUsd, 0.05625);
  assert.equal(store.saved[0].photoPath, "user-1/ident/id-1.jpg");
  assert.ok(!("rawName" in res.matches[0]), "internal fields are not sent to the app");
});

Deno.test("below 60% the result is low confidence, never presented as certain", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0,
    candidates: [{ name: "Epipremnum aureum", commonNames: [], probability: 0.42 }],
  });
  const res = await identify(req(), deps(store, plant, visionUnused));
  assert.equal(res.status, "low_confidence");
  assert.equal(res.matches[0].confidenceBand, "low");
  assert.equal(store.saved[0].status, "low_confidence");
});

Deno.test("answers that point to the same taxon add up (two rose species make one rose)", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0,
    candidates: [
      { name: "Rosa chinensis", commonNames: ["China rose"], probability: 0.35 },
      { name: "Rosa gallica", commonNames: [], probability: 0.3 },
      { name: "Hibiscus rosa-sinensis", commonNames: [], probability: 0.2 },
    ],
  });
  const res = await identify(req(), deps(store, plant, visionUnused));
  assert.equal(res.status, "confident");
  assert.equal(res.matches[0].nameEn, "Rose");
  assert.equal(res.matches[0].confidence, 0.65);
  assert.equal(res.matches.length, 2);
});

Deno.test("a photo that is not a plant is reported as not recognised", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "other",
    recognised: false,
    candidates: [],
    costUsd: 0.05,
  });
  const res = await identify(req(), deps(store, plant, visionUnused));
  assert.equal(res.status, "not_recognised");
  assert.equal(res.matches.length, 0);
});

Deno.test("the daily limit stops calls before any engine is paid for", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: false,
    candidates: [],
    costUsd: 0,
  });
  const d = deps(store, plant, visionUnused, { ...CONFIG, dailyLimitPerUser: 1 });
  await identify(req(), d);
  await assert.rejects(identify(req(), d), (e: unknown) => e instanceof HttpError && e.status === 429);
  assert.equal(plant.calls.length, 1);
});

Deno.test("detect automatically trusts a confident on-device hint", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0,
    candidates: [{ name: "Epipremnum aureum", commonNames: [], probability: 0.9 }],
  });
  const res = await identify(
    req({ category: "auto", hint: { category: "plant", confidence: 0.85 } }),
    deps(store, plant, visionUnused),
  );
  assert.equal(res.detectedCategory, "plant");
  assert.deepEqual(plant.calls, ["plant"]);
});

Deno.test("detect automatically without a hint routes plants on to the specialist engine", async () => {
  const store = new FakeStore();
  const vision = new FixedEngine("vision:test", {
    engine: "vision:test",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0.002,
    candidates: [{ name: "Epipremnum aureum", commonNames: [], band: "medium" }],
  });
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0.05,
    candidates: [{ name: "Epipremnum aureum", commonNames: [], probability: 0.95 }],
  });
  const res = await identify(req({ category: "auto" }), deps(store, plant, vision));
  assert.equal(res.engine, "vision:test+plantid");
  assert.equal(res.matches[0].confidence, 0.95);
  assert.ok(Math.abs(store.saved[0].costUsd - 0.052) < 1e-9, "both calls are costed");
});

Deno.test("pets use confidence bands and a visible health concern triggers vet advice", async () => {
  const store = new FakeStore();
  const vision = new FixedEngine("vision:test", {
    engine: "vision:test",
    detectedKind: "cat",
    recognised: true,
    costUsd: 0.001,
    healthConcern: true,
    candidates: [{ name: "Mixed breed cat", commonNames: ["Domestic cat"], band: "medium" }],
  });
  const res = await identify(req({ category: "cat" }), deps(store, new FixedEngine("plantid", new Error("unused")), vision));
  assert.equal(res.status, "confident");
  assert.equal(res.matches[0].nameBn, "দেশি বিড়াল");
  assert.equal(res.matches[0].confidenceBand, "medium");
  assert.equal(res.vetAdvice, true);
});

Deno.test("a slow engine times out with a retryable error and the attempt is recorded", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", "hang");
  await assert.rejects(
    identify(req(), deps(store, plant, visionUnused)),
    (e: unknown) => e instanceof HttpError && e.status === 504 && e.retryable,
  );
  assert.equal(store.saved[0].status, "failed");
});

Deno.test("a storage failure does not lose the identification", async () => {
  const store = new FakeStore();
  store.failUpload = true;
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "plant",
    recognised: true,
    costUsd: 0,
    candidates: [{ name: "Epipremnum aureum", commonNames: [], probability: 0.9 }],
  });
  const res = await identify(req(), deps(store, plant, visionUnused));
  assert.equal(res.status, "confident");
  assert.equal(store.saved[0].photoPath, null);
});

Deno.test("with photo retention off nothing is uploaded", async () => {
  const store = new FakeStore();
  const plant = new FixedEngine("plantid", {
    engine: "plantid",
    detectedKind: "other",
    recognised: false,
    candidates: [],
    costUsd: 0,
  });
  await identify(req(), deps(store, plant, visionUnused, { ...CONFIG, photoRetentionHours: 0 }));
  assert.equal(store.uploads.length, 0);
  assert.equal(store.saved[0].photoPath, null);
});
