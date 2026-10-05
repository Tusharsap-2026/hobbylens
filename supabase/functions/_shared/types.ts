export type Kind = "plant" | "cat" | "dog" | "bird";
export type RequestedCategory = Kind | "auto";
export type Band = "high" | "medium" | "low";
export type IdStatus = "confident" | "low_confidence" | "not_recognised" | "failed";

export const KINDS: readonly Kind[] = ["plant", "cat", "dog", "bird"];

/** One possible answer from an identification engine, before we map it to our taxa. */
export interface Candidate {
  /** Scientific name (plants, bird species) or breed name (cats, dogs). */
  name: string;
  /** English common names the engine gave, best first. */
  commonNames: string[];
  genus?: string;
  /** Calibrated probability 0..1 when the engine provides one (specialist plant engines). */
  probability?: number;
  /** Coarse confidence when the engine cannot give a calibrated probability (vision models). */
  band?: Band;
}

export interface EngineResult {
  engine: string;
  /** What the photo shows, when the engine can tell. */
  detectedKind?: Kind | "other";
  /** False when the photo is unusable or clearly not a plant / pet. */
  recognised: boolean;
  candidates: Candidate[];
  /** The model saw something that may be a health problem (pets only). Never a diagnosis. */
  healthConcern?: boolean;
  costUsd: number;
}

export interface ImageInput {
  bytes: Uint8Array;
  mimeType: "image/jpeg" | "image/png" | "image/webp";
  base64: string;
}

export interface Engine {
  readonly name: string;
  identify(image: ImageInput, kind: Kind | "auto", signal: AbortSignal): Promise<EngineResult>;
}

export interface CareTip {
  topic: string;
  en: string;
  bn: string;
}

export interface CareCard {
  status: "draft" | "reviewed" | "ai_generated";
  isFallback: boolean;
  tips: CareTip[];
}

export interface TaxonInfo {
  id: number;
  key: string;
  kind: Kind;
  scientificName: string;
  nameEn: string;
  nameBn: string;
  petSafety: string | null;
}

export interface MatchOut {
  rank: number;
  taxonId: number | null;
  taxonKey: string | null;
  scientificName: string;
  nameEn: string;
  nameBn: string | null;
  confidence: number | null;
  confidenceBand: Band;
  petSafety: string | null;
  care: CareCard | null;
}

export interface IdentifyResponse {
  identificationId: string;
  status: IdStatus;
  requestedCategory: RequestedCategory;
  detectedCategory: Kind | null;
  engine: string;
  matches: MatchOut[];
  vetAdvice: boolean;
  quota: { used: number; limit: number };
  responseMs: number;
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly retryable = false,
  ) {
    super(message);
  }
}
