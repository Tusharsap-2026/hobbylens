import { HttpError } from "./types.ts";

/**
 * Bangladeshi mobile numbers: 01[3-9]XXXXXXXX locally, 8801[3-9]XXXXXXXX internationally.
 * Returns the 13-digit international form without "+", or throws.
 */
export function toBdMsisdn(phone: string): string {
  const digits = phone.replace(/[^\d]/g, "");
  let n = digits;
  if (n.startsWith("00880")) n = n.slice(2);
  if (n.startsWith("01") && n.length === 11) n = "88" + n;
  if (!/^8801[3-9]\d{8}$/.test(n)) {
    throw new HttpError(400, "bad_phone", "only Bangladeshi mobile numbers are supported");
  }
  return n;
}

export type NumberFormat = "e164" | "880" | "local";

export function formatNumber(msisdn: string, format: NumberFormat): string {
  switch (format) {
    case "e164":
      return `+${msisdn}`;
    case "880":
      return msisdn;
    case "local":
      return msisdn.slice(2); // 01XXXXXXXXX
  }
}

export interface SmsSender {
  send(to: string, message: string): Promise<void>;
}

/** Logs instead of sending. For local development only. */
export class ConsoleSender implements SmsSender {
  sent: Array<{ to: string; message: string }> = [];
  send(to: string, message: string) {
    this.sent.push({ to, message });
    console.log(`[sms:console] to=${to} message=${message}`);
    return Promise.resolve();
  }
}

/**
 * Generic HTTP gateway. Most Bangladeshi SMS gateways take a GET or form POST with an API key,
 * sender id, number and message. The URL template uses {api_key}, {sender_id}, {to} and
 * {message}, each URL-encoded, e.g.
 *   https://gateway.example/api/send?api_key={api_key}&senderid={sender_id}&number={to}&message={message}
 * Copy the exact template from the chosen provider's API document.
 */
export class HttpTemplateSender implements SmsSender {
  constructor(
    private readonly opts: {
      urlTemplate: string;
      method: "GET" | "POST";
      apiKey: string;
      senderId: string;
      /** Text the gateway returns on success; anything else is treated as a failure. */
      successPattern: RegExp;
      fetch?: typeof fetch;
    },
  ) {}

  async send(to: string, message: string): Promise<void> {
    const fill = (tpl: string) =>
      tpl
        .replaceAll("{api_key}", encodeURIComponent(this.opts.apiKey))
        .replaceAll("{sender_id}", encodeURIComponent(this.opts.senderId))
        .replaceAll("{to}", encodeURIComponent(to))
        .replaceAll("{message}", encodeURIComponent(message));
    const full = fill(this.opts.urlTemplate);
    let res: Response;
    if (this.opts.method === "GET") {
      res = await (this.opts.fetch ?? fetch)(full, { signal: AbortSignal.timeout(10_000) });
    } else {
      const [base, query = ""] = full.split("?", 2);
      res = await (this.opts.fetch ?? fetch)(base, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: query,
        signal: AbortSignal.timeout(10_000),
      });
    }
    const text = await res.text();
    if (!res.ok || !this.opts.successPattern.test(text)) {
      throw new HttpError(502, "sms_failed", `SMS gateway rejected the message (${res.status}): ${text.slice(0, 120)}`, true);
    }
  }
}

export function otpMessage(template: string, otp: string): string {
  return template.replaceAll("{otp}", otp);
}
