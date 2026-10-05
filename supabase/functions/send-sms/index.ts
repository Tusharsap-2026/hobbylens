// Supabase Auth "Send SMS" hook: Supabase calls this to deliver phone OTP codes, so they go
// through a local Bangladeshi gateway (about BDT 0.35 each) instead of an international one.
// Configure under Authentication > Hooks > Send SMS (HTTPS), pointing at this function.
import { Webhook } from "npm:standardwebhooks@1.1.1";
import { formatNumber, type NumberFormat, otpMessage, type SmsSender, toBdMsisdn } from "../_shared/sms.ts";
import { ConsoleSender, HttpTemplateSender } from "../_shared/sms.ts";
import { HttpError } from "../_shared/types.ts";

const hookSecret = (Deno.env.get("SEND_SMS_HOOK_SECRET") ?? "").replace(/^v1,whsec_/, "");
const template = Deno.env.get("SMS_TEMPLATE") ?? "HobbyLens code: {otp}. Do not share this code with anyone.";
const numberFormat = (Deno.env.get("SMS_NUMBER_FORMAT") ?? "880") as NumberFormat;

function buildSender(): SmsSender {
  const provider = Deno.env.get("SMS_PROVIDER") ?? "console";
  if (provider === "console") return new ConsoleSender();
  if (provider === "http") {
    for (const key of ["SMS_URL_TEMPLATE", "SMS_API_KEY", "SMS_SUCCESS_PATTERN"]) {
      // The success pattern differs per gateway; it must come from the provider's API document.
      if (!Deno.env.get(key)) throw new Error(`${key} must be set when SMS_PROVIDER=http`);
    }
    return new HttpTemplateSender({
      urlTemplate: Deno.env.get("SMS_URL_TEMPLATE") ?? "",
      method: (Deno.env.get("SMS_HTTP_METHOD") ?? "GET") === "POST" ? "POST" : "GET",
      apiKey: Deno.env.get("SMS_API_KEY") ?? "",
      senderId: Deno.env.get("SMS_SENDER_ID") ?? "",
      successPattern: new RegExp(Deno.env.get("SMS_SUCCESS_PATTERN")!, "i"),
    });
  }
  throw new Error(`unknown SMS_PROVIDER "${provider}"`);
}
const sender = buildSender();

function hookError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return hookError(405, "use POST");
  const payload = await req.text();

  // deno-lint-ignore no-explicit-any
  let event: any;
  try {
    event = new Webhook(hookSecret).verify(payload, Object.fromEntries(req.headers));
  } catch {
    return hookError(401, "invalid hook signature");
  }

  try {
    const otp = String(event?.sms?.otp ?? "");
    if (!/^\d{4,10}$/.test(otp)) throw new HttpError(400, "bad_otp", "missing OTP");
    const to = formatNumber(toBdMsisdn(String(event?.user?.phone ?? "")), numberFormat);
    await sender.send(to, otpMessage(template, otp));
    return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("send-sms failed", err);
    if (err instanceof HttpError) return hookError(err.status === 400 ? 400 : 502, err.message);
    return hookError(500, "could not send the code");
  }
});
