import type { Candidate, Engine, EngineResult, ImageInput, Kind } from "../types.ts";
import { HttpError } from "../types.ts";

/** Pl@ntNet identify API v2 (https://my-api.plantnet.org). */
export class PlantNetEngine implements Engine {
  readonly name = "plantnet";

  constructor(
    private readonly opts: {
      apiKey: string;
      project: string;
      usdPerCall: number;
      fetch?: typeof fetch;
    },
  ) {}

  async identify(image: ImageInput, _kind: Kind | "auto", signal: AbortSignal): Promise<EngineResult> {
    if (!this.opts.apiKey) throw new HttpError(500, "engine_not_configured", "PLANTNET_API_KEY is not set");
    const url = new URL(`https://my-api.plantnet.org/v2/identify/${encodeURIComponent(this.opts.project)}`);
    url.searchParams.set("api-key", this.opts.apiKey);
    url.searchParams.set("lang", "en");
    url.searchParams.set("nb-results", "3");
    url.searchParams.set("include-related-images", "false");

    const form = new FormData();
    form.append("images", new Blob([image.bytes as BlobPart], { type: image.mimeType }), "photo.jpg");
    form.append("organs", "auto");

    const res = await (this.opts.fetch ?? fetch)(url, { method: "POST", body: form, signal });
    if (res.status === 404) {
      // Pl@ntNet answers 404 "Species not found" when nothing matches.
      await res.body?.cancel();
      return { engine: this.name, detectedKind: "other", recognised: false, candidates: [], costUsd: this.opts.usdPerCall };
    }
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new HttpError(
        502,
        "engine_error",
        `plantnet ${res.status}: ${text.slice(0, 200)}`,
        res.status >= 500 || res.status === 429,
      );
    }
    return parsePlantNetResponse(await res.json(), this.opts.usdPerCall);
  }
}

// deno-lint-ignore no-explicit-any
export function parsePlantNetResponse(body: any, costUsd: number): EngineResult {
  const results: unknown[] = Array.isArray(body?.results) ? body.results : [];
  const candidates: Candidate[] = results
    // deno-lint-ignore no-explicit-any
    .map((r: any): Candidate => ({
      name: String(r?.species?.scientificNameWithoutAuthor ?? r?.species?.scientificName ?? "").trim(),
      commonNames: Array.isArray(r?.species?.commonNames) ? r.species.commonNames.map(String) : [],
      genus: r?.species?.genus?.scientificNameWithoutAuthor ? String(r.species.genus.scientificNameWithoutAuthor) : undefined,
      probability: Math.min(1, Math.max(0, Number(r?.score ?? 0) || 0)),
    }))
    .filter((c) => c.name !== "")
    .sort((a, b) => (b.probability ?? 0) - (a.probability ?? 0));

  return {
    engine: "plantnet",
    detectedKind: candidates.length > 0 ? "plant" : "other",
    recognised: candidates.length > 0,
    candidates,
    costUsd,
  };
}
