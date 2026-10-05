import { strict as assert } from "node:assert";
import { Webhook } from "npm:standardwebhooks@1.1.1";
import { formatNumber, HttpTemplateSender, otpMessage, toBdMsisdn } from "../_shared/sms.ts";
import { HttpError } from "../_shared/types.ts";

Deno.test("Bangladeshi mobile numbers are normalised from any common form", () => {
  for (const input of ["01711223344", "+8801711223344", "8801711223344", "008801711223344", "+880 1711-223344"]) {
    assert.equal(toBdMsisdn(input), "8801711223344", input);
  }
});

Deno.test("non-mobile or foreign numbers are refused", () => {
  for (const input of ["0171122334", "+441711223344", "+8802711223344", "01211223344"]) {
    assert.throws(() => toBdMsisdn(input), (e: unknown) => e instanceof HttpError && e.code === "bad_phone", input);
  }
});

Deno.test("number formats for different gateways", () => {
  assert.equal(formatNumber("8801711223344", "e164"), "+8801711223344");
  assert.equal(formatNumber("8801711223344", "880"), "8801711223344");
  assert.equal(formatNumber("8801711223344", "local"), "01711223344");
});

Deno.test("the HTTP gateway fills and encodes the URL template, and checks the reply", async () => {
  const urls: string[] = [];
  const sender = new HttpTemplateSender({
    urlTemplate: "https://sms.example/api?key={api_key}&from={sender_id}&to={to}&msg={message}",
    method: "GET",
    apiKey: "k&1",
    senderId: "HobbyLens",
    successPattern: /"status":"ok"/,
    fetch: ((u: string) => {
      urls.push(String(u));
      return Promise.resolve(new Response('{"status":"ok"}'));
    }) as typeof fetch,
  });
  await sender.send("8801711223344", otpMessage("Code: {otp}", "123456"));
  assert.equal(urls[0], "https://sms.example/api?key=k%261&from=HobbyLens&to=8801711223344&msg=Code%3A%20123456");

  const failing = new HttpTemplateSender({
    urlTemplate: "https://sms.example/api?to={to}&msg={message}",
    method: "POST",
    apiKey: "",
    senderId: "",
    successPattern: /"status":"ok"/,
    fetch: (() => Promise.resolve(new Response('{"status":"insufficient balance"}'))) as typeof fetch,
  });
  await assert.rejects(failing.send("8801711223344", "x"), (e: unknown) => e instanceof HttpError && e.retryable);
});

Deno.test("hook payloads signed with the shared secret verify; tampered ones do not", () => {
  const secret = btoa("a-test-secret-of-sufficient-length-123");
  const wh = new Webhook(secret);
  const payload = JSON.stringify({ user: { phone: "8801711223344" }, sms: { otp: "123456" } });
  const id = "msg_1";
  const ts = new Date();
  const sig = wh.sign(id, ts, payload);
  const headers = { "webhook-id": id, "webhook-timestamp": String(Math.floor(ts.getTime() / 1000)), "webhook-signature": sig };
  // deno-lint-ignore no-explicit-any
  const event = wh.verify(payload, headers) as any;
  assert.equal(event.sms.otp, "123456");
  assert.throws(() => wh.verify(payload.replace("123456", "000000"), headers));
});
