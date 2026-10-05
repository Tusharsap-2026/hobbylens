import { HttpError } from "./types.ts";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json; charset=utf-8" },
  });
}

export function errorResponse(err: unknown): Response {
  if (err instanceof HttpError) {
    return json({ error: { code: err.code, message: err.message, retryable: err.retryable } }, err.status);
  }
  console.error("unhandled error", err);
  return json({ error: { code: "internal", message: "internal error", retryable: true } }, 500);
}

/** Wraps a handler with CORS preflight, method check and uniform error responses. */
export function handler(fn: (req: Request) => Promise<Response>): (req: Request) => Promise<Response> {
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
    if (req.method !== "POST") return json({ error: { code: "method", message: "use POST" } }, 405);
    try {
      return await fn(req);
    } catch (err) {
      return errorResponse(err);
    }
  };
}

export async function readJson(req: Request, maxBytes: number): Promise<Record<string, unknown>> {
  const len = Number(req.headers.get("content-length") ?? 0);
  if (len > maxBytes) throw new HttpError(413, "body_too_large", "request body is too large");
  const text = await req.text();
  if (text.length > maxBytes) throw new HttpError(413, "body_too_large", "request body is too large");
  try {
    const v = JSON.parse(text);
    if (v === null || typeof v !== "object" || Array.isArray(v)) throw new Error();
    return v as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "bad_json", "body must be a JSON object");
  }
}

export function bearer(req: Request): string {
  const h = req.headers.get("authorization") ?? "";
  const m = h.match(/^Bearer\s+(.+)$/i);
  if (!m) throw new HttpError(401, "unauthorised", "sign-in required");
  return m[1];
}

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The caller's address as seen by the Supabase edge, hashed so it is never stored raw. */
export async function clientIpHash(req: Request, salt: string): Promise<string | null> {
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  return ip ? (await sha256Hex(`${salt}:${ip}`)).slice(0, 32) : null;
}
