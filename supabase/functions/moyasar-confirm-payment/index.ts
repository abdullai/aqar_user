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

function basicAuthHeader(secretKey: string): string {
  const bytes = new TextEncoder().encode(`${secretKey}:`);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return `Basic ${btoa(binary)}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method_not_allowed" });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const anonKey = (Deno.env.get("SUPABASE_ANON_KEY") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const moyasarKey = (Deno.env.get("MOYASAR_SECRET_KEY") ?? "").trim();
  const webhookSecret = (Deno.env.get("MOYASAR_WEBHOOK_SECRET") ?? "").trim();
  if (!supabaseUrl || !anonKey || !serviceKey || !moyasarKey || !webhookSecret) {
    return json(500, { ok: false, error: "server_misconfigured" });
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return json(401, { ok: false, error: "auth" });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, error: "invalid_json" });
  }

  const billingId = String(body.billing_transaction_id ?? "").trim();
  const paymentId = String(body.payment_id ?? "").trim();
  if (!billingId || !paymentId) {
    return json(400, { ok: false, error: "missing_payment_reference" });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) {
    return json(401, { ok: false, error: "auth" });
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data: billing, error: billingError } = await admin
    .from("billing_transactions")
    .select("id,user_id,amount,currency,status")
    .eq("id", billingId)
    .eq("user_id", authData.user.id)
    .maybeSingle();
  if (billingError) {
    console.error("[moyasar-confirm-payment] billing lookup failed", billingError.message);
    return json(500, { ok: false, error: "billing_lookup_failed" });
  }
  if (!billing) return json(404, { ok: false, error: "billing_not_found" });
  if (billing.status !== "pending" && billing.status !== "success") {
    return json(409, { ok: false, error: "billing_not_pending" });
  }

  let payment: Record<string, unknown>;
  try {
    const response = await fetch(
      `https://api.moyasar.com/v1/payments/${encodeURIComponent(paymentId)}`,
      {
        headers: {
          Authorization: basicAuthHeader(moyasarKey),
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) {
      return json(502, { ok: false, error: "moyasar_payment_lookup_failed" });
    }
    payment = await response.json();
  } catch (error) {
    console.error("[moyasar-confirm-payment] Moyasar lookup failed", error);
    return json(502, { ok: false, error: "moyasar_payment_lookup_failed" });
  }

  const metadata = payment.metadata && typeof payment.metadata === "object"
    ? payment.metadata as Record<string, unknown>
    : {};
  if (
    String(payment.id ?? "") !== paymentId ||
    String(metadata.billing_transaction_id ?? "") !== billingId ||
    String(metadata.user_id ?? "") !== authData.user.id
  ) {
    return json(403, { ok: false, error: "payment_metadata_mismatch" });
  }

  const paymentStatus = String(payment.status ?? "").toLowerCase();
  if (paymentStatus !== "paid" && paymentStatus !== "captured") {
    return json(409, { ok: false, error: "payment_not_paid" });
  }
  const expectedHalalas = Math.round(Number(billing.amount) * 100);
  if (
    !Number.isFinite(expectedHalalas) ||
    Number(payment.amount) !== expectedHalalas
  ) {
    return json(409, { ok: false, error: "amount_mismatch" });
  }
  if (
    String(payment.currency ?? "SAR").toUpperCase() !==
    String(billing.currency ?? "SAR").toUpperCase()
  ) {
    return json(409, { ok: false, error: "currency_mismatch" });
  }

  const secretIsLive = moyasarKey.startsWith("sk_live_");
  const secretIsTest = moyasarKey.startsWith("sk_test_");
  const paymentIsLive = payment.livemode === true || payment.livemode === "true";
  if (
    (secretIsLive && !paymentIsLive) ||
    (secretIsTest && paymentIsLive) ||
    (!secretIsLive && !secretIsTest)
  ) {
    return json(409, { ok: false, error: "environment_mismatch" });
  }

  const webhookResponse = await fetch(
    `${supabaseUrl.replace(/\/$/, "")}/functions/v1/moyasar-webhook`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        type: "payment_paid",
        secret_token: webhookSecret,
        data: { id: paymentId, metadata },
      }),
    },
  );
  let webhookResult: Record<string, unknown> = {};
  try {
    webhookResult = await webhookResponse.json();
  } catch {
    return json(502, { ok: false, error: "payment_fulfillment_failed" });
  }
  if (!webhookResponse.ok || webhookResult.ok !== true) {
    console.error(
      "[moyasar-confirm-payment] verified payment fulfillment was not confirmed",
      webhookResult.reason ?? webhookResult.error ?? webhookResponse.status,
    );
    return json(502, { ok: false, error: "payment_fulfillment_failed" });
  }

  return json(200, {
    ok: true,
    billing_transaction_id: billingId,
    payment_id: paymentId,
    card_saved: webhookResult.card_saved === true,
  });
});
