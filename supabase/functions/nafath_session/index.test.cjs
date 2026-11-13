const assert = require("node:assert/strict");
const { webcrypto } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { stripTypeScriptTypes } = require("node:module");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function createHarness({ status = "WAITING", failSave = false, ageMs = 0 } = {}) {
  const projectUrl = "https://project.example.test";
  const gatewayUrl = "https://nafath-gateway.example.test";
  const values = {
    SUPABASE_URL: projectUrl,
    SUPABASE_SERVICE_ROLE_KEY: "test-service-role",
    NAFATH_GATEWAY_URL: gatewayUrl,
    NAFATH_GATEWAY_SECRET: "test-gateway-secret-123456789012345678901234",
  };
  const calls = [];
  let handler;
  let row;
  const respond = (data, code = 200) =>
    new Response(JSON.stringify(data), { status: code });
  const fetch = async (input, init = {}) => {
    const url = new URL(input);
    calls.push({ url, init });
    if (url.origin === gatewayUrl && url.pathname === "/nafath/status") {
      return respond({ status });
    }
    if (url.origin === gatewayUrl && url.pathname === "/nafath/start") {
      return respond({ transId: "00000000-0000-4000-8000-000000000002", random: "42" });
    }
    if (url.origin === projectUrl && url.pathname === "/rest/v1/nafath_logins") {
      if (init.method === "POST") {
        if (failSave) return respond({ error: "db error" }, 500);
        row = { ...JSON.parse(init.body), created_at: new Date(Date.now() - ageMs).toISOString() };
        return respond([row]);
      }
      return respond(row && url.searchParams.get("id") === `eq.${row.id}` ? [row] : []);
    }
    throw new Error(`Unexpected mocked request: ${url}`);
  };
  const source = readFileSync(path.join(__dirname, "index.ts"), "utf8")
    .replace(/^import .*?;\s*/, "");
  vm.runInNewContext(stripTypeScriptTypes(source), {
    Deno: { env: { get: (name) => values[name] } },
    serve: (fn) => { handler = fn; },
    fetch, crypto: webcrypto, URL, URLSearchParams, Headers, Request, Response, AbortSignal,
    console: { error() {} },
  });
  return {
    calls, values,
    invoke: async (body) => {
      const res = await handler(new Request("https://function.example.test", {
        method: "POST",
        body: JSON.stringify(body),
        headers: {
          "content-type": "application/json",
          "cf-connecting-ip": "203.0.113.25",
        },
      }));
      return { status: res.status, data: await res.json() };
    },
  };
}

test("start uses the Saudi gateway and preserves transaction and client IP", async () => {
  const h = createHarness();
  const result = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(result.data.mode, "polling");
  const provider = h.calls[0];
  assert.equal(provider.url.origin, "https://nafath-gateway.example.test");
  assert.equal(provider.init.headers.Authorization, `Bearer ${h.values.NAFATH_GATEWAY_SECRET}`);
  assert.equal(provider.init.redirect, "error");
  assert.deepEqual(JSON.parse(provider.init.body), {
    nationalId: "1234567890",
    service: "Login",
    locale: "ar",
    requestId: result.data.request_id,
    clientIp: "203.0.113.25",
  });
});

test("missing credentials and invalid identifiers fail without a provider request", async () => {
  const h = createHarness();
  const invalid = await h.invoke({ action: "start", national_id: "123-4567890" });
  assert.equal(invalid.status, 400);
  delete h.values.NAFATH_GATEWAY_SECRET;
  const missing = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(missing.status, 503);
  assert.equal(h.calls.length, 0);
});

test("a failed request save cannot produce a polling response", async () => {
  const h = createHarness({ failSave: true });
  const result = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(result.status, 500);
  assert.equal(result.data.mode, "error");
});

test("a forged callback cannot override the independently checked provider status", async () => {
  const h = createHarness();
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({
    action: "callback", requestId: start.data.request_id, status: "COMPLETED",
  });
  assert.equal(result.data.status, "WAITING");
  const call = h.calls.find((item) => item.url.pathname === "/nafath/status");
  assert.deepEqual(JSON.parse(call.init.body), {
    nationalId: "1234567890",
    transId: "00000000-0000-4000-8000-000000000002",
    random: "42",
    clientIp: "203.0.113.25",
  });
});

test("completed Nafath verification cannot create a fake account session", async () => {
  const h = createHarness({ status: "COMPLETED" });
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({ action: "poll", request_id: start.data.request_id });
  assert.equal(result.data.status, "COMPLETED");
  assert.equal(result.data.error, "nafath_auth_session_not_configured");
  assert.equal(result.data.mode, "not_configured");
  assert.equal(h.calls.some((item) => item.url.pathname.startsWith("/auth/")), false);
});

test("unknown status and expired local requests fail closed", async () => {
  const unknown = createHarness({ status: "UNKNOWN" });
  const start = await unknown.invoke({ action: "start", national_id: "1234567890" });
  assert.equal((await unknown.invoke({ action: "poll", request_id: start.data.request_id })).status, 502);
  const expired = createHarness({ ageMs: 6 * 60 * 1000 });
  const old = await expired.invoke({ action: "start", national_id: "1234567890" });
  assert.equal((await expired.invoke({ action: "poll", request_id: old.data.request_id })).status, 410);
  assert.equal(expired.calls.some((item) => item.url.pathname === "/nafath/status"), false);
});
