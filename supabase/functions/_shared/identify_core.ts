import type { Config } from "./config.ts";
import type {
  Band,
  CareCard,
  Engine,
  EngineResult,
  IdentifyResponse,
  IdStatus,
  ImageInput,
  Kind,
  MatchOut,
  RequestedCategory,
  TaxonInfo,
} from "./types.ts";
import { HttpError, KINDS } from "./types.ts";

/** Everything the identification flow needs from the database and storage. */
export interface Store {
  consumeQuota(subject: string, limit: number): Promise<number | null>;
  matchTaxon(kind: Kind, names: string[]): Promise<TaxonInfo | null>;
  careFor(taxonId: number): Promise<CareCard | null>;
  cachedAiCare(kind: Kind, scientificName: string): Promise<CareCard | null>;
  saveIdentification(rec: IdentificationRecord): Promise<void>;
  uploadTempPhoto(path: string, image: ImageInput, expiresAt: Date): Promise<void>;
}

export interface IdentificationRecord {
  id: string;
  userId: string;
  requestedCategory: RequestedCategory;
  detectedCategory: Kind | null;
  status: IdStatus;
  engine: string;
  topConfidence: number | null;
  responseMs: number;
  costUsd: number;
  photoPath: string | null;
  photoExpiresAt: string | null;
  clientHint: unknown;
  matches: Array<{
    rank: number;
    taxonId: number | null;
    rawName: string;
    rawCommonName: string | null;
    confidence: number | null;
    band: Band;
  }>;
}

export interface IdentifyRequest {
  userId: string;
  ipHash: string | null;
  category: RequestedCategory;
  /** Result of the free on-device image labeller, used to route "detect automatically". */
  hint?: { category?: Kind | "other"; confidence?: number; labels?: unknown } | null;
  image: ImageInput;
}

export interface Deps {
  store: Store;
  plantEngine: Engine;
  visionEngine: Engine;
  config: Pick<
    Config,
    "confidentThreshold" | "dailyLimitPerUser" | "dailyLimitPerIp" | "photoRetentionHours" | "engineTimeoutMs"
  >;
  now?: () => number;
  newId?: () => string;
  log?: (msg: string, extra?: unknown) => void;
}

const BAND_SCORE: Record<Band, number> = { high: 0.9, medium: 0.7, low: 0.4 };

export function bandFor(probability: number): Band {
  return probability >= 0.8 ? "high" : probability >= 0.6 ? "medium" : "low";
}

export async function identify(req: IdentifyRequest, deps: Deps): Promise<IdentifyResponse> {
  const now = deps.now ?? Date.now;
  const newId = deps.newId ?? (() => crypto.randomUUID());
  const log = deps.log ?? ((m: string, e?: unknown) => console.error(m, e ?? ""));
  const { store, config } = deps;
  const started = now();

  // 1. Quotas: per user, and optionally per network address.
  const used = await store.consumeQuota(`u:${req.userId}`, config.dailyLimitPerUser);
  if (used === null) {
    throw new HttpError(429, "quota_exceeded", `daily limit of ${config.dailyLimitPerUser} identifications reached`);
  }
  if (config.dailyLimitPerIp > 0 && req.ipHash) {
    if ((await store.consumeQuota(`ip:${req.ipHash}`, config.dailyLimitPerIp)) === null) {
      throw new HttpError(429, "quota_exceeded", "too many identifications from this network today");
    }
  }

  // 2. Route. "Detect automatically" trusts the on-device hint when it is confident.
  let route: Kind | "auto" = req.category;
  const hintKind = req.hint?.category;
  if (route === "auto" && hintKind && hintKind !== "other" && (req.hint?.confidence ?? 0) >= 0.6) {
    route = hintKind;
  }

  // 3. Keep the photo for 24 hours (for "Not right?" reports), uploaded alongside the engine call.
  const id = newId();
  const keepPhoto = config.photoRetentionHours > 0;
  const photoPath = keepPhoto ? `${req.userId}/ident/${id}.jpg` : null;
  const expiresAt = new Date(started + config.photoRetentionHours * 3_600_000);
  const upload = photoPath
    ? store.uploadTempPhoto(photoPath, req.image, expiresAt).then(() => true, (e) => {
      log("temporary photo upload failed", e);
      return false;
    })
    : Promise.resolve(false);

  // 4. Ask the engines.
  const signal = AbortSignal.timeout(config.engineTimeoutMs);
  let result: EngineResult;
  let costUsd = 0;
  let engineName = route === "plant" ? deps.plantEngine.name : deps.visionEngine.name;
  try {
    if (route === "plant") {
      result = await deps.plantEngine.identify(req.image, "plant", signal);
      costUsd += result.costUsd;
    } else {
      result = await deps.visionEngine.identify(req.image, route, signal);
      costUsd += result.costUsd;
      if (route === "auto" && result.detectedKind === "plant" && deps.plantEngine !== deps.visionEngine) {
        // The vision model only routed the photo; the specialist engine names the plant.
        const plant = await deps.plantEngine.identify(req.image, "plant", signal);
        costUsd += plant.costUsd;
        engineName = `${deps.visionEngine.name}+${deps.plantEngine.name}`;
        result = plant;
      }
    }
  } catch (err) {
    const timedOut = err instanceof DOMException && (err.name === "TimeoutError" || err.name === "AbortError");
    await store.saveIdentification({
      id,
      userId: req.userId,
      requestedCategory: req.category,
      detectedCategory: null,
      status: "failed",
      engine: engineName,
      topConfidence: null,
      responseMs: now() - started,
      costUsd,
      photoPath: (await upload) ? photoPath : null,
      photoExpiresAt: (await upload) ? expiresAt.toISOString() : null,
      clientHint: req.hint ?? null,
      matches: [],
    }).catch((e) => log("could not record failed identification", e));
    if (err instanceof HttpError) throw err;
    if (timedOut) throw new HttpError(504, "engine_timeout", "identification took too long", true);
    log("engine error", err);
    throw new HttpError(502, "engine_error", "identification service unavailable", true);
  }

  // 5. Map candidates to our species list (Bangla names, care cards, pet safety).
  const detected: Kind | null = (KINDS as readonly string[]).includes(result.detectedKind ?? "")
    ? result.detectedKind as Kind
    : route === "auto"
    ? null
    : route;

  const matches = detected && result.recognised ? await buildMatches(result, detected, store) : [];
  const top = matches[0]?.confidence ?? null;
  let status: IdStatus;
  if (!result.recognised || matches.length === 0) status = "not_recognised";
  else if (top !== null && top >= config.confidentThreshold) status = "confident";
  else status = "low_confidence";

  const vetAdvice = detected !== null && detected !== "plant" && result.healthConcern === true;
  const uploaded = await upload;
  const responseMs = now() - started;

  await store.saveIdentification({
    id,
    userId: req.userId,
    requestedCategory: req.category,
    detectedCategory: detected,
    status,
    engine: engineName,
    topConfidence: top,
    responseMs,
    costUsd,
    photoPath: uploaded ? photoPath : null,
    photoExpiresAt: uploaded ? expiresAt.toISOString() : null,
    clientHint: req.hint ?? null,
    matches: matches.map((m) => ({
      rank: m.rank,
      taxonId: m.taxonId,
      rawName: m.rawName,
      rawCommonName: m.rawCommonName,
      confidence: m.confidence,
      band: m.confidenceBand,
    })),
  });

  return {
    identificationId: id,
    status,
    requestedCategory: req.category,
    detectedCategory: detected,
    engine: engineName,
    matches: matches.map(({ rawName: _r, rawCommonName: _c, ...m }) => m),
    vetAdvice,
    quota: { used, limit: config.dailyLimitPerUser },
    responseMs,
  };
}

type InternalMatch = MatchOut & { rawName: string; rawCommonName: string | null };

async function buildMatches(result: EngineResult, kind: Kind, store: Store): Promise<InternalMatch[]> {
  const candidates = result.candidates.slice(0, 5);
  const taxa = await Promise.all(
    candidates.map((c) => store.matchTaxon(kind, [c.name, ...c.commonNames])),
  );

  // Several engine answers can point at one of our taxa (e.g. two rose species -> "Rose").
  // They are different answers for the same thing, so their probabilities add up.
  const merged: Array<{ i: number; taxon: TaxonInfo | null; confidence: number; band: Band }> = [];
  candidates.forEach((c, i) => {
    const confidence = c.probability ?? BAND_SCORE[c.band ?? "low"];
    const taxon = taxa[i];
    const existing = taxon ? merged.find((m) => m.taxon?.id === taxon.id) : undefined;
    if (existing) {
      existing.confidence = Math.min(1, existing.confidence + (c.probability ?? 0));
      if (c.probability !== undefined) existing.band = bandFor(existing.confidence);
    } else {
      merged.push({ i, taxon, confidence, band: c.band ?? bandFor(confidence) });
    }
  });
  merged.sort((a, b) => b.confidence - a.confidence);
  const top3 = merged.slice(0, 3);

  const cards = await Promise.all(
    top3.map((m) => m.taxon ? store.careFor(m.taxon.id) : store.cachedAiCare(kind, candidates[m.i].name)),
  );

  return top3.map((m, rank) => {
    const c = candidates[m.i];
    const t = m.taxon;
    const round = Math.round(m.confidence * 1000) / 1000;
    return {
      rank: rank + 1,
      taxonId: t?.id ?? null,
      taxonKey: t?.key ?? null,
      scientificName: t?.scientificName ?? c.name,
      nameEn: t?.nameEn ?? c.commonNames[0] ?? c.name,
      nameBn: t?.nameBn ?? null,
      confidence: round,
      confidenceBand: m.band,
      petSafety: t?.petSafety ?? null,
      care: cards[rank],
      rawName: c.name,
      rawCommonName: c.commonNames[0] ?? null,
    };
  });
}
