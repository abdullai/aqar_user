const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { stripTypeScriptTypes } = require("node:module");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function createHarness({ granted = true, authStatus = 200, providerStatus = 200 } = {}) {
  const projectUrl = "https://project.example.test";
  const values = {
    SUPABASE_URL: projectUrl,
    SUPABASE_ANON_KEY: "test-anon",
    SUPABASE_SERVICE_ROLE_KEY: "test-service",
    WATHQ_API_KEY: "test-wathq",
  };
  const calls = [];
  let handler;
  const respond = (data, status = 200) =>
    new Response(JSON.stringify(data), { status });
  const fetch = async (input, init = {}) => {
    const url = new URL(input);
    calls.push({ url, init });
    if (url.pathname === "/auth/v1/user") {
      return respond({ id: "00000000-0000-4000-8000-000000000001" }, authStatus);
    }
    if (url.pathname === "/rest/v1/wathq_access_grants") {
      return respond(granted ? [{ id: "grant" }] : []);
    }
    if (url.hostname === "api.wathq.sa") {
      return respond(url.pathname.includes("/deed/") ? { deedDetails: { valid: true } } : { valid: true }, providerStatus);
    }
    throw new Error("Unexpected request");
  };
  const source = readFileSync(path.join(__dirname, "index.ts"), "utf8")
    .replace(/^export \{\};\s*/, "");
  vm.runInNewContext(stripTypeScriptTypes(source), {
    Deno: { env: { get: (name) => values[name] }, serve: (fn) => { handler = fn; } },
    fetch, URL, URLSearchParams, Request, Response, AbortSignal,
    console: { error() {} },
  });
  return {
    calls, values,
    invoke: async (body, authorization = "Bearer user-token") => {
      const res = await handler(new Request("https://function.example.test", {
        method: "POST",
        headers: { authorization, "content-type": "application/json" },
        body: JSON.stringify(body),
      }));
      return { status: res.status, data: await res.json(), headers: res.headers };
    },
    handler,
  };
}

test("commercial request verifies user and resource grant before calling sandbox with apiKey", async () => {
  const h = createHarness();
  const result = await h.invoke({
    action: "get_commercial_registration",
    crNumber: "1234567890",
    language: "en",
    userId: "attacker-controlled",
  });
  assert.equal(result.status, 200);
  assert.equal(result.data.success, true);
  assert.equal(result.headers.get("access-control-allow-origin"), "*");
  assert.equal(h.calls[0].init.headers.Authorization, "Bearer user-token");
  assert.equal(h.calls[1].url.searchParams.get("user_id"), "eq.00000000-0000-4000-8000-000000000001");
  assert.equal(h.calls[1].url.searchParams.get("resource_type"), "eq.commercial_registration");
  const provider = h.calls[2];
  assert.equal(provider.url.pathname, "/sandbox/commercial-registration/info/1234567890");
  assert.equal(provider.url.searchParams.get("language"), "en");
  assert.equal(provider.init.headers.apiKey, "test-wathq");
  assert.equal(provider.init.redirect, "error");
});

test("address and deed use distinct grants and exact provider routes", async () => {
  const address = createHarness();
  const addressResult = await address.invoke({ action: "get_national_address", crNumber: "1234567890" });
  assert.ok(Array.isArray(addressResult.data.data));
  assert.equal(address.calls[1].url.searchParams.get("resource_type"), "eq.national_address");
  assert.equal(address.calls[2].url.pathname, "/spl/national/address/info/1234567890");
  const deed = createHarness();
  const deedResult = await deed.invoke({
    action: "get_real_estate_deed", deedNumber: "1234", idNumber: "1234567890", idType: "National_ID",
  });
  assert.equal(deedResult.data.data.valid, true);
  assert.equal(deed.calls[1].url.searchParams.get("owner_id"), "eq.1234567890");
  assert.equal(deed.calls[1].url.searchParams.get("owner_id_type"), "eq.National_ID");
  assert.equal(deed.calls[2].url.pathname, "/moj/real-estate/deed/1234/1234567890/National_ID");
});

test("no authorization or no verified grant prevents upstream requests", async () => {
  const missing = createHarness();
  assert.equal((await missing.invoke({ action: "get_national_address", crNumber: "1234567890" }, "")).status, 401);
  assert.equal(missing.calls.length, 0);
  const invalid = createHarness({ authStatus: 401 });
  assert.equal((await invalid.invoke({ action: "get_national_address", crNumber: "1234567890" })).status, 401);
  assert.equal(invalid.calls.length, 1);
  const denied = createHarness({ granted: false });
  assert.equal((await denied.invoke({ action: "get_national_address", crNumber: "1234567890" })).status, 403);
  assert.equal(denied.calls.length, 2);
});

test("malformed parameters cannot alter the requested endpoint", async () => {
  const h = createHarness();
  const result = await h.invoke({
    action: "get_real_estate_deed", deedNumber: "1/../../info", idNumber: "1234567890", idType: "National_ID",
  });
  assert.equal(result.status, 400);
  assert.equal(h.calls.length, 0);
});

test("provider failures are clear and do not expose secrets", async () => {
  const h = createHarness({ providerStatus: 401 });
  const result = await h.invoke({ action: "get_national_address", crNumber: "1234567890" });
  assert.equal(result.status, 502);
  assert.equal(result.data.error, "wathq_request_failed");
  assert.equal(result.data.statusCode, 502);
  assert.equal(JSON.stringify(result.data).includes("test-wathq"), false);
});

test("missing server configuration fails without calling any service", async () => {
  const h = createHarness();
  delete h.values.WATHQ_API_KEY;
  const result = await h.invoke({ action: "get_national_address", crNumber: "1234567890" });
  assert.equal(result.status, 503);
  assert.equal(result.data.error, "not_configured");
  assert.equal(h.calls.length, 0);
});

test("CORS preflight succeeds without credentials", async () => {
  const h = createHarness();
  const result = await h.handler(new Request("https://function.example.test", { method: "OPTIONS" }));
  assert.equal(result.status, 204);
  assert.match(result.headers.get("access-control-allow-headers"), /authorization/);
  assert.equal(h.calls.length, 0);
});
