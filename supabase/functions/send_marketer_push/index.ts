// supabase/functions/send_marketer_push/index.ts
// deno-lint-ignore-file no-explicit-any
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

// =====================
// Types
// =====================
type TriggerBody = {
  record?: {
    request_id?: string;
    title?: string;
    city?: string;
  };
};

type ManualBody = {
  tokens?: string[];
  title?: string;
  body?: string;
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

// =====================
// Firebase access token
// =====================
async function getAccessToken() {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
  const privateKeyB64 = Deno.env.get("FIREBASE_PRIVATE_KEY_B64") ?? "";

  if (!projectId || !clientEmail || !privateKeyB64) {
    throw new Error("Missing Firebase env secrets");
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

  const j = await r.json();

  if (!j?.access_token) {
    throw new Error("Failed to obtain Firebase token");
  }

  return j.access_token as string;
}

// =====================
// Send notification
// =====================
async function sendToToken(
  accessToken: string,
  token: string,
  title: string,
  body: string,
) {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")!;
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const message = {
    message: {
      token,
      notification: {
        title,
        body,
      },
    },
  };

  const r = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });

  const j = await r.json().catch(() => ({}));

  return { ok: r.ok, status: r.status, body: j };
}

// =====================
// Supabase Admin
// =====================
function getSupabaseAdmin() {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!url || !key) {
    throw new Error("Missing Supabase env");
  }

  return createClient(url, key, {
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
        "Access-Control-Allow-Headers": "Content-Type",
      },
    });
  }

  if (req.method !== "POST") {
    return json({ ok: false, error: "POST only" }, 405);
  }

  try {
    const raw = await req.json().catch(() => ({}));

    // -------- Trigger mode (new marketing request) --------
    const trigger = raw as TriggerBody;

    if (trigger?.record?.request_id) {
      const sb = getSupabaseAdmin();

      const { data: marketers } = await sb
        .from("marketer_profiles")
        .select("user_id");

      if (!marketers?.length) {
        return json({ ok: true, sent: 0 });
      }

      const userIds = marketers.map((m: any) => m.user_id);

      const { data: tokensRows } = await sb
        .from("user_push_tokens")
        .select("fcm_token")
        .in("user_id", userIds);

      const tokens = (tokensRows ?? [])
        .map((r: any) => r.fcm_token)
        .filter((t: string) => !!t);

      if (!tokens.length) {
        return json({ ok: true, sent: 0 });
      }

      const accessToken = await getAccessToken();

      const title = "طلب تسويق جديد";
      const body =
        trigger.record.title ??
        "يوجد طلب تسويق عقار جديد بالقرب منك";

      const results: any[] = [];

      for (const t of tokens) {
        results.push(await sendToToken(accessToken, t, title, body));
      }

      return json({ ok: true, mode: "trigger", sent: results.length });
    }

    // -------- Manual mode --------
    const manual = raw as ManualBody;

    const tokens = manual.tokens ?? [];

    if (!tokens.length) {
      return json({ ok: true, sent: 0 });
    }

    const accessToken = await getAccessToken();

    const results: any[] = [];

    for (const t of tokens) {
      results.push(
        await sendToToken(
          accessToken,
          t,
          manual.title ?? "New Request",
          manual.body ?? "",
        ),
      );
    }

    return json({ ok: true, mode: "manual", sent: results.length });
  } catch (e) {
    console.error("send_marketer_push ERROR:", e);
    return json(
      {
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      },
      500,
    );
  }
});