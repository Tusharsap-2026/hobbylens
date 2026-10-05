import type { Candidate, Engine, EngineResult, ImageInput, Kind } from "../types.ts";
import { HttpError } from "../types.ts";

/**
 * Kindwise Plant.id v3 identification.
 * Request and response shapes follow the public Plant.id v3 examples; confirm field names
 * against the Kindwise handbook during the bake-off week.
 */
export class PlantIdEngine implements Engine {
  readonly name = "plantid";

  constructor(
    private readonly opts: {
      apiKey: string;
      baseUrl: string;
      language: string;
      usdPerCall: number;
      fetch?: typeof fetch;
    },
  ) {}

  async identify(image: ImageInput, _kind: Kind | "auto", signal: AbortSignal): Promise<EngineResult> {
    if (!this.opts.apiKey) throw new HttpError(500, "engine_not_configured", "PLANTID_API_KEY is not set");
    const url = new URL(`${this.opts.baseUrl.replace(/\/$/, "")}/identification`);
    url.searchParams.set("details", "common_names,taxonomy");
    url.searchParams.set("language", this.opts.language);

    const res = await (this.opts.fetch ?? fetch)(url, {
      method: "POST",
      signal,
      headers: { "Api-Key": this.opts.apiKey, "Content-Type": "application/json" },
      body: JSON.stringify({
        images: [`data:${image.mimeType};base64,${image.base64}`],
        similar_images: false,
      }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new HttpError(
        502,
        "engine_error",
        `plant.id ${res.status}: ${text.slice(0, 200)}`,
        res.status >= 500 || res.status === 429,
      );
    }
    return parsePlantIdResponse(await res.json(), this.opts.usdPerCall);
  }
}

// deno-lint-ignore no-explicit-any
export function parsePlantIdResponse(body: any, costUsd: number): EngineResult {
  const result = body?.result ?? {};
  const isPlantProbability = Number(result?.is_plant?.probability ?? 1);
  const suggestions: unknown[] = Array.isArray(result?.classification?.suggestions) ? result.classification.suggestions : [];

  const candidates: Candidate[] = suggestions
    // deno-lint-ignore no-explicit-any
    .map((s: any): Candidate => ({
      name: String(s?.name ?? "").trim(),
      commonNames: Array.isArray(s?.details?.common_names)
        ? s.details.common_names.map((n: unknown) => String(n)).filter(Boolean)
        : [],
      genus: s?.details?.taxonomy?.genus ? String(s.details.taxonomy.genus) : undefined,
      probability: clamp01(Number(s?.probability ?? 0)),
    }))
    .filter((c) => c.name !== "")
    .sort((a, b) => (b.probability ?? 0) - (a.probability ?? 0));

  return {
    engine: "plantid",
    detectedKind: isPlantProbability >= 0.5 ? "plant" : "other",
    recognised: isPlantProbability >= 0.5 && candidates.length > 0,
    candidates,
    costUsd,
  };
}

function clamp01(n: number): number {
  if (!Number.isFinite(n)) return 0;
  return Math.min(1, Math.max(0, n));
}
