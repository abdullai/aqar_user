import {
  createPublicKey,
  timingSafeEqual,
  verify as verifySignature,
} from "node:crypto";
import { createServer } from "node:http";
import { isIP } from "node:net";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const MAX_BODY_BYTES = 64 * 1024;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FINAL_STATUSES = new Set(["COMPLETED", "REJECTED"]);

function json(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(JSON.stringify(body));
}

function requiredEnv(env, name) {
  const value = env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function httpsUrl(value, name, allowedHostSuffix) {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    (allowedHostSuffix && !url.hostname.endsWith(allowedHostSuffix))
  ) {
    throw new Error(`${name} must be an HTTPS URL on an approved host`);
  }
  return url;
}

function readConfig(env) {
  const serviceProviderIp = requiredEnv(env, "NAFATH_SERVICE_PROVIDER_IP");
  if (!isIP(serviceProviderIp)) {
    throw new Error("NAFATH_SERVICE_PROVIDER_IP must be a public IP address");
  }
  const gatewaySecret = requiredEnv(env, "NAFATH_GATEWAY_SECRET");
  if (gatewaySecret.length < 32) {
    throw new Error("NAFATH_GATEWAY_SECRET must contain at least 32 characters");
  }
  const baseUrl = httpsUrl(
    requiredEnv(env, "NAFATH_BASE_URL"),
    "NAFATH_BASE_URL",
    ".elm.sa",
  );
  const jwkUrl = httpsUrl(
    env.NAFATH_JWK_URL?.trim() ||
      new URL("api/v1/mfa/jwk", `${baseUrl.href.replace(/\/+$/, "")}/`).href,
    "NAFATH_JWK_URL",
    ".elm.sa",
  );
  const supabaseUrl = httpsUrl(
    requiredEnv(env, "SUPABASE_URL"),
    "SUPABASE_URL",
  );
  return {
    baseUrl,
    appId: requiredEnv(env, "NAFATH_APP_ID"),
    appKey: requiredEnv(env, "NAFATH_APP_KEY"),
    audience: requiredEnv(env, "NAFATH_AUDIENCE"),
    issuer: requiredEnv(env, "NAFATH_ISSUER"),
    serviceProviderIp,
    gatewaySecret,
    jwkUrl,
    supabaseUrl,
    serviceRoleKey: requiredEnv(env, "SUPABASE_SERVICE_ROLE_KEY"),
  };
}

function decodeBase64Url(value) {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid_base64url");
  return Buffer.from(value, "base64url");
}

function decodeJsonPart(value) {
  return JSON.parse(decodeBase64Url(value).toString("utf8"));
}

function audienceMatches(actual, expected) {
  return actual === expected ||
    (Array.isArray(actual) && actual.includes(expected));
}

function verifyJwt(token, jwk, config, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (typeof token !== "string" || token.length > 32 * 1024) {
    throw new Error("invalid_token");
  }
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("invalid_token");

  const header = decodeJsonPart(parts[0]);
  const claims = decodeJsonPart(parts[1]);
  if (
    !header ||
    typeof header !== "object" ||
    header.alg !== "RS256" ||
    !jwk ||
    jwk.kty !== "RSA" ||
    jwk.use && jwk.use !== "sig" ||
    jwk.alg && jwk.alg !== "RS256" ||
    jwk.kid !== header.kid
  ) {
    throw new Error("invalid_signing_key");
  }

  const publicKey = createPublicKey({ key: jwk, format: "jwk" });
  const signedContent = Buffer.from(`${parts[0]}.${parts[1]}`, "ascii");
  if (
    !verifySignature(
      "RSA-SHA256",
      signedContent,
      publicKey,
      decodeBase64Url(parts[2]),
    )
  ) {
    throw new Error("invalid_signature");
  }

  if (
    !claims ||
    typeof claims !== "object" ||
    claims.iss !== config.issuer ||
    !audienceMatches(claims.aud, config.audience) ||
    !Number.isInteger(claims.exp) ||
    claims.exp <= nowSeconds ||
    !Number.isInteger(claims.iat) ||
    claims.iat > nowSeconds + 60 ||
    (claims.nbf !== undefined &&
      (!Number.isInteger(claims.nbf) || claims.nbf > nowSeconds + 60)) ||
    !FINAL_STATUSES.has(claims.status) ||
    typeof claims.transId !== "string"
  ) {
    throw new Error("invalid_claims");
  }
  return claims;
}

async function readBody(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error("body_too_large");
    chunks.push(chunk);
  }
  const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error("invalid_body");
  }
  return body;
}

async function fetchJson(fetchImpl, url, init) {
  const response = await fetchImpl(url, {
    ...init,
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`upstream_${response.status}`);
  try {
    return text ? JSON.parse(text) : null;
  } catch {
    throw new Error("upstream_invalid_json");
  }
}

export function createNafathCallbackHandler({
  env = process.env,
  fetchImpl = fetch,
  now = () => Date.now(),
}) {
  let config;
  let jwksCache;
  let jwksCacheUntil = 0;

  const getConfig = () => config ??= readConfig(env);

  async function getJwks(clientIp, forceRefresh = false) {
    const currentConfig = getConfig();
    if (!forceRefresh && jwksCache && now() < jwksCacheUntil) return jwksCache;
    const response = await fetchJson(fetchImpl, currentConfig.jwkUrl, {
      headers: {
        "APP-ID": currentConfig.appId,
        "APP-KEY": currentConfig.appKey,
        "X-Forwarded-For": `${clientIp},${currentConfig.serviceProviderIp}`,
        "Content-Type": "application/json",
      },
    });
    if (!response || !Array.isArray(response.keys)) {
      throw new Error("invalid_jwks_response");
    }
    jwksCache = response.keys;
    jwksCacheUntil = now() + 5 * 60 * 1000;
    return jwksCache;
  }

  async function findRow(requestId, transId) {
    const currentConfig = getConfig();
    const url = new URL("/rest/v1/nafath_logins", currentConfig.supabaseUrl);
    url.searchParams.set("select", "id,trans_id,status,created_at,client_ip");
    url.searchParams.set("id", `eq.${requestId}`);
    url.searchParams.set("trans_id", `eq.${transId}`);
    url.searchParams.set("limit", "1");
    const rows = await fetchJson(fetchImpl, url, {
      headers: {
        apikey: currentConfig.serviceRoleKey,
        Authorization: `Bearer ${currentConfig.serviceRoleKey}`,
      },
    });
    return Array.isArray(rows) ? rows[0] ?? null : null;
  }

  async function updateRow(requestId, transId, status) {
    const currentConfig = getConfig();
    const url = new URL("/rest/v1/nafath_logins", currentConfig.supabaseUrl);
    url.searchParams.set("id", `eq.${requestId}`);
    url.searchParams.set("trans_id", `eq.${transId}`);
    url.searchParams.set("status", "eq.WAITING");
    const updatedAt = new Date(now()).toISOString();
    const update = {
      status,
      updated_at: updatedAt,
      ...(status === "COMPLETED" ? { completed_at: updatedAt } : {}),
      ...(status === "REJECTED" ? { rejected_at: updatedAt } : {}),
    };
    const rows = await fetchJson(fetchImpl, url, {
      method: "PATCH",
      headers: {
        apikey: currentConfig.serviceRoleKey,
        Authorization: `Bearer ${currentConfig.serviceRoleKey}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify(update),
    });
    return Array.isArray(rows) ? rows.length > 0 : false;
  }

  async function processCallback(body) {
    const requestId = typeof body.requestId === "string"
      ? body.requestId.toLowerCase()
      : "";
    const transId = typeof body.transId === "string"
      ? body.transId.toLowerCase()
      : "";
    if (
      !UUID_PATTERN.test(requestId) ||
      !UUID_PATTERN.test(transId) ||
      typeof body.token !== "string"
    ) {
      return { status: 400, body: { error: "invalid_callback" } };
    }

    const row = await findRow(requestId, transId);
    if (!row) return { status: 404, body: { error: "transaction_not_found" } };

    const createdAt = Date.parse(row.created_at);
    if (
      !Number.isFinite(createdAt) ||
      createdAt > now() + 60_000 ||
      now() - createdAt > 200_000
    ) {
      return { status: 410, body: { error: "transaction_expired" } };
    }
    if (typeof row.client_ip !== "string" || !isIP(row.client_ip)) {
      return { status: 409, body: { error: "transaction_missing_client_ip" } };
    }

    const currentConfig = getConfig();
    const tokenParts = body.token.split(".");
    if (tokenParts.length !== 3) {
      return { status: 401, body: { error: "invalid_token" } };
    }
    let header;
    try {
      header = decodeJsonPart(tokenParts[0]);
    } catch {
      return { status: 401, body: { error: "invalid_token" } };
    }
    if (!header || typeof header.kid !== "string" || header.alg !== "RS256") {
      return { status: 401, body: { error: "invalid_token" } };
    }

    let keys = await getJwks(row.client_ip);
    let jwk = keys.find((key) => key.kid === header.kid);
    if (!jwk) {
      keys = await getJwks(row.client_ip, true);
      jwk = keys.find((key) => key.kid === header.kid);
    }
    if (!jwk) return { status: 401, body: { error: "unknown_signing_key" } };

    let claims;
    try {
      claims = verifyJwt(body.token, jwk, currentConfig, Math.floor(now() / 1000));
    } catch {
      return { status: 401, body: { error: "invalid_token" } };
    }
    if (claims.transId.toLowerCase() !== transId) {
      return { status: 401, body: { error: "transaction_mismatch" } };
    }

    if (row.status === claims.status) {
      return { status: 200, body: { success: true } };
    }
    if (row.status !== "WAITING") {
      return { status: 409, body: { error: "transaction_already_final" } };
    }
    if (!(await updateRow(requestId, transId, claims.status))) {
      const current = await findRow(requestId, transId);
      if (current?.status !== claims.status) {
        return { status: 409, body: { error: "transaction_already_final" } };
      }
    }
    return { status: 200, body: { success: true } };
  }

  function isGatewayAuthorized(req) {
    const expected = `Bearer ${getConfig().gatewaySecret}`;
    const supplied = req.headers.authorization ?? "";
    const expectedBytes = Buffer.from(expected);
    const suppliedBytes = Buffer.from(supplied);
    return suppliedBytes.length === expectedBytes.length &&
      timingSafeEqual(suppliedBytes, expectedBytes);
  }

  function providerHeaders(clientIp) {
    const currentConfig = getConfig();
    return {
      "APP-ID": currentConfig.appId,
      "APP-KEY": currentConfig.appKey,
      "X-Forwarded-For": `${clientIp},${currentConfig.serviceProviderIp}`,
      "Content-Type": "application/json",
    };
  }

  function isValidClientIp(value) {
    return typeof value === "string" && isIP(value) !== 0;
  }

  async function startNafath(body) {
    if (
      typeof body.requestId !== "string" ||
      !UUID_PATTERN.test(body.requestId) ||
      typeof body.clientIp !== "string" ||
      !isValidClientIp(body.clientIp) ||
      typeof body.nationalId !== "string" ||
      !/^[123456]\d{9}$/.test(body.nationalId) ||
      !["Login", "Register"].includes(body.service) ||
      !["ar", "en"].includes(body.locale)
    ) {
      return { status: 400, body: { error: "invalid_nafath_request" } };
    }

    const currentConfig = getConfig();
    const url = new URL(
      "api/v1/mfa/request",
      `${currentConfig.baseUrl.href.replace(/\/+$/, "")}/`,
    );
    url.searchParams.set("local", body.locale);
    url.searchParams.set("requestId", body.requestId);
    const response = await fetchJson(fetchImpl, url, {
      method: "POST",
      headers: providerHeaders(body.clientIp),
      body: JSON.stringify({
        nationalId: body.nationalId,
        service: body.service,
      }),
    });
    const transId = typeof response?.transId === "string"
      ? response.transId.replace(/^\{|\}$/g, "").toLowerCase()
      : "";
    const random = response?.random;
    if (!UUID_PATTERN.test(transId) || !/^\d{2}$/.test(String(random ?? ""))) {
      throw new Error("invalid_nafath_start_response");
    }
    return { status: 200, body: { transId, random: String(random) } };
  }

  async function pollNafath(body) {
    if (
      typeof body.clientIp !== "string" ||
      !isValidClientIp(body.clientIp) ||
      typeof body.nationalId !== "string" ||
      !/^[123456]\d{9}$/.test(body.nationalId) ||
      typeof body.transId !== "string" ||
      !UUID_PATTERN.test(body.transId) ||
      typeof body.random !== "string" ||
      !/^\d{2}$/.test(body.random)
    ) {
      return { status: 400, body: { error: "invalid_nafath_request" } };
    }

    const currentConfig = getConfig();
    const url = new URL(
      "api/v1/mfa/request/status",
      `${currentConfig.baseUrl.href.replace(/\/+$/, "")}/`,
    );
    const response = await fetchJson(fetchImpl, url, {
      method: "POST",
      headers: providerHeaders(body.clientIp),
      body: JSON.stringify({
        nationalId: body.nationalId,
        transId: body.transId,
        random: body.random,
      }),
    });
    const status = typeof response?.status === "string"
      ? response.status.toUpperCase()
      : "";
    if (!["WAITING", "COMPLETED", "REJECTED", "EXPIRED"].includes(status)) {
      throw new Error("invalid_nafath_status_response");
    }
    return { status: 200, body: { status } };
  }

  return async function handler(req, res) {
    if (req.method === "GET" && req.url === "/healthz") {
      try {
        getConfig();
        return json(res, 200, { ok: true });
      } catch {
        return json(res, 503, { ok: false });
      }
    }
    if (
      req.method === "POST" &&
      ["/nafath/start", "/nafath/status"].includes(req.url)
    ) {
      try {
        if (!isGatewayAuthorized(req)) {
          return json(res, 401, { error: "unauthorized" });
        }
        if (!req.headers["content-type"]?.toLowerCase().startsWith("application/json")) {
          return json(res, 415, { error: "unsupported_media_type" });
        }
        const body = await readBody(req);
        const result = req.url === "/nafath/start"
          ? await startNafath(body)
          : await pollNafath(body);
        return json(res, result.status, result.body);
      } catch (error) {
        const code = error instanceof Error ? error.message : "gateway_failed";
        if (code === "body_too_large") {
          return json(res, 413, { error: "payload_too_large" });
        }
        if (error instanceof SyntaxError) {
          return json(res, 400, { error: "invalid_json" });
        }
        console.error("Nafath gateway request failed:", code);
        return json(res, 502, { error: "nafath_gateway_unavailable" });
      }
    }
    if (req.method !== "POST" || req.url !== "/callback") {
      return json(res, 404, { error: "not_found" });
    }
    if (!req.headers["content-type"]?.toLowerCase().startsWith("application/json")) {
      return json(res, 415, { error: "unsupported_media_type" });
    }

    try {
      const body = await readBody(req);
      const result = await processCallback(body);
      return json(res, result.status, result.body);
    } catch (error) {
      const code = error instanceof Error ? error.message : "callback_failed";
      if (code === "body_too_large") {
        return json(res, 413, { error: "payload_too_large" });
      }
      if (error instanceof SyntaxError) {
        return json(res, 400, { error: "invalid_json" });
      }
      console.error("Nafath callback processing failed:", code);
      return json(res, 503, { error: "callback_unavailable" });
    }
  };
}

if (
  process.argv[1] &&
  fileURLToPath(import.meta.url) === resolve(process.argv[1])
) {
  const port = Number(process.env.PORT ?? "3000");
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("PORT must be a valid TCP port");
  }
  const server = createServer(createNafathCallbackHandler());
  server.listen(port, "0.0.0.0", () => {
    console.log(`Nafath callback server listening on port ${port}`);
  });
}
