import { strict as assert } from "node:assert";
import { parsePlantIdResponse, PlantIdEngine } from "../_shared/engines/plantid.ts";
import { parsePlantNetResponse, PlantNetEngine } from "../_shared/engines/plantnet.ts";
import { AnthropicBackend, GeminiBackend, parseCareTips, parseVisionIdentify, VisionEngine } from "../_shared/engines/vision.ts";
import { MockEngine } from "../_shared/engines/mock.ts";
import { decodeImage } from "../_shared/image.ts";
import { HttpError } from "../_shared/types.ts";
import { fakeJpeg } from "./fakes.ts";

type Captured = { url: string; init: RequestInit };
function fakeFetch(status: number, body: unknown, captured: Captured[] = []): typeof fetch {
  return ((url: string | URL, init?: RequestInit) => {
    captured.push({ url: String(url), init: init ?? {} });
    const text = typeof body === "string" ? body : JSON.stringify(body);
    return Promise.resolve(new Response(text, { status, headers: { "Content-Type": "application/json" } }));
  }) as typeof fetch;
}
const signal = () => AbortSignal.timeout(1000);

// Plant.id ---------------------------------------------------------------------------
Deno.test("plant.id: suggestions become candidates, best first", () => {
  const r = parsePlantIdResponse({
    result: {
      is_plant: { probability: 0.99, binary: true },
      classification: {
        suggestions: [
          {
            name: "Dracaena trifasciata",
            probability: 0.12,
            details: { common_names: ["Snake plant"], taxonomy: { genus: "Dracaena" } },
          },
          {
            name: "Epipremnum aureum",
            probability: 0.81,
            details: { common_names: ["Golden pothos", "Devil's ivy"], taxonomy: { genus: "Epipremnum" } },
          },
        ],
      },
    },
  }, 0.05);
  assert.equal(r.recognised, true);
  assert.equal(r.candidates[0].name, "Epipremnum aureum");
  assert.deepEqual(r.candidates[0].commonNames, ["Golden pothos", "Devil's ivy"]);
  assert.equal(r.candidates[0].genus, "Epipremnum");
  assert.equal(r.costUsd, 0.05);
});

Deno.test("plant.id: a photo that is not a plant is not recognised", () => {
  const r = parsePlantIdResponse({
    result: { is_plant: { probability: 0.08 }, classification: { suggestions: [{ name: "Rosa", probability: 0.4 }] } },
  }, 0.05);
  assert.equal(r.recognised, false);
  assert.equal(r.detectedKind, "other");
});

Deno.test("plant.id: sends the key in a header and the image as a data URL", async () => {
  const captured: Captured[] = [];
  const engine = new PlantIdEngine({
    apiKey: "k",
    baseUrl: "https://plant.id/api/v3/",
    language: "en",
    usdPerCall: 0.05,
    fetch: fakeFetch(201, { result: { is_plant: { probability: 1 }, classification: { suggestions: [] } } }, captured),
  });
  await engine.identify(fakeJpeg(), "plant", signal());
  assert.ok(captured[0].url.startsWith("https://plant.id/api/v3/identification?"));
  assert.equal((captured[0].init.headers as Record<string, string>)["Api-Key"], "k");
  assert.ok(JSON.parse(String(captured[0].init.body)).images[0].startsWith("data:image/jpeg;base64,"));
});

Deno.test("plant.id: a 429 is a retryable engine error", async () => {
  const engine = new PlantIdEngine({
    apiKey: "k",
    baseUrl: "https://x",
    language: "en",
    usdPerCall: 0,
    fetch: fakeFetch(429, "slow down"),
  });
  await assert.rejects(engine.identify(fakeJpeg(), "plant", signal()), (e: unknown) => e instanceof HttpError && e.retryable);
});

// Pl@ntNet ---------------------------------------------------------------------------
Deno.test("plantnet: results become candidates without author names", () => {
  const r = parsePlantNetResponse({
    results: [
      {
        score: 0.71,
        species: {
          scientificNameWithoutAuthor: "Mangifera indica",
          scientificName: "Mangifera indica L.",
          genus: { scientificNameWithoutAuthor: "Mangifera" },
          commonNames: ["Mango"],
        },
      },
    ],
  }, 0);
  assert.equal(r.candidates[0].name, "Mangifera indica");
  assert.equal(r.candidates[0].probability, 0.71);
});

Deno.test("plantnet: 404 means no species found, not an error", async () => {
  const engine = new PlantNetEngine({
    apiKey: "k",
    project: "all",
    usdPerCall: 0,
    fetch: fakeFetch(404, { message: "Species not found" }),
  });
  const r = await engine.identify(fakeJpeg(), "plant", signal());
  assert.equal(r.recognised, false);
});

// Vision models --------------------------------------------------------------------
Deno.test("vision: parses fenced JSON and keeps at most three candidates", () => {
  const r = parseVisionIdentify(
    "```json\n" + JSON.stringify({
      category: "dog",
      image_usable: true,
      health_concern_visible: false,
      candidates: [
        { name: "Mixed breed dog", common_name_en: "Local dog", confidence: "medium" },
        { name: "German Shepherd", confidence: "low" },
        { name: "Labrador Retriever", confidence: "certain" },
        { name: "Husky", confidence: "low" },
      ],
    }) + "\n```",
  );
  assert.equal(r.detectedKind, "dog");
  assert.equal(r.candidates.length, 3);
  assert.equal(r.candidates[2].band, "low", "an invalid band is treated as low");
});

Deno.test("vision: an unusable photo or 'other' is not recognised", () => {
  assert.equal(
    parseVisionIdentify(JSON.stringify({ category: "cat", image_usable: false, candidates: [{ name: "x", confidence: "high" }] }))
      .recognised,
    false,
  );
  assert.equal(
    parseVisionIdentify(JSON.stringify({ category: "car", candidates: [{ name: "x", confidence: "high" }] })).recognised,
    false,
  );
});

Deno.test("vision: prose instead of JSON is a retryable error", () => {
  assert.throws(() => parseVisionIdentify("I think this is a cat."), (e: unknown) => e instanceof HttpError && e.retryable);
});

Deno.test("gemini: request shape and token-based cost", async () => {
  const captured: Captured[] = [];
  const backend = new GeminiBackend({
    apiKey: "g",
    model: "gemini-2.5-flash",
    fetch: fakeFetch(200, {
      candidates: [{
        content: {
          parts: [{
            text: JSON.stringify({ category: "bird", candidates: [{ name: "Melopsittacus undulatus", confidence: "high" }] }),
          }],
        },
      }],
      usageMetadata: { promptTokenCount: 1800, candidatesTokenCount: 400 },
    }, captured),
  });
  const engine = new VisionEngine(backend, { usdPerMTokIn: 0.3, usdPerMTokOut: 2.5 });
  const r = await engine.identify(fakeJpeg(), "bird", signal());
  assert.equal(r.candidates[0].name, "Melopsittacus undulatus");
  assert.ok(Math.abs(r.costUsd - 0.00154) < 1e-9);
  assert.ok(captured[0].url.endsWith("/models/gemini-2.5-flash:generateContent"));
  const body = JSON.parse(String(captured[0].init.body));
  assert.equal(body.contents[0].parts[0].inline_data.mime_type, "image/jpeg");
  assert.equal(body.generationConfig.responseMimeType, "application/json");
});

Deno.test("anthropic: request shape and parsing", async () => {
  const captured: Captured[] = [];
  const backend = new AnthropicBackend({
    apiKey: "a",
    model: "claude-haiku-4-5",
    fetch: fakeFetch(200, {
      content: [{
        type: "text",
        text: JSON.stringify({ category: "cat", candidates: [{ name: "Persian", confidence: "high" }] }),
      }],
      usage: { input_tokens: 1500, output_tokens: 120 },
    }, captured),
  });
  const r = await new VisionEngine(backend, { usdPerMTokIn: 1, usdPerMTokOut: 5 }).identify(fakeJpeg(), "cat", signal());
  assert.equal(r.candidates[0].name, "Persian");
  const headers = captured[0].init.headers as Record<string, string>;
  assert.equal(headers["x-api-key"], "a");
  assert.equal(headers["anthropic-version"], "2023-06-01");
  const body = JSON.parse(String(captured[0].init.body));
  assert.equal(body.messages[0].content[0].type, "image");
});

Deno.test("care tips: only allowed topics, both languages, no duplicates", () => {
  const tips = parseCareTips(
    JSON.stringify({
      tips: [
        { topic: "light", en: "Bright light.", bn: "উজ্জ্বল আলো।" },
        { topic: "light", en: "Again.", bn: "আবার।" },
        { topic: "dosage", en: "Give 5 mg.", bn: "৫ মিগ্রা দিন।" },
        { topic: "water", en: "Water weekly.", bn: "সপ্তাহে পানি দিন।" },
        { topic: "soil", en: "Loose soil.", bn: "" },
      ],
    }),
    "plant",
  );
  assert.deepEqual(tips.map((t) => t.topic), ["light", "water"]);
});

Deno.test("mock engine covers each result screen", async () => {
  const m = new MockEngine();
  const outcome = async (size: number) => (await m.identify(fakeJpeg(size), "plant", signal()));
  assert.equal((await outcome(4096)).candidates[0].probability, 0.91);
  assert.equal((await outcome(4097)).candidates[0].probability, 0.42);
  assert.equal((await outcome(4099)).recognised, false);
});

// Image input --------------------------------------------------------------------------
Deno.test("image: accepts JPEG base64 and data URLs, rejects other files and oversize input", () => {
  const jpeg = fakeJpeg(2048);
  assert.equal(decodeImage(jpeg.base64, 1_500_000).mimeType, "image/jpeg");
  assert.equal(decodeImage(`data:image/jpeg;base64,${jpeg.base64}`, 1_500_000).bytes.length, 2048);
  const pdf = btoa("%PDF-1.7" + "x".repeat(2000));
  assert.throws(() => decodeImage(pdf, 1_500_000), (e: unknown) => e instanceof HttpError && e.status === 415);
  assert.throws(() => decodeImage(fakeJpeg(5000).base64, 4000), (e: unknown) => e instanceof HttpError && e.status === 413);
  assert.throws(() => decodeImage("", 1000), (e: unknown) => e instanceof HttpError && e.status === 400);
});
