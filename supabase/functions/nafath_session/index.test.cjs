const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { stripTypeScriptTypes } = require("node:module");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const requestId = "e6a78347-3c72-4b9b-8b09-daa497e5c4bc";
const transId = "bb0fd95a-baa2-83ce-3f36-4ffc92fd49d0";
const userId = "f1b6be31-09d3-4f20-bad9-6104d17c8701";

function createHarness({
  status = "WAITING",
  callbackCompleted = false,
  activeRequest = false,
  failSave = false,
  ageMs = 0,
  profileRows = [{ user_id: userId }],
  missingSecrets = [],
} = {}) {
  const projectUrl = "https://project.example.test";
  const gatewayUrl = "https://nafath-gateway.example.test";
  const values = {
    SUPABASE_URL: projectUrl,
    SUPABASE_SERVICE_ROLE_KEY: "test-service-role",
    SUPABASE_ANON_KEY: "test-anon-key",
    NAFATH_GATEWAY_URL: gatewayUrl,
    NAFATH_GATEWAY_SECRET: "test-gateway-secret-123456789012345678901234",
  };
  for (const name of missingSecrets) delete values[name];
  const calls = [];
  let handler;
  let row;
  let sessionClaimed = false;
  const respond = (data, code = 200) =>
    new Response(JSON.stringify(data), { status: code });
  const fetch = async (input, init = {}) => {
    const url = new URL(input);
    calls.push({ url, init });
    if (url.origin === gatewayUrl && url.pathname === "/nafath/start") {
      if (activeRequest) {
        return respond({
          error: "nafath_request_already_active",
          error_code: "400-034-050",
        }, 409);
      }
      return respond({ transId, random: "42" });
    }
    if (url.origin === gatewayUrl && url.pathname === "/nafath/status") {
      return respond({ status });
    }
    if (url.origin === projectUrl && url.pathname === "/rest/v1/nafath_logins") {
      if (init.method === "POST") {
        if (failSave) return respond({ error: "database error" }, 500);
        row = {
          ...JSON.parse(init.body),
          status: callbackCompleted ? "COMPLETED" : "WAITING",
          auth_user_id: callbackCompleted ? userId : null,
          created_at: new Date(Date.now() - ageMs).toISOString(),
        };
        return respond([row]);
      }
      if (init.method === "PATCH") {
        if (row && row.status === "WAITING") {
          Object.assign(row, JSON.parse(init.body));
        }
        return respond([]);
      }
      return respond(row && url.searchParams.get("id") === `eq.${row.id}` ? [row] : []);
    }
    if (url.origin === projectUrl && url.pathname === "/rest/v1/users_profiles") {
      return respond(profileRows);
    }
    if (url.origin === projectUrl &&
      url.pathname === "/rest/v1/rpc/claim_nafath_session") {
      if (
        row?.status === "COMPLETED" &&
        row.auth_user_id === userId &&
        !sessionClaimed
      ) {
        sessionClaimed = true;
        return respond(userId);
      }
      return respond(null);
    }
    if (url.origin === projectUrl && url.pathname === `/auth/v1/admin/users/${userId}`) {
      return respond({ id: userId, email: "known-user@example.test" });
    }
    if (url.origin === projectUrl && url.pathname === "/auth/v1/admin/generate_link") {
      return respond({ hashed_token: "one-time-hash" });
    }
    if (url.origin === projectUrl && url.pathname === "/auth/v1/verify") {
      return respond({
        access_token: "signed-access-token",
        refresh_token: "signed-refresh-token",
        user: { id: userId },
      });
    }
    throw new Error(`Unexpected request: ${url}`);
  };
  const source = readFileSync(path.join(__dirname, "index.ts"), "utf8")
    .replace(/^import .*?;\s*/, "");
  vm.runInNewContext(stripTypeScriptTypes(source), {
    Deno: { env: { get: (name) => values[name] } },
    serve: (fn) => { handler = fn; },
    fetch,
    crypto: { randomUUID: () => requestId },
    URL,
    URLSearchParams,
    Headers,
    Request,
    Response,
    AbortSignal,
    console: { error() {} },
  });
  return {
    calls,
    values,
    invoke: async (body, { ip = "203.0.113.25" } = {}) => {
      const res = await handler(new Request("https://function.example.test", {
        method: "POST",
        body: JSON.stringify(body),
        headers: {
          "content-type": "application/json",
          "cf-connecting-ip": ip,
        },
      }));
      return { status: res.status, data: await res.json() };
    },
  };
}

test("missing Nafath gateway configuration reports safe field names", async () => {
  const h = createHarness({
    missingSecrets: ["NAFATH_GATEWAY_URL", "NAFATH_GATEWAY_SECRET"],
  });
  const result = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(result.status, 503);
  assert.equal(result.data.mode, "not_configured");
  assert.deepEqual(result.data.configuration, ["NAFATH_GATEWAY_SECRET"]);
  assert.equal(h.calls.length, 0);
});

test("start relays the request through the Saudi gateway and persists it", async () => {
  const h = createHarness();
  const result = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(result.status, 200);
  assert.equal(result.data.mode, "polling");
  assert.equal(result.data.request_id, requestId);
  assert.equal(result.data.trans_id, transId);
  assert.equal(result.data.random, "42");

  const gateway = h.calls.find((call) => call.url.pathname === "/nafath/start");
  assert.deepEqual(JSON.parse(gateway.init.body), {
    requestId,
    clientIp: "203.0.113.25",
    nationalId: "1234567890",
    service: "Login",
    locale: "ar",
  });
  assert.equal(
    gateway.init.headers.Authorization,
    `Bearer ${h.values.NAFATH_GATEWAY_SECRET}`,
  );
  const save = h.calls.find((call) =>
    call.url.pathname === "/rest/v1/nafath_logins" &&
    call.init.method === "POST"
  );
  assert.equal(JSON.parse(save.init.body).status, "WAITING");
});

test("active request errors preserve the Nafath 400-034-050 code", async () => {
  const h = createHarness({ activeRequest: true });
  const result = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(result.status, 409);
  assert.equal(result.data.error_code, "400-034-050");
});

test("a failed request save cannot produce a polling response", async () => {
  const h = createHarness({ failSave: true });
  const result = await h.invoke({ action: "start", national_id: "1234567890" });
  assert.equal(result.status, 500);
  assert.equal(result.data.mode, "error");
});

test("waiting state is confirmed through the gateway and returns the random number", async () => {
  const h = createHarness({ status: "WAITING" });
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({ action: "poll", request_id: start.data.request_id });
  assert.equal(result.data.status, "WAITING");
  assert.equal(result.data.random, "42");
  const statusRequest = h.calls.find((call) => call.url.pathname === "/nafath/status");
  assert.deepEqual(JSON.parse(statusRequest.init.body), {
    clientIp: "203.0.113.25",
    nationalId: "1234567890",
    transId,
    random: "42",
  });
});

test("provider COMPLETED is not trusted until the signed callback has updated the row", async () => {
  const h = createHarness({ status: "COMPLETED" });
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({ action: "poll", request_id: start.data.request_id });
  assert.equal(result.status, 200);
  assert.equal(result.data.mode, "polling");
  assert.equal(result.data.status, "WAITING");
  assert.equal(h.calls.some((call) => call.url.pathname === "/auth/v1/verify"), false);
});

test("a signed callback completion issues a one-time Supabase session for the matched account", async () => {
  const h = createHarness({ callbackCompleted: true });
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({ action: "poll", request_id: start.data.request_id });
  assert.equal(result.status, 200);
  assert.equal(result.data.mode, "redirect");
  assert.equal(result.data.status, "COMPLETED");
  assert.equal(result.data.refresh_token, "signed-refresh-token");
  assert.equal(result.data.access_token, "signed-access-token");

  const generated = h.calls.find((call) =>
    call.url.pathname === "/auth/v1/admin/generate_link"
  );
  assert.deepEqual(JSON.parse(generated.init.body), {
    type: "magiclink",
    email: "known-user@example.test",
  });
  const verified = h.calls.find((call) => call.url.pathname === "/auth/v1/verify");
  assert.deepEqual(JSON.parse(verified.init.body), {
    type: "magiclink",
    token_hash: "one-time-hash",
  });
});

test("a verified Nafath identity without an existing profile cannot create a session", async () => {
  const h = createHarness({ callbackCompleted: true, profileRows: [] });
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({ action: "poll", request_id: start.data.request_id });
  assert.equal(result.status, 404);
  assert.equal(result.data.error, "nafath_account_not_found");
  assert.equal(h.calls.some((call) => call.url.pathname === "/auth/v1/verify"), false);
});

test("expired local requests do not reach the gateway", async () => {
  const h = createHarness({ ageMs: 6 * 60 * 1000 });
  const start = await h.invoke({ action: "start", national_id: "1234567890" });
  const result = await h.invoke({ action: "poll", request_id: start.data.request_id });
  assert.equal(result.status, 410);
  assert.equal(result.data.status, "EXPIRED");
  assert.equal(h.calls.some((call) => call.url.pathname === "/nafath/status"), false);
});
