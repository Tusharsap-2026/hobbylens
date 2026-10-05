import type { ImageInput } from "./types.ts";
import { HttpError } from "./types.ts";

/** Decodes a base64 photo (optionally a data: URL) and checks its type from the file bytes. */
export function decodeImage(input: unknown, maxBytes: number): ImageInput {
  if (typeof input !== "string" || input.length === 0) {
    throw new HttpError(400, "image_missing", "image_base64 is required");
  }
  const base64 = input.replace(/^data:image\/[a-z]+;base64,/i, "").replace(/\s/g, "");
  // Base64 grows data by a third; reject oversized input before decoding it.
  if (base64.length > Math.ceil(maxBytes / 3) * 4 + 4) {
    throw new HttpError(413, "image_too_large", `image must be at most ${maxBytes} bytes`);
  }
  let bytes: Uint8Array;
  try {
    const bin = atob(base64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    throw new HttpError(400, "image_invalid", "image_base64 is not valid base64");
  }
  if (bytes.length > maxBytes) throw new HttpError(413, "image_too_large", `image must be at most ${maxBytes} bytes`);
  if (bytes.length < 1024) throw new HttpError(400, "image_invalid", "image is too small to identify");
  const mimeType = sniffMime(bytes);
  if (!mimeType) throw new HttpError(415, "image_type", "image must be JPEG, PNG or WebP");
  return { bytes, mimeType, base64 };
}

export function sniffMime(b: Uint8Array): ImageInput["mimeType"] | null {
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (
    b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
    b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50
  ) return "image/webp";
  return null;
}
