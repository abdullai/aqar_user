import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { Readable } from "node:stream";
import { test } from "node:test";
import { createNafathCallbackHandler } from "./server.mjs";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
});
const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-kid", use: "sig", alg: "RS256" };
const requestId = "e6a78347-3c72-4b9b-8b09-daa497e5c4bc";
const transId = "bb0fd95a-baa2-83ce-3f36-4ffc92fd49d0";
const now = Date.now();

function token(claimOverrides = {}) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const header = encode({ alg: "RS256", typ: "JWT", kid: "test-kid" });
  const claims = encode({
    aud: "service-provider",
    iss: "nafath-issuer",
    transId,
    status: "COMPLETED",
    iat: Math.floor(now / 1000),
    exp: Math.floor(now / 1000) + 60,
    ...claimOverrides,
  });
  const signed = `${header}.${claims}`;
  return `${signed}.${sign("RSA-SHA256", Buffer.from(signed), privateKey).toString("base64url")}`;
}

function createHarness({
  status = "WAITING",
  callbackToken = token(),
  nafathStartStatus = 200,
} = {}) {
  const calls = [];
  let currentStatus = status;
  const env = {
    NAFATH_BASE_URL: "https://rabet-nafath.api.elm.sa/nafath-sandbox",
    NAFATH_APP_ID: "test-app-id",
    NAFATH_APP_KEY: "test-app-key",
    NAFATH_AUDIENCE: "service-provider",
    NAFATH_ISSUER: "nafath-issuer",
    NAFATH_SERVICE_PROVIDER_IP: "198.51.100.10",
    NAFATH_GATEWAY_SECRET: "test-gateway-secret-123456789012345678901234",
    SUPABASE_URL: "https://project.example.test",
    SUPABASE_SERVICE_ROLE_KEY: "test-service-role",
  };
  const fetchImpl = async (input, init = {}) => {
    const url = new URL(input);
    calls.push({ url, init });
    if (url.pathname.endsWith("/api/v1/mfa/jwk")) {
      return Response.json({ keys: [jwk] });
    }
    if (url.pathname.endsWith("/api/v1/mfa/request")) {
      if (nafathStartStatus !== 200) {
        return Response.json({ code: "400-034-050" }, {
          status: nafathStartStatus,
        });
      }
      return Response.json({
        transId,
        random: "42",
      });
    }
    if (url.pathname.endsWith("/api/v1/mfa/request/status")) {
      return Response.json({ status: "WAITING", nationalId: "should-not-leak" });
    }
    if (
      url.pathname === "/rest/v1/rpc/complete_nafath_callback" &&
      init.method === "POST"
    ) {
      const update = JSON.parse(init.body);
      if (currentStatus === "WAITING") {
        currentStatus = update.p_status;
        return Response.json(true);
      }
      return Response.json(currentStatus === update.p_status);
    }
    if (url.pathname === "/rest/v1/nafath_logins") {
      if (
        url.searchParams.get("id") === `eq.${requestId}` &&
        url.searchParams.get("trans_id") === `eq.${transId}`
      ) {
        return Response.json([{
          id: requestId,
          trans_id: transId,
          status: currentStatus,
          client_ip: "203.0.113.25",
          created_at: new Date(now - 1000).toISOString(),
        }]);
      }
      return Response.json([]);
    }
    throw new Error(`Unexpected request: ${url}`);
  };
  const handler = createNafathCallbackHandler({
    env,
    fetchImpl,
    now: () => now,
  });
  return {
    calls,
    env,
    currentStatus: () => currentStatus,
    invoke: async (body, { path = "/callback", authorization } = {}) => {
      const req = Readable.from([Buffer.from(JSON.stringify(body))]);
      req.method = "POST";
      req.url = path;
      req.headers = {
        "content-type": "application/json",
        ...(authorization ? { authorization } : {}),
      };
      const res = {
        headers: {},
        writeHead(statusCode, headers) {
          this.statusCode = statusCode;
          this.headers = headers;
        },
        end(value) {
          this.body = JSON.parse(value);
        },
      };
      await handler(req, res);
      return { status: res.statusCode, body: res.body };
    },
    callbackToken,
  };
}

test("health reports configuration failures without exposing credentials", async () => {
  const handler = createNafathCallbackHandler({ env: {} });
  const res = {
    headersSent: false,
    writeHead(statusCode) {
      this.statusCode = statusCode;
    },
    end(value) {
      this.body = JSON.parse(value);
    },
  };
  await handler({
    method: "GET",
    url: "/healthz",
    headers: {},
  }, res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.ok, false);
  assert.equal(res.body.error, "configuration_invalid");
  assert.match(res.body.reason, /NAFATH_SERVICE_PROVIDER_IP/);
  assert.deepEqual(res.body.configuration, [
    "NAFATH_SERVICE_PROVIDER_IP",
    "NAFATH_GATEWAY_SECRET",
    "NAFATH_BASE_URL",
    "NAFATH_APP_ID",
    "NAFATH_APP_KEY",
    "NAFATH_AUDIENCE",
    "NAFATH_ISSUER",
    "SUPABASE_URL",
    "SUPABASE_SERVICE_ROLE_KEY",
  ]);
  assert.equal(JSON.stringify(res.body).includes("SUPABASE_SERVICE_ROLE_KEY="), false);
});

test("authenticated Saudi gateway starts Nafath with the provider-required IP header", async () => {
  const h = createHarness();
  const result = await h.invoke({
    requestId,
    clientIp: "203.0.113.25",
    nationalId: "1234567890",
    service: "Login",
    locale: "ar",
  }, {
    path: "/nafath/start",
    authorization: `Bearer ${h.env.NAFATH_GATEWAY_SECRET}`,
  });
  assert.equal(result.status, 200);
  assert.equal(result.body.transId, transId);
  const request = h.calls.find((call) => call.url.pathname.endsWith("/api/v1/mfa/request"));
  assert.equal(request.init.headers["X-Forwarded-For"], "203.0.113.25,198.51.100.10");
  assert.equal(request.init.headers["APP-ID"], "test-app-id");
  assert.equal(request.init.headers["APP-KEY"], "test-app-key");
  assert.equal(request.url.searchParams.get("requestId"), requestId);
  assert.equal(
    JSON.parse(request.init.body).callbackUrl,
    "https://nafath-callback.onrender.com/callback",
  );
});

test("active Nafath requests return the provider's 400-034-050 code", async () => {
  const h = createHarness({ nafathStartStatus: 400 });
  const result = await h.invoke({
    requestId,
    clientIp: "203.0.113.25",
    nationalId: "1234567890",
    service: "Login",
    locale: "ar",
  }, {
    path: "/nafath/start",
    authorization: `Bearer ${h.env.NAFATH_GATEWAY_SECRET}`,
  });
  assert.equal(result.status, 409);
  assert.equal(result.body.error_code, "400-034-050");
});

test("unauthorized gateway callers cannot reach Nafath", async () => {
  const h = createHarness();
  const result = await h.invoke({
    requestId,
    clientIp: "203.0.113.25",
    nationalId: "1234567890",
    service: "Login",
    locale: "ar",
  }, { path: "/nafath/start" });
  assert.equal(result.status, 401);
  assert.equal(h.calls.length, 0);
});

test("gateway status returns only the status and forwards the recorded user IP", async () => {
  const h = createHarness();
  const result = await h.invoke({
    clientIp: "203.0.113.25",
    nationalId: "1234567890",
    transId,
    random: "42",
  }, {
    path: "/nafath/status",
    authorization: `Bearer ${h.env.NAFATH_GATEWAY_SECRET}`,
  });
  assert.deepEqual(result.body, { status: "WAITING" });
  const request = h.calls.find((call) =>
    call.url.pathname.endsWith("/api/v1/mfa/request/status")
  );
  assert.equal(request.init.headers["X-Forwarded-For"], "203.0.113.25,198.51.100.10");
  assert.equal(request.init.headers["APP-ID"], "test-app-id");
  assert.equal(request.init.headers["APP-KEY"], "test-app-key");
});

test("valid signed completion updates only the matching waiting transaction", async () => {
  const h = createHarness();
  const result = await h.invoke({ requestId, transId, token: h.callbackToken });
  assert.equal(result.status, 200);
  assert.equal(h.currentStatus(), "COMPLETED");
  const update = h.calls.find((call) =>
    call.url.pathname === "/rest/v1/rpc/complete_nafath_callback"
  );
  assert.deepEqual(JSON.parse(update.init.body), {
    p_request_id: requestId,
    p_trans_id: transId,
    p_status: "COMPLETED",
    p_jwt_kid: "test-kid",
  });
  const jwkRequest = h.calls.find((call) => call.url.pathname.endsWith("/jwk"));
  assert.equal(jwkRequest.init.headers["APP-KEY"], "test-app-key");
  assert.equal(
    jwkRequest.init.headers["X-Forwarded-For"],
    "203.0.113.25,198.51.100.10",
  );
});

test("rejects a tampered JWT without changing transaction state", async () => {
  const h = createHarness();
  const [header, claims, signature] = h.callbackToken.split(".");
  const badToken =
    `${header}.${claims}.${signature[0] === "A" ? "B" : "A"}${signature.slice(1)}`;
  const result = await h.invoke({ requestId, transId, token: badToken });
  assert.equal(result.status, 401);
  assert.equal(h.currentStatus(), "WAITING");
});

test("rejects a token bound to another transaction and wrong audience or issuer", async () => {
  for (const claims of [
    { transId: "c6cba251-896b-492a-9a2c-f6ca00e17e48" },
    { aud: "other-service" },
    { iss: "other-issuer" },
    { status: "WAITING" },
  ]) {
    const h = createHarness();
    const result = await h.invoke({ requestId, transId, token: token(claims) });
    assert.equal(result.status, 401);
    assert.equal(h.currentStatus(), "WAITING");
  }
});

test("callback replay is idempotent and conflicting terminal status is rejected", async () => {
  const completed = createHarness({ status: "COMPLETED" });
  assert.equal(
    (await completed.invoke({ requestId, transId, token: completed.callbackToken })).status,
    200,
  );
  const rejected = createHarness({ status: "REJECTED" });
  assert.equal(
    (await rejected.invoke({ requestId, transId, token: rejected.callbackToken })).status,
    409,
  );
});
