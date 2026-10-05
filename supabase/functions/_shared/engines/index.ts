import type { Config } from "../config.ts";
import type { Engine } from "../types.ts";
import { MockEngine, MockVisionBackend } from "./mock.ts";
import { PlantIdEngine } from "./plantid.ts";
import { PlantNetEngine } from "./plantnet.ts";
import { AnthropicBackend, GeminiBackend, VisionEngine } from "./vision.ts";

const MOCK_CARE_REPLY = JSON.stringify({
  tips: [
    { topic: "light", en: "Demo tip: bright, indirect light.", bn: "ডেমো পরামর্শ: উজ্জ্বল, পরোক্ষ আলো।" },
    { topic: "water", en: "Demo tip: water when the topsoil is dry.", bn: "ডেমো পরামর্শ: ওপরের মাটি শুকালে পানি দিন।" },
    { topic: "food", en: "Demo tip: feed a complete diet.", bn: "ডেমো পরামর্শ: পূর্ণাঙ্গ খাবার দিন।" },
    { topic: "space", en: "Demo tip: give enough space.", bn: "ডেমো পরামর্শ: যথেষ্ট জায়গা দিন।" },
  ],
});

export function buildVisionEngine(cfg: Config): VisionEngine {
  const pricing = { usdPerMTokIn: cfg.visionUsdPerMTokIn, usdPerMTokOut: cfg.visionUsdPerMTokOut };
  switch (cfg.visionProvider) {
    case "gemini":
      return new VisionEngine(new GeminiBackend({ apiKey: cfg.geminiApiKey, model: cfg.geminiModel }), pricing);
    case "anthropic":
      return new VisionEngine(new AnthropicBackend({ apiKey: cfg.anthropicApiKey, model: cfg.anthropicModel }), pricing);
    case "mock":
      return new VisionEngine(new MockVisionBackend(MOCK_CARE_REPLY), { usdPerMTokIn: 0, usdPerMTokOut: 0 });
  }
}

/** The engines used by /identify: one for plants, one for animals and routing. */
export function buildEngines(cfg: Config): { plantEngine: Engine; visionEngine: Engine } {
  const vision: Engine = cfg.visionProvider === "mock" ? new MockEngine() : buildVisionEngine(cfg);
  let plant: Engine;
  switch (cfg.plantEngine) {
    case "plantid":
      plant = new PlantIdEngine({
        apiKey: cfg.plantIdApiKey,
        baseUrl: cfg.plantIdBaseUrl,
        language: cfg.plantIdLanguage,
        usdPerCall: cfg.plantIdEurPerCall * cfg.eurToUsd,
      });
      break;
    case "plantnet":
      plant = new PlantNetEngine({
        apiKey: cfg.plantNetApiKey,
        project: cfg.plantNetProject,
        usdPerCall: cfg.plantNetUsdPerCall,
      });
      break;
    case "vision":
      plant = vision;
      break;
    case "mock":
      plant = new MockEngine();
      break;
  }
  return { plantEngine: plant, visionEngine: vision };
}
