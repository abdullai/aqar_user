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
        ? { message: data.message_ar ?? data.error ?? "Request failed" }
        : {}),
      statusCode: status,
    };
  }
  return new Response(JSON.stringify(result), {
    status,
    headers: { ...corsHeaders },
  });
}

function clean(value: unknown) {
  return String(value ?? "").trim();
}

function requestIp(req: Request) {
  const forwarded = clean(req.headers.get("cf-connecting-ip")) ||
    clean(req.headers.get("x-forwarded-for")).split(",")[0]?.trim() || "";
  if (forwarded.length > 45) return "";
  const ipv4 = forwarded.split(".");
  if (
    ipv4.length === 4 &&
    ipv4.every((part) => /^\d{1,3}$/.test(part) && Number(part) <= 255)
  ) return forwarded;
  return forwarded.includes(":") && /^[\da-f:]+$/i.test(forwarded)
    ? forwarded
    : "";
}

function configuration() {
  const supabaseUrl = clean(Deno.env.get("SUPABASE_URL"));
  const serviceRole = clean(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const anonKey = clean(Deno.env.get("SUPABASE_ANON_KEY"));
  const gatewayUrl = clean(Deno.env.get("NAFATH_GATEWAY_URL"));
  const gatewaySecret = clean(Deno.env.get("NAFATH_GATEWAY_SECRET"));
  if (!supabaseUrl || !serviceRole || !anonKey || !gatewayUrl ||
    gatewaySecret.length < 32) return null;

  try {
    const supabase = new URL(supabaseUrl);
    const gateway = new URL(gatewayUrl);
    if (supabase.protocol !== "https:" || gateway.protocol !== "https:") {
      return null;
    }
    return { supabase, serviceRole, anonKey, gateway, gatewaySecret };
  } catch {
    return null;
  }
}

function notConfigured(action: string) {
  return json({
    mode: "not_configured",
    error: "nafath_not_configured",
    message_ar: "خدمة نفاذ غير مهيأة بالكامل على الخادم.",
    message_en: "Nafath is not fully configured on the server.",
    action,
  }, 503);
}

async function requestJson(
  url: URL,
  init: RequestInit,
): Promise<{ response: Response; data: unknown }> {
  const response = await fetch(url, {
    ...init,
    redirect: "error",
    signal: init.signal ?? AbortSignal.timeout(15000),
  });
  const text = await response.text();
  let data: unknown = null;
  if (text.trim()) {
    try {
      data = JSON.parse(text);
    } catch {
      data = null;
    }
  }
  return { response, data };
}

async function restJson(
  config: NonNullable<ReturnType<typeof configuration>>,
  path: string,
  init: RequestInit = {},
) {
  const headers = new Headers(init.headers);
  headers.set("apikey", config.serviceRole);
  headers.set("Authorization", `Bearer ${config.serviceRole}`);
  if (init.body != null && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const { response, data } = await requestJson(
    new URL(path, config.supabase),
    { ...init, headers },
  );
  if (!response.ok) throw new Error(`supabase_${response.status}`);
  return data;
}

async function authJson(
  config: NonNullable<ReturnType<typeof configuration>>,
  path: string,
  apiKey: string,
  init: RequestInit = {},
) {
  const headers = new Headers(init.headers);
  headers.set("apikey", apiKey);
  headers.set("Authorization", `Bearer ${apiKey}`);
  if (init.body != null && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  const { response, data } = await requestJson(
    new URL(path, config.supabase),
    { ...init, headers },
  );
  if (!response.ok) throw new Error(`auth_${response.status}`);
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("invalid_auth_response");
  }
  return data as JsonMap;
}

async function gatewayJson(
  config: NonNullable<ReturnType<typeof configuration>>,
  path: string,
  body: JsonMap,
) {
  const { response, data } = await requestJson(
    new URL(path, `${config.gateway.href.replace(/\/+$/, "")}/`),
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${config.gatewaySecret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  const result = data && typeof data === "object" && !Array.isArray(data)
    ? data as JsonMap
    : {};
  if (!response.ok) {
    const error = clean(result.error);
    const errorCode = clean(result.error_code ?? result.errorCode);
    const failure = new Error(error || `gateway_${response.status}`);
    Object.assign(failure, { status: response.status, errorCode });
    throw failure;
  }
  return result;
}

function startError(error: unknown) {
  const failure = error as Error & { status?: number; errorCode?: string };
  if (failure.errorCode === "400-034-050") {
    return json({
      mode: "error",
      error: "nafath_request_already_active",
      error_code: failure.errorCode,
      message_ar: "لديك طلب نفاذ نشط بالفعل. أكمل الطلب الحالي قبل إعادة المحاولة.",
      message_en: "An active Nafath request already exists. Complete it before retrying.",
    }, 409);
  }
  return json({
    mode: "error",
    error: "nafath_request_unavailable",
    message_ar: "تعذر بدء طلب نفاذ. حاول مرة أخرى لاحقاً.",
    message_en: "Could not start Nafath. Try again later.",
  }, failure.status === 400 ? 400 : 502);
}

async function startNafath(
  config: NonNullable<ReturnType<typeof configuration>>,
  body: JsonMap,
  req: Request,
) {
  const nationalId = clean(body.national_id ?? body.nationalId ?? body.id);
  const flow = clean(body.flow || "login").toLowerCase();
  const locale = clean(body.locale || "ar").toLowerCase();
  const clientIp = requestIp(req);
  if (!/^[123456]\d{9}$/.test(nationalId)) {
    return json({
      mode: "error",
      error: "invalid_national_id",
      message_ar: "أدخل رقم هوية أو إقامة صحيحاً من 10 أرقام.",
      message_en: "Enter a valid 10-digit national or Iqama ID.",
    }, 400);
  }
  if (!clientIp) {
    return json({
      mode: "error",
      error: "client_ip_unavailable",
      message_ar: "تعذر تحديد عنوان اتصال الجهاز لبدء طلب نفاذ.",
      message_en: "Could not determine the device IP for the Nafath request.",
    }, 400);
  }
  if (flow !== "login" || !["ar", "en"].includes(locale)) {
    return json({ mode: "error", error: "invalid_request" }, 400);
  }

  const requestId = crypto.randomUUID();
  let provider: JsonMap;
  try {
    provider = await gatewayJson(config, "/nafath/start", {
      requestId,
      clientIp,
      nationalId,
      service: "Login",
      locale,
    });
  } catch (error) {
    return startError(error);
  }

  const transId = clean(provider.transId ?? provider.trans_id)
    .replace(/^\{|\}$/g, "")
    .toLowerCase();
  const random = clean(provider.random);
  if (
    !/^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$/i
      .test(transId) ||
    !/^\d{2}$/.test(random)
  ) {
    throw new Error("invalid_nafath_start_response");
  }

  const saved = await restJson(config, "/rest/v1/nafath_logins", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      id: requestId,
      trans_id: transId,
      random,
      national_id: nationalId,
      client_ip: clientIp,
      locale,
      flow,
      status: "WAITING",
      updated_at: new Date().toISOString(),
    }),
  });
  if (!Array.isArray(saved) || !saved[0]?.id) {
    throw new Error("nafath_request_not_saved");
  }

  return json({
    mode: "polling",
    request_id: requestId,
    trans_id: transId,
    random,
    status: "WAITING",
    message_ar: `افتح تطبيق نفاذ واختر الرقم ${random} لإكمال الدخول.`,
    message_en: `Open Nafath and choose number ${random} to continue.`,
  });
}

async function updateWaitingStatus(
  config: NonNullable<ReturnType<typeof configuration>>,
  requestId: string,
  status: string,
  errorCode?: string,
) {
  const query = new URLSearchParams({
    id: `eq.${requestId}`,
    status: "eq.WAITING",
  });
  await restJson(config, `/rest/v1/nafath_logins?${query}`, {
    method: "PATCH",
    body: JSON.stringify({
      status,
      error_code: errorCode ?? null,
      updated_at: new Date().toISOString(),
      ...(status === "EXPIRED" ? { completed_at: null } : {}),
      ...(status === "REJECTED" ? { rejected_at: new Date().toISOString() } : {}),
    }),
  });
}

async function issueLoginSession(
  config: NonNullable<ReturnType<typeof configuration>>,
  row: JsonMap,
  requestId: string,
) {
  const nationalId = clean(row.national_id);
  const profilesQuery = new URLSearchParams({
    select: "user_id",
    national_id: `eq.${nationalId}`,
    limit: "2",
  });
  const profiles = await restJson(
    config,
    `/rest/v1/users_profiles?${profilesQuery}`,
  );
  if (!Array.isArray(profiles) || profiles.length !== 1) {
    const profileCount = Array.isArray(profiles) ? profiles.length : 0;
    return json({
      mode: "error",
      status: "COMPLETED",
      error: profileCount ? "nafath_account_ambiguous" : "nafath_account_not_found",
      message_ar: profileCount
        ? "تعذر ربط الهوية بحساب واحد. تواصل مع الدعم."
        : "تم التحقق من الهوية، لكن لا يوجد حساب أقار مسجل بهذه الهوية. أنشئ حساباً أولاً.",
      message_en: profileCount
        ? "This identity is linked to multiple accounts. Contact support."
        : "Identity verified, but no Aqar account uses this ID. Register first.",
    }, profileCount ? 409 : 404);
  }

  const userId = clean((profiles[0] as JsonMap).user_id);
  if (!/^[0-9a-f-]{36}$/i.test(userId)) {
    throw new Error("invalid_profile_user_id");
  }
  const claimed = await restJson(
    config,
    "/rest/v1/rpc/claim_nafath_session",
    {
      method: "POST",
      body: JSON.stringify({ p_request_id: requestId }),
    },
  );
  if (clean(claimed).toLowerCase() !== userId.toLowerCase()) {
    return json({
      mode: "error",
      status: "COMPLETED",
      error: "nafath_session_already_issued",
      message_ar: "تم استخدام طلب نفاذ هذا. ابدأ طلباً جديداً لتسجيل الدخول.",
      message_en: "This Nafath request has already been used. Start a new login.",
    }, 409);
  }

  const userData = await authJson(
    config,
    `/auth/v1/admin/users/${encodeURIComponent(userId)}`,
    config.serviceRole,
  );
  const user = userData.user && typeof userData.user === "object"
    ? userData.user as JsonMap
    : userData;
  const email = clean(user.email);
  if (!email) throw new Error("nafath_account_has_no_email");

  const link = await authJson(
    config,
    "/auth/v1/admin/generate_link",
    config.serviceRole,
    {
      method: "POST",
      body: JSON.stringify({ type: "magiclink", email }),
    },
  );
  const tokenHash = clean(link.hashed_token ?? link.hashedToken);
  if (!tokenHash) throw new Error("nafath_login_link_not_generated");

  const session = await authJson(
    config,
    "/auth/v1/verify",
    config.anonKey,
    {
      method: "POST",
      body: JSON.stringify({ type: "magiclink", token_hash: tokenHash }),
    },
  );
  const sessionUser = session.user && typeof session.user === "object"
    ? session.user as JsonMap
    : {};
  const accessToken = clean(session.access_token);
  const refreshToken = clean(session.refresh_token);
  if (!accessToken || !refreshToken || clean(sessionUser.id) !== userId) {
    throw new Error("nafath_auth_session_not_created");
  }

  return json({
    mode: "redirect",
    status: "COMPLETED",
    request_id: requestId,
    access_token: accessToken,
    refresh_token: refreshToken,
    message_ar: "تم التحقق وتسجيل الدخول بنجاح.",
    message_en: "Identity verified and signed in successfully.",
  });
}

async function pollNafath(
  config: NonNullable<ReturnType<typeof configuration>>,
  body: JsonMap,
) {
  const requestId = clean(body.request_id);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(requestId)) {
    return json({ mode: "error", error: "missing_request_id" }, 400);
  }

  const query = new URLSearchParams({
    select: "id,trans_id,national_id,random,status,created_at,client_ip,auth_user_id",
    id: `eq.${requestId}`,
    limit: "1",
  });
  const rows = await restJson(config, `/rest/v1/nafath_logins?${query}`);
  const row = Array.isArray(rows) ? rows[0] as JsonMap | undefined : undefined;
  if (!row) return json({ mode: "error", error: "request_not_found" }, 404);

  const status = clean(row.status).toUpperCase();
  if (status === "REJECTED" || status === "EXPIRED") {
    return json({
      mode: "error",
      status,
      request_id: requestId,
      message_ar: status === "EXPIRED"
        ? "انتهت مهلة طلب نفاذ. أعد المحاولة."
        : "تم رفض طلب نفاذ.",
      message_en: status === "EXPIRED"
        ? "The Nafath request expired. Try again."
        : "The Nafath request was rejected.",
    }, status === "EXPIRED" ? 410 : 409);
  }
  if (status !== "WAITING" && status !== "COMPLETED") {
    return json({ mode: "error", error: "invalid_request_status" }, 409);
  }

  const createdAt = Date.parse(clean(row.created_at));
  if (
    !Number.isFinite(createdAt) ||
    createdAt > Date.now() + 60_000 ||
    Date.now() - createdAt > 5 * 60 * 1000
  ) {
    await updateWaitingStatus(config, requestId, "EXPIRED");
    return json({ mode: "error", status: "EXPIRED" }, 410);
  }

  if (status === "COMPLETED") {
    return await issueLoginSession(config, row, requestId);
  }

  let provider: JsonMap;
  try {
    provider = await gatewayJson(config, "/nafath/status", {
      clientIp: clean(row.client_ip),
      nationalId: clean(row.national_id),
      transId: clean(row.trans_id),
      random: clean(row.random),
    });
  } catch {
    return json({
      mode: "error",
      error: "nafath_status_unavailable",
      message_ar: "تعذر الاستعلام عن حالة نفاذ.",
      message_en: "Could not retrieve Nafath status.",
    }, 502);
  }

  const providerStatus = clean(provider.status).toUpperCase();
  if (!["WAITING", "COMPLETED", "REJECTED", "EXPIRED"].includes(providerStatus)) {
    return json({ mode: "error", error: "invalid_nafath_status" }, 502);
  }
  if (providerStatus === "REJECTED" || providerStatus === "EXPIRED") {
    await updateWaitingStatus(config, requestId, providerStatus);
    return json({
      mode: "error",
      status: providerStatus,
      message_ar: providerStatus === "EXPIRED"
        ? "انتهت مهلة طلب نفاذ. أعد المحاولة."
        : "تم رفض طلب نفاذ.",
      message_en: providerStatus === "EXPIRED"
        ? "The Nafath request expired. Try again."
        : "The Nafath request was rejected.",
    }, providerStatus === "EXPIRED" ? 410 : 409);
  }

  if (providerStatus === "COMPLETED") {
    const callbackRows = await restJson(
      config,
      `/rest/v1/nafath_logins?${new URLSearchParams({
        select: "id,status,auth_user_id",
        id: `eq.${requestId}`,
        limit: "1",
      })}`,
    );
    const callbackRow = Array.isArray(callbackRows)
      ? callbackRows[0] as JsonMap | undefined
      : undefined;
    if (clean(callbackRow?.status).toUpperCase() === "COMPLETED") {
      return await issueLoginSession(config, { ...row, ...callbackRow }, requestId);
    }
  }

  return json({
    mode: "polling",
    request_id: requestId,
    random: clean(row.random),
    status: "WAITING",
    message_ar: `بانتظار اكتمال تحقق نفاذ. اختر الرقم ${clean(row.random)} في التطبيق.`,
    message_en: `Waiting for Nafath verification. Choose ${clean(row.random)} in the app.`,
  });
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }
    if (req.method !== "POST") {
      return json({ mode: "error", error: "method_not_allowed" }, 405);
    }

    const config = configuration();
    if (!config) return notConfigured("request");

    let body: JsonMap;
    try {
      const parsed: unknown = await req.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return json({ mode: "error", error: "invalid_json" }, 400);
      }
      body = parsed as JsonMap;
    } catch {
      return json({ mode: "error", error: "invalid_json" }, 400);
    }

    const action = clean(body.action || "start");
    if (action === "start") return await startNafath(config, body, req);
    if (action === "poll") return await pollNafath(config, body);
    return json({ mode: "error", error: "invalid_action" }, 400);
  } catch (error) {
    console.error(
      "Nafath session failed:",
      error instanceof Error ? error.message : "unknown",
    );
    return json({
      mode: "error",
      error: "nafath_server_error",
      message_ar: "تعذر إكمال طلب نفاذ بسبب خطأ في الخادم.",
      message_en: "The Nafath request could not be completed.",
    }, 500);
  }
});
