// فحص ترابط إعدادات ميسّر (بدون كشف الأسرار الكاملة).
// POST + JWT المستخدم
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function keyMode(prefix: string): string {
  if (prefix.startsWith("pk_test") || prefix.startsWith("sk_test")) {
    return "test";
  }
  if (prefix.startsWith("pk_live") || prefix.startsWith("sk_live")) {
    return "live";
  }
  return "missing";
}

function maskKey(key: string): string {
  const k = key.trim();
  if (k.length === 0) return "";
  if (k.length <= 10) return "••••";
  return `${k.slice(0, 7)}…${k.slice(-4)}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method_not_allowed" });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const anonKey = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();
  const sk = (Deno.env.get("MOYASAR_SECRET_KEY") ?? "").trim();
  const webhookSecret = (Deno.env.get("MOYASAR_WEBHOOK_SECRET") ?? "").trim();
  const callbackUrl = (Deno.env.get("MOYASAR_CALLBACK_URL") ?? "").trim();

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json(401, { ok: false, error: "auth" });
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const clientPrefix = String(body.publishable_prefix ?? "").trim();
  const clientMode = keyMode(clientPrefix);
  const serverMode = keyMode(sk);

  const sb = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await sb.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "auth" });
  }

  const modesMatch = clientMode !== "missing" && serverMode !== "missing" &&
    clientMode === serverMode;
  const issues: string[] = [];

  if (clientMode === "missing") {
    issues.push("client_publishable_key_missing");
  }
  if (serverMode === "missing") {
    issues.push("server_secret_key_missing");
  }
  if (!modesMatch && clientMode !== "missing" && serverMode !== "missing") {
    issues.push("client_server_mode_mismatch");
  }
  if (!callbackUrl) {
    issues.push("callback_url_missing_on_server");
  }
  if (!webhookSecret) {
    issues.push("webhook_secret_missing");
  }
  if (clientMode === "live") {
    issues.push(
      "live_mode_requires_moyasar_account_activation_otherwise_http_405",
    );
  }

  return json(200, {
    ok: issues.length === 0 ||
      (issues.length === 1 &&
        issues[0] === "live_mode_requires_moyasar_account_activation_otherwise_http_405"),
    client_mode: clientMode,
    server_mode: serverMode,
    modes_match: modesMatch,
    publishable_masked: clientPrefix ? `${clientPrefix}…` : "",
    secret_masked: maskKey(sk),
    callback_url_set: !!callbackUrl,
    callback_url_host: callbackUrl
      ? (() => {
        try {
          return new URL(callbackUrl).host;
        } catch {
          return "";
        }
      })()
      : "",
    webhook_secret_set: !!webhookSecret,
    webhook_url:
      `${supabaseUrl.replace(/\/$/, "")}/functions/v1/moyasar-webhook`,
    issues,
    test_card_hint: clientMode === "test"
      ? "4111111111111111 / 12/30 / CVV 123"
      : null,
  });
});
