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
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders },
  });
}

function text(body: string, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": corsHeaders["Access-Control-Allow-Headers"],
      "Access-Control-Allow-Methods": corsHeaders["Access-Control-Allow-Methods"],
      "Content-Type": "text/plain; charset=utf-8",
    },
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

function isMissingOrPlaceholder(value: string | undefined) {
  const v = clean(value);
  const lower = v.toLowerCase();
  return !v ||
    v === "..." ||
    lower === "placeholder" ||
    lower === "your-subdomain" ||
    lower === "your-api-key" ||
    lower === "default_subdomain" ||
    lower === "your_api_key";
}

function nafathUnavailable(action: string, flow: string) {
  return json({
    mode: "not_configured",
    message_ar:
      "خدمة الدخول عبر نفاذ قيد التفعيل حالياً. الرجاء استخدام تسجيل الدخول برقم الهوية وكلمة المرور.",
    message_en:
      "Nafath sign-in is being activated. Please use ID/password sign-in for now.",
    action,
    flow,
  });
}

function env() {
  const supabaseUrl = clean(Deno.env.get("SUPABASE_URL"));
  const serviceRole = clean(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const urlBase = clean(
    Deno.env.get("NAFATH_URL_BASE") ?? Deno.env.get("NAFATH_BASE_URL"),
  );
  const apiKey = clean(Deno.env.get("NAFATH_API_KEY"));
  const callbackUrl = clean(Deno.env.get("NAFATH_CALLBACK_URL")) ||
    `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/nafath_session`;
  const redirectTo = clean(Deno.env.get("NAFATH_AUTH_REDIRECT_TO")) ||
    clean(Deno.env.get("SITE_URL")) ||
    "https://eaqar-mawthuq.web.app";
  return { supabaseUrl, serviceRole, urlBase, apiKey, callbackUrl, redirectTo };
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
    throw new Error(
      `rest_${res.status}: ${typeof data === "string" ? data : JSON.stringify(data)}`,
    );
  }
  return data;
}

function decodeJwtPayload(token: string): JsonMap {
  const part = token.split(".")[1] ?? "";
  if (!part) return {};
  const base64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
  return JSON.parse(atob(padded));
}

async function findProfileByNationalId(nationalId: string): Promise<JsonMap | null> {
  const q = new URLSearchParams();
  q.set("select", "user_id,email,username");
  q.set("username", `eq.${nationalId}`);
  q.set("limit", "1");
  const rows = await restJson(`/rest/v1/users_profiles?${q.toString()}`, {
    headers: { Accept: "application/json" },
  });
  if (Array.isArray(rows) && rows.length > 0) {
    return rows[0] as JsonMap;
  }
  return null;
}

async function generateMagicLink(email: string): Promise<string> {
  const { redirectTo } = env();
  const data = await restJson("/auth/v1/admin/generate_link", {
    method: "POST",
    body: JSON.stringify({
      type: "magiclink",
      email,
      options: { redirect_to: redirectTo },
    }),
  }) as JsonMap;
  return clean(data.action_link);
}

async function startNafath(body: JsonMap) {
  const enabled = Deno.env.get("NAFATH_INTEGRATION_ENABLED") === "true";
  const flow = clean(body.flow) || "login";
  const locale = clean(body.locale) || "ar";
  const nationalId = clean(body.national_id ?? body.nationalId ?? body.id)
    .replace(/\D/g, "");
  const { urlBase, apiKey, callbackUrl } = env();

  if (!enabled) return nafathUnavailable("start", flow);
  if (isMissingOrPlaceholder(urlBase) || isMissingOrPlaceholder(apiKey)) {
    return nafathUnavailable("start", flow);
  }
  if (!["login", "register"].includes(flow)) {
    return json({ mode: "error", error: "invalid_flow" }, 400);
  }
  if (!["ar", "en"].includes(locale)) {
    return json({ mode: "error", error: "invalid_locale" }, 400);
  }
  if (!/^\d{10}$/.test(nationalId)) {
    return json({
      mode: "error",
      error: "invalid_national_id",
      message_ar: "أدخل رقم هوية/إقامة صحيح من 10 أرقام قبل الدخول عبر نفاذ.",
      message_en: "Enter a valid 10-digit ID before using Nafath.",
    }, 400);
  }

  const url = `https://${urlBase}.semati.sa/nafath/api/v1/client/authorize/`;
  const nafathRes = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `apikey ${apiKey}`,
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    body: JSON.stringify({
      id: nationalId,
      action: "SpRequest",
      service: "Login",
      callbackUrl,
    }),
  });
  const raw = await nafathRes.text();
  let data: JsonMap = {};
  try {
    data = JSON.parse(raw);
  } catch {
    data = { raw };
  }
  if (!nafathRes.ok) {
    return json({
      mode: "error",
      error: data.error ?? data.message ?? raw,
      message_ar: "تعذر بدء طلب نفاذ. تحقق من إعدادات NAFATH_URL_BASE و NAFATH_API_KEY.",
      message_en: "Could not start Nafath request. Check server Nafath settings.",
    }, nafathRes.status);
  }

  const transId = clean(data.transId ?? data.trans_id);
  const random = clean(data.random);
  if (!transId || !random) {
    return json({
      mode: "error",
      error: "invalid_nafath_response",
      message_ar: "استجابة نفاذ لا تحتوي رقم الطلب أو رقم التحقق.",
      message_en: "Nafath response did not include transaction/random.",
    }, 502);
  }

  await restJson("/rest/v1/nafath_logins", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({
      trans_id: transId,
      random,
      national_id: nationalId,
      flow,
      status: "PENDING",
      updated_at: new Date().toISOString(),
    }),
  });

  return json({
    mode: "polling",
    request_id: transId,
    random,
    status: "PENDING",
    message_ar:
      `افتح تطبيق نفاذ واختر الرقم ${random} لإكمال تسجيل الدخول. سيتم التحقق تلقائياً.`,
    message_en:
      `Open Nafath app and choose number ${random} to complete sign-in. We will verify automatically.`,
  });
}

async function handleCallback(body: JsonMap) {
  const token = clean(body.response ?? body.token ?? body.jwt);
  const payload = token ? decodeJwtPayload(token) : body;
  const transId = clean(payload.transId ?? payload.trans_id);
  const status = clean(payload.status).toUpperCase();
  if (!transId) return text("missing transId", 400);

  const patch: JsonMap = {
    status: status || "UNKNOWN",
    callback_payload: payload,
    updated_at: new Date().toISOString(),
  };
  if (status === "COMPLETED") patch.completed_at = new Date().toISOString();
  if (status === "REJECTED") patch.rejected_at = new Date().toISOString();

  await restJson(`/rest/v1/nafath_logins?trans_id=eq.${encodeURIComponent(transId)}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify(patch),
  });

  return text("TRS", 200);
}

async function pollNafath(body: JsonMap) {
  const requestId = clean(body.request_id ?? body.trans_id);
  if (!requestId) {
    return json({ mode: "error", error: "missing_request_id" }, 400);
  }

  const q = new URLSearchParams();
  q.set("select", "*");
  q.set("trans_id", `eq.${requestId}`);
  q.set("limit", "1");
  const rows = await restJson(`/rest/v1/nafath_logins?${q.toString()}`) as unknown[];
  const row = Array.isArray(rows) && rows.length > 0 ? rows[0] as JsonMap : null;
  if (!row) {
    return json({ mode: "error", error: "request_not_found" }, 404);
  }

  const status = clean(row.status).toUpperCase();
  if (status === "REJECTED") {
    return json({
      mode: "error",
      status,
      request_id: requestId,
      message_ar: "تم رفض طلب نفاذ أو انتهت المهلة.",
      message_en: "Nafath request was rejected or expired.",
    });
  }

  if (status === "COMPLETED") {
    const nationalId = clean(row.national_id);
    const profile = await findProfileByNationalId(nationalId);
    const email = clean(profile?.email);
    if (profile?.user_id) {
      await restJson(`/rest/v1/nafath_logins?trans_id=eq.${encodeURIComponent(requestId)}`, {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          auth_user_id: profile.user_id,
          updated_at: new Date().toISOString(),
        }),
      });
    }
    if (email) {
      const link = await generateMagicLink(email);
      await restJson(`/rest/v1/nafath_logins?trans_id=eq.${encodeURIComponent(requestId)}`, {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify({
          auth_link: link,
          updated_at: new Date().toISOString(),
        }),
      });
      return json({
        mode: "redirect",
        status,
        request_id: requestId,
        authorization_url: link,
        message_ar: "تم التحقق عبر نفاذ. جاري إكمال تسجيل الدخول.",
        message_en: "Nafath verified. Completing sign-in.",
      });
    }
    return json({
      mode: "error",
      status,
      request_id: requestId,
      message_ar:
        "تم التحقق عبر نفاذ، لكن لا يوجد بريد إلكتروني مرتبط بالحساب لإنشاء جلسة Supabase تلقائية.",
      message_en:
        "Nafath verified, but this account has no email for automatic Supabase sign-in.",
    });
  }

  return json({
    mode: "polling",
    status: status || "PENDING",
    request_id: requestId,
    random: row.random,
    message_ar: `بانتظار تأكيد نفاذ. اختر الرقم ${clean(row.random)} في تطبيق نفاذ.`,
    message_en: `Waiting for Nafath confirmation. Choose ${clean(row.random)} in Nafath app.`,
  });
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") return corsPreflight();
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

    const body = await req.json().catch(() => ({})) as JsonMap;
    const action = clean(body.action || (body.response ? "callback" : "start"));
    if (action === "callback") return await handleCallback(body);
    if (action === "start") return await startNafath(body);
    if (action === "poll") return await pollNafath(body);
    return json({ mode: "error", error: "invalid_action" }, 400);
  } catch (e) {
    return json({
      mode: "error",
      error: String(e),
      message_ar: "خطأ في الخادم أثناء معالجة طلب نفاذ.",
      message_en: "Server error in nafath_session.",
    }, 500);
  }
});
