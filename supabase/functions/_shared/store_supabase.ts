import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.117.2";
import type { IdentificationRecord, Store } from "./identify_core.ts";
import type { CareCard, CareTip, ImageInput, Kind, TaxonInfo } from "./types.ts";

/** A client with the service role key: bypasses row-level security. Server-side only. */
export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export class SupabaseStore implements Store {
  constructor(private readonly db: SupabaseClient) {}

  async consumeQuota(subject: string, limit: number): Promise<number | null> {
    const { data, error } = await this.db.rpc("consume_quota", { p_subject: subject, p_limit: limit });
    if (error) throw error;
    return data === null || data === undefined ? null : Number(data);
  }

  async matchTaxon(kind: Kind, names: string[]): Promise<TaxonInfo | null> {
    const { data: id, error } = await this.db.rpc("match_taxon", { p_kind: kind, p_names: names });
    if (error) throw error;
    if (id === null || id === undefined) return null;
    const { data, error: e2 } = await this.db
      .from("taxa")
      .select("id, key, kind, scientific_name, name_en, name_bn, pet_safety")
      .eq("id", id)
      .single();
    if (e2) throw e2;
    return {
      id: Number(data.id),
      key: data.key,
      kind: data.kind,
      scientificName: data.scientific_name,
      nameEn: data.name_en,
      nameBn: data.name_bn,
      petSafety: data.pet_safety,
    };
  }

  async careFor(taxonId: number): Promise<CareCard | null> {
    const { data, error } = await this.db.rpc("care_for", { p_taxon_id: taxonId });
    if (error) throw error;
    const rows = (data ?? []) as Array<
      { status: CareCard["status"]; is_fallback: boolean; topic: string; body_en: string; body_bn: string }
    >;
    if (rows.length === 0) return null;
    return {
      status: rows[0].status,
      isFallback: rows[0].is_fallback,
      tips: rows.map((r) => ({ topic: r.topic, en: r.body_en, bn: r.body_bn })),
    };
  }

  async cachedAiCare(kind: Kind, scientificName: string): Promise<CareCard | null> {
    const { data, error } = await this.db
      .from("ai_care_cache")
      .select("tips")
      .eq("kind", kind)
      .eq("scientific_name", scientificName.toLowerCase())
      .maybeSingle();
    if (error) throw error;
    return data ? { status: "ai_generated", isFallback: false, tips: data.tips as CareTip[] } : null;
  }

  async saveAiCare(kind: Kind, scientificName: string, tips: CareTip[], model: string): Promise<void> {
    const { error } = await this.db.from("ai_care_cache").upsert({
      kind,
      scientific_name: scientificName.toLowerCase(),
      tips,
      model,
    });
    if (error) throw error;
  }

  async saveIdentification(rec: IdentificationRecord): Promise<void> {
    const { error } = await this.db.from("identifications").insert({
      id: rec.id,
      user_id: rec.userId,
      requested_category: rec.requestedCategory,
      detected_category: rec.detectedCategory,
      status: rec.status,
      engine: rec.engine,
      top_confidence: rec.topConfidence,
      response_ms: rec.responseMs,
      cost_usd: Number(rec.costUsd.toFixed(6)),
      photo_path: rec.photoPath,
      photo_expires_at: rec.photoExpiresAt,
      client_hint: rec.clientHint,
    });
    if (error) throw error;
    if (rec.matches.length === 0) return;
    const { error: e2 } = await this.db.from("identification_matches").insert(
      rec.matches.map((m) => ({
        identification_id: rec.id,
        rank: m.rank,
        taxon_id: m.taxonId,
        raw_name: m.rawName,
        raw_common_name: m.rawCommonName,
        confidence: m.confidence,
        confidence_band: m.band,
      })),
    );
    if (e2) throw e2;
  }

  async uploadTempPhoto(path: string, image: ImageInput, _expiresAt: Date): Promise<void> {
    const { error } = await this.db.storage.from("photos").upload(path, image.bytes, {
      contentType: image.mimeType,
      upsert: false,
    });
    if (error) throw error;
  }

  async removePhotos(paths: string[]): Promise<void> {
    for (let i = 0; i < paths.length; i += 100) {
      const { error } = await this.db.storage.from("photos").remove(paths.slice(i, i + 100));
      if (error) throw error;
    }
  }
}
