// deno-lint-ignore-file no-explicit-any
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

// =====================
// Types
// =====================
type TriggerBody = {
  record?: {
    conversation_id?: string;
    sender_id?: string;
    receiver_id?: string;
    content?: string;
    kind?: string;
    user_id?: string;
    property_id?: string;
    id?: string;
    status?: string;
    username?: string;
    title?: string;
    body?: string;
    type?: string;
    data?: Record<string, unknown>;
  };
  type?: string;
  table?: string;
  schema?: string;
};

type ManualBody = {
  tokens?: string[];
  title?: string;
  body?: string;
  data?: Record<string, string>;
};

// =====================
// Helpers
// =====================
function json(res: any, status = 200) {
  return new Response(JSON.stringify(res), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

function base64url(input: string) {
  return btoa(input)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function asStringData(data: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(data)) {
    if (v === undefined || v === null) continue;
    out[k] = String(v);
  }
  return out;
}

/** `in_app_notifications.data` قد يكون jsonb أو نص JSON من بعض قنوات الـ webhook */
function inAppNotificationDataObject(
  record: Record<string, unknown>,
): Record<string, unknown> {
  const v = record["data"];
  if (v && typeof v === "object" && !Array.isArray(v)) {
    return v as Record<string, unknown>;
  }
  if (typeof v === "string" && v.trim()) {
    try {
      const d = JSON.parse(v);
      if (d && typeof d === "object" && !Array.isArray(d)) {
        return d as Record<string, unknown>;
      }
    } catch {
      /* ignore */
    }
  }
  return {};
}

// =====================
// Firebase JWT helpers
// =====================
async function signJwt(privateKeyPem: string, header: any, payload: any) {
  const enc = new TextEncoder();
  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const toSign = `${headerB64}.${payloadB64}`;

  const keyData = privateKeyPem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const binaryDer = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    enc.encode(toSign),
  );

  const sigB64 = base64url(String.fromCharCode(...new Uint8Array(sig)));
  return `${toSign}.${sigB64}`;
}

async function getAccessToken() {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
  const privateKeyB64 = Deno.env.get("FIREBASE_PRIVATE_KEY_B64") ?? "";

  if (!projectId || !clientEmail || !privateKeyB64) {
    throw new Error(
      `Missing Firebase env secrets: projectId=${!!projectId}, clientEmail=${!!clientEmail}, privateKeyB64=${!!privateKeyB64}`,
    );
  }

  const privateKeyPem =
    "-----BEGIN PRIVATE KEY-----\n" +
    privateKeyB64.replace(/(.{64})/g, "$1\n") +
    "\n-----END PRIVATE KEY-----\n";

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const jwt = await signJwt(privateKeyPem, header, payload);

  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const j = await r.json().catch(() => ({}));
  if (!r.ok) {
    throw new Error(`Token error: status=${r.status} body=${JSON.stringify(j)}`);
  }

  if (!j?.access_token) {
    throw new Error(
      `Token error: missing access_token body=${JSON.stringify(j)}`,
    );
  }

  return j.access_token as string;
}

// =====================
// FCM sender
// =====================
async function sendToToken(
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data?: Record<string, string>,
) {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const kind = (data?.kind ?? "property").toString();
  const channelId =
    kind === "support"
      ? "chat_support"
      : kind === "reservation"
      ? "chat_reservation"
      : kind === "workflow"
      ? "workflow_channel"
      : "chat_property";

  const msg = {
    message: {
      token,
      notification: { title, body },
      data: data ?? {},
      android: {
        priority: "HIGH",
        notification: { channel_id: channelId },
      },
      apns: {
        headers: { "apns-priority": "10" },
        payload: {
          aps: {
            alert: { title, body },
            sound: "default",
          },
        },
      },
    },
  };

  const r = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(msg),
  });

  const text = await r.text().catch(() => "");
  let j: any = {};
  try {
    j = text ? JSON.parse(text) : {};
  } catch {
    j = { raw: text };
  }

  return { ok: r.ok, status: r.status, body: j };
}

function getSupabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("SB_URL") ?? "";

  const serviceKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SB_SERVICE_ROLE_KEY") ??
    "";

  if (!url || !serviceKey) {
    throw new Error(
      `Missing Supabase env: url=${!!url}, serviceKey=${!!serviceKey}`,
    );
  }

  return createClient(url, serviceKey, {
    auth: { persistSession: false },
  });
}

async function deliverTokens(
  accessToken: string,
  tokens: string[],
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const results: any[] = [];
  for (const t of tokens) {
    results.push(await sendToToken(accessToken, t, title, body, data));
  }
  return results;
}

async function tokensForUser(userId: string): Promise<string[]> {
  const sb = getSupabaseAdmin();
  const { data: rows, error } = await sb
    .from("user_push_tokens")
    .select("fcm_token")
    .eq("user_id", userId);

  if (error) {
    throw new Error(`user_push_tokens read error: ${error.message}`);
  }

  return (rows ?? [])
    .map((r: any) => (r?.fcm_token ?? "").toString().trim())
    .filter((t) => t.length > 0);
}

// =====================
// Reservation (webhook: INSERT reservations)
// =====================
async function handleReservationInsert(rec: any) {
  const propertyId = (rec?.property_id ?? "").toString().trim();
  const reserverId = (rec?.user_id ?? "").toString().trim();
  const reservationId = (rec?.id ?? "").toString().trim();

  if (!propertyId) {
    return json({ ok: true, sent: 0, reason: "no property_id" });
  }

  const sb = getSupabaseAdmin();
  const { data: prop, error } = await sb
    .from("properties")
    .select("owner_id, published_by_marketer_id, title")
    .eq("id", propertyId)
    .maybeSingle();

  if (error) {
    throw new Error(`properties read: ${error.message}`);
  }
  if (!prop) {
    return json({ ok: true, sent: 0, reason: "property_not_found" });
  }

  const ownerId = (prop.owner_id ?? "").toString().trim();
  const marketerId = (prop.published_by_marketer_id ?? "").toString().trim();

  const targets = new Set<string>();
  if (ownerId) targets.add(ownerId);
  if (marketerId) targets.add(marketerId);
  if (reserverId) targets.delete(reserverId);

  const accessToken = await getAccessToken();
  const title = "حجز جديد";
  const shortTitle = (prop.title ?? "").toString().trim();
  const body = shortTitle
    ? `تم حجز إعلان: ${shortTitle.length > 80 ? shortTitle.slice(0, 80) + "…" : shortTitle}`
    : "تم حجز أحد إعلاناتك. اضغط للعرض.";

  let total = 0;
  const allResults: any[] = [];

  for (const uid of targets) {
    const tokens = await tokensForUser(uid);
    if (!tokens.length) continue;
    const data = asStringData({
      kind: "reservation",
      property_id: propertyId,
      reservation_id: reservationId,
      title_ar: title,
      body_ar: body,
    });
    const results = await deliverTokens(accessToken, tokens, title, body, data);
    allResults.push(...results);
    total += results.length;
  }

  return json({
    ok: true,
    mode: "reservation_insert",
    sent: total,
    results: allResults,
  });
}

// =====================
// HTTP Handler
// =====================
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("", {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  if (req.method !== "POST") {
    return json({ ok: false, error: "POST only" }, 405);
  }

  try {
    const raw = await req.json().catch(() => ({}));

    // -------- Supabase Database Webhook (INSERT reservations) --------
    const whType = (raw as TriggerBody).type;
    const whTable = (raw as TriggerBody).table;
    if (whType === "INSERT" && whTable === "reservations") {
      const rec = (raw as TriggerBody).record;
      if (rec) return await handleReservationInsert(rec);
    }

    // -------- Chat message trigger (legacy body) --------
    const trigger = raw as TriggerBody;
    let rec = trigger?.record;

    if (rec?.receiver_id && rec?.content) {
      const receiverId = rec.receiver_id.trim();
      const senderId = (rec.sender_id ?? "").trim();
      const conversationId = (rec.conversation_id ?? "").trim();
      const kind = (rec.kind ?? "property").trim();
      const content = rec.content.trim();

      if (!receiverId || !content) {
        return json({ ok: true, sent: 0, reason: "missing receiver/content" });
      }

      if (senderId && senderId === receiverId) {
        return json({ ok: true, sent: 0, reason: "self message ignored" });
      }

      const tokens = await tokensForUser(receiverId);

      if (!tokens.length) {
        return json({ ok: true, sent: 0, reason: "no tokens" });
      }

      const accessToken = await getAccessToken();

      const title = kind === "support" ? "رسالة من الدعم" : "رسالة جديدة";
      const body = content.length > 140 ? content.slice(0, 140) + "…" : content;

      const data = asStringData({
        kind,
        conversation_id: conversationId,
        sender_id: senderId,
        receiver_id: receiverId,
        title_ar: title,
        body_ar: body,
      });

      const results = await deliverTokens(
        accessToken,
        tokens,
        title,
        body,
        data,
      );

      return json({ ok: true, mode: "trigger", sent: results.length, results });
    }

    // -------- Webhook: INSERT messages --------
    if (whType === "INSERT" && whTable === "messages" && (raw as any).record) {
      const mrec = (raw as any).record;
      const receiverId = (mrec.receiver_id ?? "").toString().trim();
      const senderId = (mrec.sender_id ?? "").toString().trim();
      const conversationId = (mrec.conversation_id ?? "").toString().trim();
      const content = (mrec.content ?? "").toString().trim();
      const kind = (mrec.kind ?? "property").toString().trim();

      if (!receiverId || !content) {
        return json({ ok: true, sent: 0, reason: "missing receiver/content" });
      }
      if (senderId && senderId === receiverId) {
        return json({ ok: true, sent: 0, reason: "self message ignored" });
      }

      const tokens = await tokensForUser(receiverId);
      if (!tokens.length) {
        return json({ ok: true, sent: 0, reason: "no tokens" });
      }

      const accessToken = await getAccessToken();
      const title = kind === "support" ? "رسالة من الدعم" : "رسالة جديدة";
      const body = content.length > 140 ? content.slice(0, 140) + "…" : content;
      const data = asStringData({
        kind: kind || "property",
        conversation_id: conversationId,
        sender_id: senderId,
        receiver_id: receiverId,
        title_ar: title,
        body_ar: body,
      });
      const results = await deliverTokens(
        accessToken,
        tokens,
        title,
        body,
        data,
      );
      return json({
        ok: true,
        mode: "messages_webhook",
        sent: results.length,
        results,
      });
    }

    // -------- Webhook: INSERT in_app_notifications (workflow / عروض / عقود / …) --------
    if (
      whType === "INSERT" &&
      whTable === "in_app_notifications" &&
      (raw as TriggerBody).record
    ) {
      const nrec = (raw as TriggerBody).record!;
      const username = (nrec.username ?? "").toString().trim();
      const title = (nrec.title ?? "موثوق العقاري").toString().trim() ||
        "موثوق العقاري";
      const body = (nrec.body ?? "").toString().trim() || "تنبيه جديد";
      const ntype = (nrec.type ?? "").toString().toLowerCase();

      if (
        ntype.includes("otp") ||
        ntype.includes("pin") ||
        ntype.includes("verify") ||
        ntype.includes("2fa") ||
        ntype.includes("mfa")
      ) {
        return json({ ok: true, sent: 0, reason: "security_notification_skipped" });
      }

      if (!username) {
        return json({ ok: true, sent: 0, reason: "no_username" });
      }

      const sb = getSupabaseAdmin();
      const { data: prof, error: pe } = await sb
        .from("users_profiles")
        .select("user_id")
        .eq("username", username)
        .maybeSingle();

      if (pe) {
        throw new Error(`users_profiles read: ${pe.message}`);
      }
      const targetUid = (prof?.user_id ?? "").toString().trim();
      if (!targetUid) {
        return json({ ok: true, sent: 0, reason: "profile_not_found" });
      }

      const tokens = await tokensForUser(targetUid);
      if (!tokens.length) {
        return json({ ok: true, sent: 0, reason: "no_tokens" });
      }

      const accessToken = await getAccessToken();
      const extra = inAppNotificationDataObject(nrec as unknown as Record<string, unknown>);
      const entityType = String(extra["entity_type"] ?? "").trim();
      const entityId = String(extra["entity_id"] ?? "").trim();
      const propertyFromData = String(extra["property_id"] ?? "").trim();
      const requestFromData = String(extra["request_id"] ?? "").trim();
      const propertyIdForPush = propertyFromData ||
        (entityType.toLowerCase() === "property" ? entityId : "");
      const requestIdForPush = requestFromData ||
        (entityType.toLowerCase() === "listing_request" ? entityId : "");

      const data = asStringData({
        kind: "workflow",
        notification_id: (nrec.id ?? "").toString(),
        title_ar: title,
        body_ar: body,
        type: ntype,
        entity_type: entityType,
        entity_id: entityId,
        property_id: propertyIdForPush,
        request_id: requestIdForPush,
        deep_route: String(extra["deep_route"] ?? "").trim(),
        main_tab: String(extra["main_tab"] ?? "").trim(),
        offer_id: String(extra["offer_id"] ?? "").trim(),
        status: String(extra["status"] ?? "").trim(),
      });
      const results = await deliverTokens(
        accessToken,
        tokens,
        title,
        body,
        data,
      );
      return json({
        ok: true,
        mode: "in_app_notifications_webhook",
        sent: results.length,
        results,
      });
    }

    // -------- Manual payload --------
    const manual = raw as ManualBody;
    const tokens = (manual.tokens ?? [])
      .map((t) => (t ?? "").toString().trim())
      .filter((t) => t.length > 0);

    if (!tokens.length) {
      return json({ ok: true, mode: "manual", sent: 0, reason: "no tokens" });
    }

    const accessToken = await getAccessToken();
    const results: any[] = [];

    for (const t of tokens) {
      results.push(
        await sendToToken(
          accessToken,
          t,
          manual.title ?? "New message",
          manual.body ?? "",
          manual.data ? asStringData(manual.data as any) : {},
        ),
      );
    }

    return json({ ok: true, mode: "manual", sent: results.length, results });
  } catch (e) {
    console.error("send_push ERROR:", e);
    const msg = e instanceof Error ? e.message : String(e);
    const stack = e instanceof Error ? e.stack : undefined;
    return json({ ok: false, error: msg, stack }, 500);
  }
});
