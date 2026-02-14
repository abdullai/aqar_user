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
    kind?: string; // support | reservation | property
  };
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

// ✅ UPDATED: uses FIREBASE_PRIVATE_KEY_B64 (stable, no multiline issues)
async function getAccessToken() {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
  const privateKeyB64 = Deno.env.get("FIREBASE_PRIVATE_KEY_B64") ?? "";

  if (!projectId || !clientEmail || !privateKeyB64) {
    throw new Error(
      `Missing Firebase env secrets: projectId=${!!projectId}, clientEmail=${!!clientEmail}, privateKeyB64=${!!privateKeyB64}`,
    );
  }

  // Build PEM from Base64
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

  // ✅ Read text then try parse JSON
  const text = await r.text().catch(() => "");
  let j: any = {};
  try {
    j = text ? JSON.parse(text) : {};
  } catch {
    j = { raw: text };
  }

  return { ok: r.ok, status: r.status, body: j };
}

// =====================
// ✅ Supabase Admin (important)
// =====================
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

    // -------- Trigger payload --------
    const trigger = raw as TriggerBody;
    const rec = trigger?.record;

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

      const sb = getSupabaseAdmin();

      const { data: rows, error } = await sb
        .from("user_push_tokens")
        .select("fcm_token")
        .eq("user_id", receiverId);

      if (error) {
        throw new Error(`user_push_tokens read error: ${error.message}`);
      }

      const tokens = (rows ?? [])
        .map((r: any) => (r?.fcm_token ?? "").toString().trim())
        .filter((t) => t.length > 0);

      if (!tokens.length) {
        return json({ ok: true, sent: 0, reason: "no tokens" });
      }

      const accessToken = await getAccessToken();

      const title = kind === "support" ? "رسالة من الدعم" : "رسالة جديدة";
      const body = content.length > 140 ? content.slice(0, 140) + "…" : content;

      const data = {
        kind,
        conversation_id: conversationId,
        sender_id: senderId,
        receiver_id: receiverId,
      };

      const results: any[] = [];
      for (const t of tokens) {
        results.push(await sendToToken(accessToken, t, title, body, data));
      }

      return json({ ok: true, mode: "trigger", sent: results.length, results });
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
          manual.data,
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
