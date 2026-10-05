/** All gateway settings come from environment variables (Supabase function secrets). */
export interface Config {
  plantEngine: "plantid" | "plantnet" | "vision" | "mock";
  visionProvider: "gemini" | "anthropic" | "mock";
  confidentThreshold: number;
  dailyLimitPerUser: number;
  dailyLimitPerIp: number;
  ipHashSalt: string;
  photoRetentionHours: number;
  engineTimeoutMs: number;
  maxImageBytes: number;

  plantIdApiKey: string;
  plantIdBaseUrl: string;
  plantIdLanguage: string;
  plantIdEurPerCall: number;
  eurToUsd: number;

  plantNetApiKey: string;
  plantNetProject: string;
  plantNetUsdPerCall: number;

  geminiApiKey: string;
  geminiModel: string;
  anthropicApiKey: string;
  anthropicModel: string;
  visionUsdPerMTokIn: number;
  visionUsdPerMTokOut: number;

  careDailyLimitPerUser: number;
}

type Env = { get(key: string): string | undefined };

function num(env: Env, key: string, fallback: number): number {
  const raw = env.get(key);
  if (raw === undefined || raw.trim() === "") return fallback;
  const n = Number(raw);
  if (!Number.isFinite(n)) throw new Error(`${key} must be a number, got "${raw}"`);
  return n;
}

function oneOf<T extends string>(env: Env, key: string, allowed: readonly T[], fallback: T): T {
  const raw = (env.get(key) ?? "").trim();
  if (raw === "") return fallback;
  if (!(allowed as readonly string[]).includes(raw)) {
    throw new Error(`${key} must be one of ${allowed.join(", ")}, got "${raw}"`);
  }
  return raw as T;
}

export function loadConfig(env: Env = Deno.env): Config {
  return {
    plantEngine: oneOf(env, "PLANT_ENGINE", ["plantid", "plantnet", "vision", "mock"] as const, "plantid"),
    visionProvider: oneOf(env, "VISION_PROVIDER", ["gemini", "anthropic", "mock"] as const, "gemini"),
    confidentThreshold: num(env, "CONFIDENT_THRESHOLD", 0.6),
    // Ten a day allows for retakes after a low-confidence result while capping abuse.
    dailyLimitPerUser: num(env, "DAILY_ID_LIMIT_USER", 10),
    // Bangladeshi mobile networks put many people behind one IP (carrier-grade NAT), so the
    // per-IP limit is off by default. Turn it on with a generous value if abuse appears.
    dailyLimitPerIp: num(env, "DAILY_ID_LIMIT_IP", 0),
    ipHashSalt: env.get("IP_HASH_SALT") ?? "",
    photoRetentionHours: num(env, "PHOTO_RETENTION_HOURS", 24),
    engineTimeoutMs: num(env, "ENGINE_TIMEOUT_MS", 8000),
    maxImageBytes: num(env, "MAX_IMAGE_BYTES", 1_500_000),

    plantIdApiKey: env.get("PLANTID_API_KEY") ?? "",
    // Verify against the Kindwise docs during the bake-off week.
    plantIdBaseUrl: env.get("PLANTID_BASE_URL") ?? "https://plant.id/api/v3",
    plantIdLanguage: env.get("PLANTID_LANGUAGE") ?? "en",
    plantIdEurPerCall: num(env, "PLANTID_EUR_PER_CALL", 0.05),
    eurToUsd: num(env, "EUR_TO_USD", 1.125),

    plantNetApiKey: env.get("PLANTNET_API_KEY") ?? "",
    plantNetProject: env.get("PLANTNET_PROJECT") ?? "all",
    plantNetUsdPerCall: num(env, "PLANTNET_USD_PER_CALL", 0),

    geminiApiKey: env.get("GEMINI_API_KEY") ?? "",
    geminiModel: env.get("GEMINI_MODEL") ?? "gemini-2.5-flash",
    anthropicApiKey: env.get("ANTHROPIC_API_KEY") ?? "",
    anthropicModel: env.get("ANTHROPIC_MODEL") ?? "claude-haiku-4-5",
    visionUsdPerMTokIn: num(env, "VISION_USD_PER_MTOK_IN", 0.3),
    visionUsdPerMTokOut: num(env, "VISION_USD_PER_MTOK_OUT", 2.5),

    careDailyLimitPerUser: num(env, "DAILY_CARE_LIMIT_USER", 20),
  };
}
