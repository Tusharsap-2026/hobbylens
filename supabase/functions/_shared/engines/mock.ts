import type { Engine, EngineResult, ImageInput, Kind } from "../types.ts";
import type { VisionBackend } from "./vision.ts";

/**
 * Deterministic stand-in for local development and tests: no network, no cost.
 * The answer depends on the image size so the app can exercise every screen:
 *   size % 4 == 0 -> confident match, 1 -> low confidence, 2 -> second-best match, 3 -> not recognised.
 */
export class MockEngine implements Engine {
  readonly name = "mock";

  identify(image: ImageInput, kind: Kind | "auto", _signal: AbortSignal): Promise<EngineResult> {
    const k: Kind = kind === "auto" ? "plant" : kind;
    const mode = image.bytes.length % 4;
    if (mode === 3) {
      return Promise.resolve({ engine: this.name, detectedKind: "other", recognised: false, candidates: [], costUsd: 0 });
    }
    const options: Record<Kind, Array<[string, string]>> = {
      plant: [["Epipremnum aureum", "Golden pothos"], ["Philodendron hederaceum", "Heartleaf philodendron"], [
        "Dracaena trifasciata",
        "Snake plant",
      ]],
      cat: [["Mixed breed cat", "Domestic cat"], ["Persian", "Persian cat"], ["Siamese", "Siamese cat"]],
      dog: [["Mixed breed dog", "Domestic dog"], ["German Shepherd", "German Shepherd"], ["Labrador Retriever", "Labrador"]],
      bird: [["Melopsittacus undulatus", "Budgerigar"], ["Nymphicus hollandicus", "Cockatiel"], [
        "Agapornis roseicollis",
        "Lovebird",
      ]],
    };
    const probs = mode === 0 ? [0.91, 0.05, 0.02] : mode === 1 ? [0.42, 0.31, 0.12] : [0.7, 0.2, 0.05];
    const list = mode === 2 ? [options[k][1], options[k][0], options[k][2]] : options[k];
    return Promise.resolve({
      engine: this.name,
      detectedKind: k,
      recognised: true,
      candidates: list.map(([name, common], i) =>
        k === "plant"
          ? { name, commonNames: [common], probability: probs[i] }
          : { name, commonNames: [common], band: probs[i] >= 0.8 ? "high" : probs[i] >= 0.6 ? "medium" : "low" }
      ),
      costUsd: 0,
    });
  }
}

export class MockVisionBackend implements VisionBackend {
  readonly name = "mock";
  constructor(private readonly reply: string) {}
  complete() {
    return Promise.resolve({ text: this.reply, inputTokens: 1000, outputTokens: 200 });
  }
}
