// Charge a saved Moyasar card token for subscription checkout.
// Client: Supabase.functions.invoke('moyasar-charge-saved-card', { body: { billing_transaction_id, card_id } })
// Requires authenticated user JWT. Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
// MOYASAR_SECRET_KEY, MOYASAR_CALLBACK_URL

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

function moyasarApiBase(_secretKey: string): string {
  return "https://api.moyasar.com/v1";
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function basicAuthHeader(secretKey: string): string {
  const raw = `${secretKey}:`;
  const bin = new TextEncoder().encode(raw);
  let s = "";
  for (const b of bin) s += String.fromCharCode(b);
  return `Basic ${btoa(s)}`;
}

function halalasFromSar(amount: number): number {
  const h = Math.round(amount * 100);
  return h < 100 ? 100 : h;
}

function merchantContact(): string {
  return (Deno.env.get("MOYASAR_METADATA_MERCHANT_CONTACT") ?? "").trim() ||
    "Abdullah Issa Ahmed Abuhia";
}

function moyasarErrorMessage(body: Record<string, unknown> | null): string {
  if (!body) return "";
  const msg = body.message ?? body.error;
  if (typeof msg === "string") return msg.trim();
  if (msg && typeof msg === "object") {
    const nested = msg as Record<string, unknown>;
    const inner = nested.message ?? nested.error;
    if (typeof inner === "string") return inner.trim();
  }
  const errors = body.errors;
  if (Array.isArray(errors) && errors.length > 0) {
    const first = errors[0];
    if (typeof first === "string") return first;
    if (first && typeof first === "object") {
      const e = first as Record<string, unknown>;
      const m = e.message ?? e.error;
      if (typeof m === "string") return m.trim();
    }
  }
  return "";
}

serve(async (req) => {
  try {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method_not_allowed" });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const moyasarSecret = (Deno.env.get("MOYASAR_SECRET_KEY") ?? "").trim();
  const callbackUrl = (Deno.env.get("MOYASAR_CALLBACK_URL") ?? "").trim();

  if (!supabaseUrl || !serviceKey || !moyasarSecret || !callbackUrl) {
    return json(200, { ok: false, error: "server_misconfigured" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json(401, { ok: false, error: "auth" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, error: "invalid_json" });
  }

  const billingId = String(body.billing_transaction_id ?? "").trim();
  const cardId = String(body.card_id ?? "").trim();
  if (!billingId || !cardId) {
    return json(400, { ok: false, error: "missing_fields" });
  }

  const userClient = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user?.id) {
    return json(401, { ok: false, error: "auth" });
  }
  const userId = userData.user.id;

  const svc = createClient(supabaseUrl, serviceKey);

  const { data: billing, error: billErr } = await svc
    .from("billing_transactions")
    .select("id,user_id,amount,currency,status,payment_method")
    .eq("id", billingId)
    .eq("user_id", userId)
    .maybeSingle();

  if (billErr || !billing) {
    return json(200, { ok: false, error: "billing_not_found" });
  }
  if (billing.status !== "pending") {
    return json(200, {
      ok: false,
      error: "billing_not_pending",
      status: billing.status,
    });
  }

  const { data: card, error: cardErr } = await svc
    .from("saved_cards")
    .select("id,card_token,card_scheme,expiry_month,expiry_year")
    .eq("id", cardId)
    .eq("user_id", userId)
    .maybeSingle();

  if (cardErr || !card) {
    return json(200, { ok: false, error: "card_not_found" });
  }

  const expMonth = Number.parseInt(String(card.expiry_month ?? "0"), 10);
  let expYear = Number.parseInt(String(card.expiry_year ?? "0"), 10);
  if (expYear < 100) expYear += 2000;
  if (expYear < 2090) {
    if (expMonth < 1 || expMonth > 12 || expYear < 2000) {
      return json(200, { ok: false, error: "card_expired" });
    }
    const now = new Date();
    const endOfMonth = new Date(expYear, expMonth, 0, 23, 59, 59);
    if (now > endOfMonth) {
      return json(200, { ok: false, error: "card_expired" });
    }
  }

  const token = String(card.card_token ?? "").trim();
  if (!token) {
    return json(200, { ok: false, error: "empty_token" });
  }
  if (token.startsWith("mock_")) {
    return json(200, { ok: false, error: "mock_token" });
  }

  const amountSar = typeof billing.amount === "number"
    ? billing.amount
    : Number.parseFloat(String(billing.amount ?? "0"));
  if (!Number.isFinite(amountSar) || amountSar <= 0) {
    return json(200, { ok: false, error: "bad_amount" });
  }

  const meta = {
    billing_transaction_id: billingId,
    user_id: userId,
    purpose: String(body.purpose ?? "subscription_checkout"),
    merchant_contact: merchantContact(),
    product: "aqar_reliable",
  };

  const payBody = {
    given_id: billingId,
    amount: halalasFromSar(amountSar),
    currency: String(billing.currency ?? "SAR").toUpperCase(),
    description: "Mawthuq Line subscription",
    callback_url: callbackUrl,
    metadata: meta,
    source: {
      type: "token",
      token,
      "3ds": true,
      manual: false,
    },
  };

  let payJson: Record<string, unknown> | null = null;
  let payHttpStatus = 0;
  try {
    const payRes = await fetch(`${moyasarApiBase(moyasarSecret)}/payments`, {
      method: "POST",
      headers: {
        Authorization: basicAuthHeader(moyasarSecret),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payBody),
    });
    payHttpStatus = payRes.status;
    payJson = await payRes.json().catch(() => null);

    if (!payRes.ok) {
      const moyasarMsg = moyasarErrorMessage(payJson);
      await svc.from("billing_transactions").update({
        status: "failed",
        gateway_response: {
          moyasar_http_error: payRes.status,
          body: payJson,
          message: moyasarMsg,
        },
        completed_at: new Date().toISOString(),
      }).eq("id", billingId).eq("status", "pending");

      const clientError = payRes.status === 401
        ? "moyasar_auth_error"
        : payRes.status === 405
        ? "moyasar_account_inactive"
        : "moyasar_rejected";

      return json(200, {
        ok: false,
        error: clientError,
        moyasar_status: payRes.status,
        moyasar_message: moyasarMsg || undefined,
        detail: payJson,
      });
    }
  } catch (e) {
    await svc.from("billing_transactions").update({
      status: "failed",
      gateway_response: { network_error: String(e) },
      completed_at: new Date().toISOString(),
    }).eq("id", billingId).eq("status", "pending");

    return json(200, { ok: false, error: "network", detail: String(e) });
  }

  const st = String(payJson?.status ?? "").toLowerCase();
  const payId = payJson?.id != null ? String(payJson.id).trim() : "";
  const source = payJson?.source as Record<string, unknown> | undefined;
  const threeDsUrl = source?.transaction_url != null
    ? String(source.transaction_url).trim()
    : "";

  if (st === "paid" || st === "captured") {
    await svc.from("billing_transactions").update({
      status: "success",
      gateway_transaction_id: payId || null,
      gateway_response: payJson,
      completed_at: new Date().toISOString(),
    }).eq("id", billingId).eq("status", "pending");

    return json(200, { ok: true, status: st, pay_id: payId });
  }

  if (st === "failed" || st === "voided") {
    await svc.from("billing_transactions").update({
      status: "failed",
      gateway_transaction_id: payId || null,
      gateway_response: payJson,
      completed_at: new Date().toISOString(),
    }).eq("id", billingId).eq("status", "pending");

    return json(200, {
      ok: false,
      error: st,
      status: st,
      pay_id: payId,
      moyasar_message: moyasarErrorMessage(payJson) || undefined,
    });
  }

  // initiated / pending 3DS — webhook finalizes
  await svc.from("billing_transactions").update({
    gateway_transaction_id: payId || null,
    gateway_response: payJson,
  }).eq("id", billingId).eq("status", "pending");

  return json(200, {
    ok: true,
    status: st,
    awaiting_webhook: true,
    pay_id: payId,
    three_ds_url: threeDsUrl || undefined,
    moyasar_http: payHttpStatus || undefined,
  });
  } catch (e) {
    console.error("[moyasar-charge-saved-card] unhandled", e);
    return json(200, { ok: false, error: "internal_error", detail: String(e) });
  }
});
