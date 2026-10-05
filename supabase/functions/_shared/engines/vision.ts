import type { Band, Candidate, CareTip, Engine, EngineResult, ImageInput, Kind } from "../types.ts";
import { HttpError } from "../types.ts";

/**
 * A general vision model used for cats, dogs and birds, for "detect automatically", and for
 * writing care tips for species outside the curated list. Two interchangeable backends.
 */
export interface VisionBackend {
  readonly name: string;
  /** Sends one prompt (optionally with an image) and returns the model's text and token use. */
  complete(
    prompt: { system: string; user: string; image?: ImageInput; maxTokens: number },
    signal: AbortSignal,
  ): Promise<{ text: string; inputTokens: number; outputTokens: number }>;
}

export const IDENTIFY_SYSTEM = `You identify plants and pets from one photo for a hobbyist app in Bangladesh.
Rules:
- Reply with JSON only, no prose, matching the schema you are given.
- Never diagnose illness. If the animal or plant looks unwell, set "health_concern_visible" to true and say nothing else about it.
- For cats and dogs, give the likely breed. Most cats and dogs in Bangladesh are local or mixed breed: say "Mixed breed cat" or "Mixed breed dog" when no recognised breed fits well.
- For birds and plants, give the scientific name.
- Give at most 3 candidates, best first, and an honest confidence band for each: "high" only when you are sure.
- If the photo is blurred, too dark, or shows no plant, cat, dog or bird, set "image_usable" to false or "category" to "other".`;

export function identifyPrompt(kind: Kind | "auto"): string {
  const focus = kind === "auto"
    ? "First decide whether the photo shows a plant, a cat, a dog, a bird, or something else."
    : `The user says the photo shows a ${kind}. If it clearly does not, set "category" to what it does show.`;
  return `${focus}
Return JSON exactly in this shape:
{"category":"plant|cat|dog|bird|other","image_usable":true,"health_concern_visible":false,
 "candidates":[{"name":"scientific name or breed","common_name_en":"English common name","confidence":"high|medium|low"}]}`;
}

export class VisionEngine implements Engine {
  readonly name: string;

  constructor(
    private readonly backend: VisionBackend,
    private readonly pricing: { usdPerMTokIn: number; usdPerMTokOut: number },
  ) {
    this.name = `vision:${backend.name}`;
  }

  async identify(image: ImageInput, kind: Kind | "auto", signal: AbortSignal): Promise<EngineResult> {
    const out = await this.backend.complete(
      { system: IDENTIFY_SYSTEM, user: identifyPrompt(kind), image, maxTokens: 400 },
      signal,
    );
    const costUsd = this.cost(out.inputTokens, out.outputTokens);
    return { ...parseVisionIdentify(out.text), engine: this.name, costUsd };
  }

  /** Writes 3 to 5 short care tips in English and Bangla for a species we have no card for. */
  async careTips(kind: Kind, scientificName: string, commonName: string, signal: AbortSignal) {
    const out = await this.backend.complete({
      system: CARE_SYSTEM,
      user: carePrompt(kind, scientificName, commonName),
      maxTokens: 700,
    }, signal);
    return { tips: parseCareTips(out.text, kind), costUsd: this.cost(out.inputTokens, out.outputTokens) };
  }

  private cost(inTok: number, outTok: number): number {
    return (inTok * this.pricing.usdPerMTokIn + outTok * this.pricing.usdPerMTokOut) / 1_000_000;
  }
}

/** Pulls the first JSON object out of a model reply, tolerating code fences. */
export function extractJson(text: string): unknown {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const raw = fenced ? fenced[1] : text;
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end <= start) throw new HttpError(502, "engine_bad_output", "model did not return JSON", true);
  try {
    return JSON.parse(raw.slice(start, end + 1));
  } catch {
    throw new HttpError(502, "engine_bad_output", "model returned malformed JSON", true);
  }
}

const BANDS: readonly Band[] = ["high", "medium", "low"];
const CATEGORIES = ["plant", "cat", "dog", "bird", "other"] as const;

export function parseVisionIdentify(text: string): Omit<EngineResult, "engine" | "costUsd"> {
  // deno-lint-ignore no-explicit-any
  const j = extractJson(text) as any;
  const category = (CATEGORIES as readonly string[]).includes(j?.category) ? j.category : "other";
  const usable = j?.image_usable !== false;
  const candidates: Candidate[] = (Array.isArray(j?.candidates) ? j.candidates : [])
    // deno-lint-ignore no-explicit-any
    .map((c: any): Candidate => ({
      name: String(c?.name ?? "").trim().slice(0, 120),
      commonNames: c?.common_name_en ? [String(c.common_name_en).trim().slice(0, 120)] : [],
      band: BANDS.includes(c?.confidence) ? c.confidence : "low",
    }))
    .filter((c: Candidate) => c.name !== "")
    .slice(0, 3);
  return {
    detectedKind: category,
    recognised: usable && category !== "other" && candidates.length > 0,
    candidates,
    healthConcern: j?.health_concern_visible === true,
  };
}

export const CARE_SYSTEM = `You write short, general care guidance for a hobbyist app in Bangladesh.
Reply with JSON only. Each tip is one or two plain sentences, at most 200 characters, in English ("en") and natural Bangla ("bn").
Give practical home-care basics suited to Bangladesh's warm, humid climate. Never give medical, veterinary or dosage advice.`;

const PLANT_TOPICS = ["light", "water", "soil", "temperature", "fertiliser"];
const ANIMAL_TOPICS = ["food", "space", "grooming", "exercise"];

export function carePrompt(kind: Kind, scientificName: string, commonName: string): string {
  const topics = kind === "plant" ? PLANT_TOPICS : ANIMAL_TOPICS;
  return `Write 3 to 5 care basics for: ${commonName || scientificName} (${scientificName}), a ${kind}.
Use only these topics: ${topics.join(", ")}.
Return JSON: {"tips":[{"topic":"${topics[0]}","en":"...","bn":"..."}]}`;
}

export function parseCareTips(text: string, kind: Kind): CareTip[] {
  // deno-lint-ignore no-explicit-any
  const j = extractJson(text) as any;
  const allowed = kind === "plant" ? PLANT_TOPICS : ANIMAL_TOPICS;
  const seen = new Set<string>();
  const tips: CareTip[] = [];
  for (const t of Array.isArray(j?.tips) ? j.tips : []) {
    const topic = String(t?.topic ?? "");
    const en = String(t?.en ?? "").trim();
    const bn = String(t?.bn ?? "").trim();
    if (!allowed.includes(topic) || seen.has(topic) || en.length < 3 || bn.length < 3) continue;
    seen.add(topic);
    tips.push({ topic, en: en.slice(0, 300), bn: bn.slice(0, 300) });
  }
  if (tips.length < 2) throw new HttpError(502, "engine_bad_output", "model returned too few care tips", true);
  return tips.slice(0, 5);
}

// ---------------------------------------------------------------------------
// Backends
// ---------------------------------------------------------------------------

export class GeminiBackend implements VisionBackend {
  readonly name = "gemini";
  constructor(private readonly opts: { apiKey: string; model: string; fetch?: typeof fetch }) {}

  async complete(
    p: { system: string; user: string; image?: ImageInput; maxTokens: number },
    signal: AbortSignal,
  ) {
    if (!this.opts.apiKey) throw new HttpError(500, "engine_not_configured", "GEMINI_API_KEY is not set");
    const parts: unknown[] = [];
    if (p.image) parts.push({ inline_data: { mime_type: p.image.mimeType, data: p.image.base64 } });
    parts.push({ text: p.user });
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(this.opts.model)}:generateContent`;
    const res = await (this.opts.fetch ?? fetch)(url, {
      method: "POST",
      signal,
      headers: { "x-goog-api-key": this.opts.apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: p.system }] },
        contents: [{ role: "user", parts }],
        generationConfig: { responseMimeType: "application/json", temperature: 0, maxOutputTokens: p.maxTokens },
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new HttpError(
        502,
        "engine_error",
        `gemini ${res.status}: ${text.slice(0, 200)}`,
        res.status >= 500 || res.status === 429,
      );
    }
    // deno-lint-ignore no-explicit-any
    const body: any = await res.json();
    const text = (body?.candidates?.[0]?.content?.parts ?? [])
      // deno-lint-ignore no-explicit-any
      .map((x: any) => x?.text ?? "")
      .join("");
    return {
      text,
      inputTokens: Number(body?.usageMetadata?.promptTokenCount ?? 0),
      outputTokens: Number(body?.usageMetadata?.candidatesTokenCount ?? 0),
    };
  }
}

export class AnthropicBackend implements VisionBackend {
  readonly name = "anthropic";
  constructor(private readonly opts: { apiKey: string; model: string; fetch?: typeof fetch }) {}

  async complete(
    p: { system: string; user: string; image?: ImageInput; maxTokens: number },
    signal: AbortSignal,
  ) {
    if (!this.opts.apiKey) throw new HttpError(500, "engine_not_configured", "ANTHROPIC_API_KEY is not set");
    const content: unknown[] = [];
    if (p.image) {
      content.push({ type: "image", source: { type: "base64", media_type: p.image.mimeType, data: p.image.base64 } });
    }
    content.push({ type: "text", text: p.user });
    const res = await (this.opts.fetch ?? fetch)("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal,
      headers: {
        "x-api-key": this.opts.apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: this.opts.model,
        max_tokens: p.maxTokens,
        system: p.system,
        messages: [{ role: "user", content }],
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new HttpError(
        502,
        "engine_error",
        `anthropic ${res.status}: ${text.slice(0, 200)}`,
        res.status >= 500 || res.status === 429,
      );
    }
    // deno-lint-ignore no-explicit-any
    const body: any = await res.json();
    const text = (Array.isArray(body?.content) ? body.content : [])
      // deno-lint-ignore no-explicit-any
      .filter((b: any) => b?.type === "text")
      // deno-lint-ignore no-explicit-any
      .map((b: any) => b.text)
      .join("");
    return {
      text,
      inputTokens: Number(body?.usage?.input_tokens ?? 0),
      outputTokens: Number(body?.usage?.output_tokens ?? 0),
    };
  }
}
