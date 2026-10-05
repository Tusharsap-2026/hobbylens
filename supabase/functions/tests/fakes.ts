import type { IdentificationRecord, Store } from "../_shared/identify_core.ts";
import type { CareCard, Engine, EngineResult, ImageInput, Kind, TaxonInfo } from "../_shared/types.ts";

interface FakeTaxon extends TaxonInfo {
  matchNames: string[];
  genus?: string;
  rank: "species" | "genus" | "breed" | "landrace";
}

export const TAXA: FakeTaxon[] = [
  {
    id: 1,
    key: "money_plant",
    kind: "plant",
    rank: "species",
    scientificName: "Epipremnum aureum",
    nameEn: "Money plant (golden pothos)",
    nameBn: "মানি প্ল্যান্ট",
    petSafety: "toxic_both",
    matchNames: ["epipremnum aureum", "golden pothos"],
  },
  {
    id: 2,
    key: "rose",
    kind: "plant",
    rank: "genus",
    genus: "Rosa",
    scientificName: "Rosa",
    nameEn: "Rose",
    nameBn: "গোলাপ",
    petSafety: "safe",
    matchNames: ["rosa", "rose"],
  },
  {
    id: 3,
    key: "cat_local",
    kind: "cat",
    rank: "landrace",
    scientificName: "Felis catus",
    nameEn: "Domestic cat (local or mixed breed)",
    nameBn: "দেশি বিড়াল",
    petSafety: null,
    matchNames: ["mixed breed cat", "domestic cat"],
  },
];

export class FakeStore implements Store {
  quota = new Map<string, number>();
  saved: IdentificationRecord[] = [];
  uploads: string[] = [];
  failUpload = false;

  consumeQuota(subject: string, limit: number) {
    const n = this.quota.get(subject) ?? 0;
    if (n >= limit) return Promise.resolve(null);
    this.quota.set(subject, n + 1);
    return Promise.resolve(n + 1);
  }

  matchTaxon(kind: Kind, names: string[]) {
    const lower = names.map((n) => n.toLowerCase().trim());
    const exact = TAXA.find((t) => t.kind === kind && lower.some((n) => t.matchNames.includes(n)));
    if (exact) return Promise.resolve(strip(exact));
    const genus = TAXA.find((t) =>
      t.kind === kind && t.rank === "genus" && lower.some((n) => n.split(" ")[0] === t.genus?.toLowerCase())
    );
    return Promise.resolve(genus ? strip(genus) : null);
  }

  careFor(taxonId: number): Promise<CareCard | null> {
    if (taxonId === 1) {
      return Promise.resolve({
        status: "draft",
        isFallback: false,
        tips: [{ topic: "light", en: "Bright, indirect light.", bn: "উজ্জ্বল পরোক্ষ আলো।" }],
      });
    }
    return Promise.resolve(null);
  }

  cachedAiCare(): Promise<CareCard | null> {
    return Promise.resolve(null);
  }

  saveIdentification(rec: IdentificationRecord) {
    this.saved.push(rec);
    return Promise.resolve();
  }

  uploadTempPhoto(path: string) {
    if (this.failUpload) return Promise.reject(new Error("storage down"));
    this.uploads.push(path);
    return Promise.resolve();
  }
}

function strip(t: FakeTaxon): TaxonInfo {
  const { matchNames: _m, genus: _g, rank: _r, ...rest } = t;
  return rest;
}

/** An engine that returns a fixed result, or waits for the abort signal when told to hang. */
export class FixedEngine implements Engine {
  calls: Array<Kind | "auto"> = [];
  constructor(readonly name: string, private readonly result: EngineResult | "hang" | Error) {}
  identify(_image: ImageInput, kind: Kind | "auto", signal: AbortSignal): Promise<EngineResult> {
    this.calls.push(kind);
    if (this.result === "hang") {
      return new Promise((_, reject) => signal.addEventListener("abort", () => reject(signal.reason)));
    }
    if (this.result instanceof Error) return Promise.reject(this.result);
    return Promise.resolve(this.result);
  }
}

/** A minimal valid JPEG-looking buffer of the given size. */
export function fakeJpeg(size = 4096): ImageInput {
  const bytes = new Uint8Array(size);
  bytes.set([0xff, 0xd8, 0xff, 0xe0]);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return { bytes, mimeType: "image/jpeg", base64: btoa(bin) };
}
