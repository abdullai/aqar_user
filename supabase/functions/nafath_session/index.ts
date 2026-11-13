import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-authorization, prefer, accept-profile, content-profile",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
  "Content-Type": "application/json; charset=utf-8",
};

type JsonMap = Record<string, unknown>;

function json(body: unknown, status = 200) {
  let result = body;
  if (body && typeof body === "object" && !Array.isArray(body)) {
    const data = body as JsonMap;
    result = {
      ...data,
      ...(status >= 400 && !data.message
        ? { message: data.message_en ?? data.error ?? "Request failed" }
        : {}),
      statusCode: status,
    };
  }
  return new Response(JSON.stringify(result), {
    status,
    headers: { ...corsHeaders },
  });
}

function corsPreflight() {
  return new Response(null, {
    status: 204,
    headers: { ...corsHeaders },
  });
}

function clean(value: unknown) {
  return String(value ?? "").trim();
}

function clientIpFromRequest(req: Request) {
  const cloudflareIp = clean(req.headers.get("cf-connecting-ip"));
  const forwardedIp = clean(req.headers.get("x-forwarded-for"))
    .split(",")[0]
    ?.trim() ?? "";
  const value = cloudflareIp || forwardedIp;
  if (!value || value.length > 45) return "";
  const octets = value.split(".");
  if (
    octets.length === 4 &&
    octets.every((octet) => /^\d{1,3}$/.test(octet) && Number(octet) <= 255)
  ) return value;
  return value.includes(":") && /^[\da-f:]+$/i.test(value) ? value : "";
}

function isMissingOrPlaceholder(value: string | undefined) {
  const v = clean(value);
  const lower = v.toLowerCase();
  return !v ||
    v === "..." ||
    lower === "placeholder" ||
    lower.startsWith("your_") ||
    lower.startsWith("your-") ||
    lower === "your-subdomain" ||
    lower === "your-api-key" ||
    lower === "default_subdomain" ||
    lower === "your_api_key";
}

function nafathUnavailable(action: string, flow: string) {
  return json({
    mode: "not_configured",
    error: "nafath_not_configured",
    message_ar:
      "خدمة الدخول عبر نفاذ قيد التفعيل حالياً. الرجاء استخدام تسجيل الدخول برقم الهوية وكلمة المرور.",
    message_en:
      "Nafath sign-in is being activated. Please use ID/password sign-in for now.",
    action,
    flow,
  }, 503);
}

function env() {
  const supabaseUrl = clean(Deno.env.get("SUPABASE_URL"));
  const serviceRole = clean(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const gatewayUrl = clean(Deno.env.get("NAFATH_GATEWAY_URL"));
  const gatewaySecret = clean(Deno.env.get("NAFATH_GATEWAY_SECRET"));
  return { supabaseUrl, serviceRole, gatewayUrl, gatewaySecret };
}

function nafathConfig() {
  const { gatewayUrl, gatewaySecret } = env();
  if (
    isMissingOrPlaceholder(gatewayUrl) ||
    isMissingOrPlaceholder(gatewaySecret) ||
    gatewaySecret.length < 32
  ) return null;
  let url: URL;
  try {
    url = new URL(gatewayUrl);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;

  return {
    gatewayUrl: url,
    headers: {
      "Authorization": `Bearer ${gatewaySecret}`,
      "Content-Type": "application/json; charset=utf-8",
    },
  };
}

async function rest(
  path: string,
  init: RequestInit = {},
): Promise<Response> {
  const { supabaseUrl, serviceRole } = env();
  if (!supabaseUrl || !serviceRole) {
    throw new Error("missing_supabase_service_config");
  }
  const headers = new Headers(init.headers);
  headers.set("apikey", serviceRole);
  headers.set("Authorization", `Bearer ${serviceRole}`);
  if (!headers.has("Content-Type") && init.body != null) {
    headers.set("Content-Type", "application/json");
  }
  return fetch(`${supabaseUrl.replace(/\/+$/, "")}${path}`, {
    ...init,
    headers,
    redirect: "error",
    signal: init.signal ?? AbortSignal.timeout(15000),
  });
}

async function restJson(path: string, init: RequestInit = {}) {
  const res = await rest(path, init);
  const bodyText = await res.text();
  let data: unknown = null;
  if (bodyText.trim().length > 0) {
    try {
      data = JSON.parse(bodyText);
    } catch {
      data = bodyText;
    }
  }
  if (!res.ok) {
    throw new Error(`rest_${res.status}`);
  }
  return data;
}

async function startNafath(body: JsonMap, req: Request) {
  const flow = clean(body.flow) || "login";
  const locale = clean(body.locale) || "ar";
  const nationalId = clean(body.national_id ?? body.nationalId ?? body.id);
  const clientIp = clientIpFromRequest(req);
  const config = nafathConfig();

  if (!config) return nafathUnavailable("start", flow);
  if (!clientIp) {
    return json({
      mode: "error",
      error: "client_ip_unavailable",
      message_ar: "تعذر التحقق من عنوان اتصال الجهاز لبدء طلب نفاذ.",
      message_en: "Could not determine the device IP for the Nafath request.",
    }, 400);
  }
  if (!["login", "register"].includes(flow)) {
    return json({ mode: "error", error: "invalid_flow" }, 400);
  }
  if (!["ar", "en"].includes(locale)) {
    return json({ mode: "error", error: "invalid_locale" }, 400);
  }
  if (!/^[123456]\d{9}$/.test(nationalId)) {
    return json({
      mode: "error",
      error: "invalid_national_id",
      message_ar: "أدخل رقم هوية/إقامة صحيح من 10 أرقام قبل الدخول عبر نفاذ.",
      message_en: "Enter a valid 10-digit ID before using Nafath.",
    }, 400);
  }

  const providerRequestId = crypto.randomUUID();
  const gatewayUrl = new URL("/nafath/start", config.gatewayUrl);
  let nafathRes: Response;
  try {
    nafathRes = await fetch(gatewayUrl, {
      method: "POST",
      headers: config.headers,
      redirect: "error",
      signal: AbortSignal.timeout(15000),
      body: JSON.stringify({
        nationalId,
        service: flow === "register" ? "Register" : "Login",
        locale,
        requestId: providerRequestId,
        clientIp,
      }),
    });
  } catch {
    return json({ mode: "error", error: "nafath_request_unavailable" }, 502);
  }
  if (!nafathRes.ok) {
    return json({
      mode: "error",
      error: "nafath_request_failed",
      message_ar: "تعذر بدء طلب نفاذ. تحقق من بيانات الاتصال.",
      message_en: "Could not start Nafath request. Check connection details.",
    }, 502);
  }
  let data: JsonMap;
  try {
    const parsed: unknown = await nafathRes.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return json({ mode: "error", error: "invalid_nafath_response" }, 502);
    }
    data = parsed as JsonMap;
  } catch {
    return json({ mode: "error", error: "invalid_nafath_response" }, 502);
  }

  const transId = clean(data.transId ?? data.trans_id);
  const random = clean(data.random);
  const uuid = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
  if (!new RegExp(`^(?:${uuid}|\\{${uuid}\\})$`, "i").test(transId) || !/^\d{2}$/.test(random)) {
    return json({
      mode: "error",
      error: "invalid_nafath_response",
      message_ar: "استجابة نفاذ لا تحتوي رقم الطلب أو رقم التحقق.",
      message_en: "Nafath response did not include transaction/random.",
    }, 502);
  }

  const rows = await restJson("/rest/v1/nafath_logins", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      id: providerRequestId,
      trans_id: transId,
      random,
      national_id: nationalId,
      client_ip: clientIp,
      flow,
      status: "WAITING",
      updated_at: new Date().toISOString(),
    }),
  });
  const row = Array.isArray(rows) ? rows[0] as JsonMap | undefined : undefined;
  const requestId = clean(row?.id);
  if (!requestId) throw new Error("nafath_request_not_saved");

  return json({
    mode: "polling",
    request_id: requestId,
    random,
    status: "WAITING",
    message_ar:
      `افتح تطبيق نفاذ واختر الرقم ${random} لإكمال تسجيل الدخول. سيتم التحقق تلقائياً.`,
    message_en:
      `Open Nafath app and choose number ${random} to complete sign-in. We will verify automatically.`,
  });
}

async function pollNafath(body: JsonMap) {
  const requestId = clean(body.request_id);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestId)) {
    return json({ mode: "error", error: "missing_request_id" }, 400);
  }

  const config = nafathConfig();
  if (!config) return nafathUnavailable("poll", "login");

  const q = new URLSearchParams();
  q.set("select", "id,trans_id,national_id,random,status,created_at,client_ip");
  q.set("id", `eq.${requestId}`);
  q.set("limit", "1");
  const rows = await restJson(`/rest/v1/nafath_logins?${q.toString()}`) as unknown[];
  const row = Array.isArray(rows) && rows.length > 0 ? rows[0] as JsonMap : null;
  if (!row) {
    return json({ mode: "error", error: "request_not_found" }, 404);
  }

  const savedStatus = clean(row.status).toUpperCase();
  if (savedStatus === "COMPLETED") {
    return json({
      mode: "not_configured",
      status: "COMPLETED",
      request_id: requestId,
      error: "nafath_auth_session_not_configured",
      message_ar:
        "تم التحقق من نفاذ، لكن لم يُفعّل ربط التحقق بجلسة حساب التطبيق بعد.",
      message_en:
        "Nafath verified the identity, but the application account session is not configured yet.",
    }, 503);
  }
  if (savedStatus === "REJECTED" || savedStatus === "EXPIRED") {
    return json({
      mode: "error",
      status: savedStatus,
      request_id: requestId,
      error: `nafath_${savedStatus.toLowerCase()}`,
    }, savedStatus === "EXPIRED" ? 410 : 409);
  }
  if (savedStatus !== "WAITING") {
    return json({ mode: "error", error: "request_already_used" }, 409);
  }
  const createdAt = Date.parse(clean(row.created_at));
  if (
    !Number.isFinite(createdAt) ||
    createdAt > Date.now() + 60 * 1000 ||
    Date.now() - createdAt > 5 * 60 * 1000
  ) {
    return json({ mode: "error", status: "EXPIRED" }, 410);
  }

  let providerResponse: Response;
  try {
    providerResponse = await fetch(new URL("/nafath/status", config.gatewayUrl), {
      method: "POST",
      headers: config.headers,
      redirect: "error",
      signal: AbortSignal.timeout(15000),
      body: JSON.stringify({
        nationalId: clean(row.national_id),
        transId: clean(row.trans_id),
        random: clean(row.random),
        clientIp: clean(row.client_ip),
      }),
    });
  } catch {
    return json({ mode: "error", error: "nafath_status_unavailable" }, 502);
  }
  if (!providerResponse.ok) {
    return json({ mode: "error", error: "nafath_status_unavailable" }, 502);
  }
  let providerData: JsonMap;
  try {
    const parsed: unknown = await providerResponse.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return json({ mode: "error", error: "invalid_nafath_status" }, 502);
    }
    providerData = parsed as JsonMap;
  } catch {
    return json({ mode: "error", error: "invalid_nafath_status" }, 502);
  }
  const status = clean(providerData.status).toUpperCase();
  if (!["WAITING", "REJECTED", "EXPIRED", "COMPLETED"].includes(status)) {
    return json({ mode: "error", error: "invalid_nafath_status" }, 502);
  }

  // حالات الرفض أو انتهاء المهلة
  if (status === "REJECTED" || status === "EXPIRED") {
    return json({
      mode: "error",
      status,
      request_id: requestId,
      message_ar: "تم رفض طلب نفاذ أو انتهت المهلة. حاول مرة أخرى.",
      message_en: "Nafath request was rejected or expired. Try again.",
    }, status === "EXPIRED" ? 410 : 409);
  }

  if (status === "COMPLETED") {
    return json({
      mode: "not_configured",
      status: "COMPLETED",
      request_id: requestId,
      error: "nafath_auth_session_not_configured",
      message_ar:
        "تم التحقق من نفاذ، لكن لم يُفعّل ربط التحقق بجلسة حساب التطبيق بعد.",
      message_en:
        "Nafath verified the identity, but the application account session is not configured yet.",
    }, 503);
  }

  // حالة الانتظار: لا تزال الطلب معلقة
  return json({
    mode: "polling",
    status: status || "WAITING",
    request_id: requestId,
    random: row.random,
    message_ar: `⏳ بانتظار تأكيد نفاذ... اختر الرقم ${clean(row.random)} في التطبيق.`,
    message_en: `⏳ Waiting for Nafath confirmation. Choose ${clean(row.random)} in the app.`,
  });
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return corsPreflight();
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    let body: JsonMap;
    try {
      const parsed: unknown = await req.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return json({ mode: "error", error: "invalid_body" }, 400);
      }
      body = parsed as JsonMap;
    } catch {
      return json({ mode: "error", error: "invalid_json" }, 400);
    }
    const action = clean(body.action || (body.requestId ? "callback" : "start"));
    if (action === "callback") {
      return await pollNafath({ request_id: body.requestId ?? body.request_id });
    }
    if (action === "start") return await startNafath(body, req);
    if (action === "poll") return await pollNafath(body);
    return json({ mode: "error", error: "invalid_action" }, 400);
  } catch (e) {
    console.error("Error processing Nafath request:", e instanceof Error ? e.name : "unknown");
    return json({
      mode: "error",
      error: "nafath_server_error",
      message_ar: "خطأ في الخادم أثناء معالجة طلب نفاذ.",
      message_en: "Server error in nafath_session.",
    }, 500);
  }
});
