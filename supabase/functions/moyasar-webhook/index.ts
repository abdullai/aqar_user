// deno-lint-ignore-file no-explicit-any
// Moyasar dashboard → Webhooks → URL: https://<project>.supabase.co/functions/v1/moyasar-webhook
// Secrets (Supabase Dashboard → Edge Functions → Secrets):
//   MOYASAR_SECRET_KEY   = sk_test_… or sk_live_…
//   MOYASAR_WEBHOOK_SECRET = same value you enter as "secret" when creating the webhook in Moyasar
//
// When creating a payment from the app, set metadata (see Moyasar metadata limits):
//   billing_transaction_id = UUID of public.billing_transactions row (status pending)
//   user_id                = same as row.user_id (defense in depth)
//
// Amount: Moyasar uses smallest currency unit (SAR → halalas). This handler compares
// payment.amount to Math.round(row.amount * 100).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

function moyasarApiBase(_secretKey: string): string {
  return "https://api.moyasar.com/v1";
}

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function basicAuthHeader(secretKey: string): string {
  const raw = `${secretKey}:`;
  const bin = new TextEncoder().encode(raw);
  let s = "";
  for (const b of bin) s += String.fromCharCode(b);
  return `Basic ${btoa(s)}`;
}

async function fetchMoyasarPayment(
  secretKey: string,
  paymentId: string,
): Promise<any | null> {
  const res = await fetch(`${moyasarApiBase(secretKey)}/payments/${encodeURIComponent(paymentId)}`, {
    method: "GET",
    headers: {
      Authorization: basicAuthHeader(secretKey),
      Accept: "application/json",
    },
  });
  if (!res.ok) return null;
  try {
    return await res.json();
  } catch {
    return null;
  }
}

function halalasFromSarRow(amount: unknown): number | null {
  const n = typeof amount === "number" ? amount : Number.parseFloat(String(amount ?? ""));
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

async function upsertSavedCardFromMoyasarPayment(
  svc: ReturnType<typeof createClient>,
  userId: string,
  verified: Record<string, unknown>,
): Promise<void> {
  const source = verified?.source;
  if (!source || typeof source !== "object") return;
  const src = source as Record<string, unknown>;
  if (String(src.type ?? "").toLowerCase() !== "creditcard") return;
  const token = String(src.token ?? "").trim();
  if (!token || token.startsWith("mock_")) return;
  const number = String(src.number ?? "");
  const digits = number.replace(/\D/g, "");
  const lastFour = digits.length >= 4 ? digits.slice(-4) : "0000";
  const scheme = String(src.company ?? "visa").toLowerCase();
  const holder = String(src.name ?? "").trim() || null;

  const { data: existing } = await svc
    .from("saved_cards")
    .select("id")
    .eq("user_id", userId)
    .eq("card_token", token)
    .maybeSingle();
  if (existing) return;

  await svc
    .from("saved_cards")
    .delete()
    .eq("user_id", userId)
    .like("card_token", "mock_%")
    .eq("last_four", lastFour);

  const { count } = await svc
    .from("saved_cards")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId);
  const isDefault = (count ?? 0) === 0;

  await svc.from("saved_cards").insert({
    user_id: userId,
    card_token: token,
    last_four: lastFour,
    card_scheme: scheme,
    card_holder_name: holder,
    expiry_month: 12,
    expiry_year: 2099,
    is_default: isDefault,
  });
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "method_not_allowed" });
  }

  const webhookSecret = (Deno.env.get("MOYASAR_WEBHOOK_SECRET") ?? "").trim();
  const moyasarSecret = (Deno.env.get("MOYASAR_SECRET_KEY") ?? "").trim();
  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();

  if (!webhookSecret || !moyasarSecret || !supabaseUrl || !serviceKey) {
    return json(500, { error: "server_misconfigured" });
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const incomingSecret = String(payload?.secret_token ?? "").trim();
  if (!incomingSecret || incomingSecret !== webhookSecret) {
    return json(401, { error: "invalid_webhook_secret" });
  }

  const type = String(payload?.type ?? "").trim();
  const data = payload?.data;
  const paymentId = data?.id != null ? String(data.id).trim() : "";

  const svc = createClient(supabaseUrl, serviceKey);

  // Fail / void: best-effort mark pending billing row as failed if metadata links it.
  if (
    type === "payment_failed" ||
    type === "payment_faild" ||
    type === "payment_voided"
  ) {
    const meta = data?.metadata && typeof data.metadata === "object"
      ? (data.metadata as Record<string, unknown>)
      : {};
    const bid = String(meta["billing_transaction_id"] ?? "").trim();
    if (bid && paymentId) {
      const { data: billRow } = await svc
        .from("billing_transactions")
        .select("id,subscription_id")
        .eq("id", bid)
        .maybeSingle();
      await svc
        .from("billing_transactions")
        .update({
          status: "failed",
          gateway_transaction_id: paymentId,
          gateway_response: { moyasar_webhook: payload },
          completed_at: new Date().toISOString(),
        })
        .eq("id", bid)
        .eq("status", "pending");
      const sid = billRow?.subscription_id != null
        ? String(billRow.subscription_id).trim()
        : "";
      if (sid) {
        await svc
          .from("user_subscriptions")
          .update({
            auto_renew_last_failure_at: new Date().toISOString(),
            auto_renew_last_failure_reason: type,
          })
          .eq("id", sid);
      }
    }
    return json(200, { ok: true, handled: type });
  }

  if (type !== "payment_paid" && type !== "payment_captured") {
    return json(200, { ok: true, ignored: true, type });
  }

  if (!paymentId) {
    return json(200, { ok: false, reason: "missing_payment_id" });
  }

  const verified = await fetchMoyasarPayment(moyasarSecret, paymentId);
  if (!verified || String(verified?.status ?? "").toLowerCase() !== "paid") {
    return json(200, { ok: false, reason: "payment_not_verified_or_not_paid" });
  }

  const meta = verified?.metadata && typeof verified.metadata === "object"
    ? (verified.metadata as Record<string, unknown>)
    : {};
  const billingId = String(meta["billing_transaction_id"] ?? "").trim();
  const metaUser = String(meta["user_id"] ?? "").trim();

  if (!billingId) {
    return json(200, { ok: false, reason: "metadata_missing_billing_transaction_id" });
  }

  const { data: row, error: selErr } = await svc
    .from("billing_transactions")
    .select("id,user_id,amount,currency,status,gateway_transaction_id,subscription_id,payment_method")
    .eq("id", billingId)
    .maybeSingle();

  if (selErr || !row) {
    return json(200, { ok: false, reason: "billing_row_not_found" });
  }

  if (metaUser && String(row.user_id) !== metaUser) {
    return json(200, { ok: false, reason: "user_id_metadata_mismatch" });
  }

  const expectedHalalas = halalasFromSarRow(row.amount);
  const paidHalalas = typeof verified.amount === "number"
    ? verified.amount
    : Number.parseInt(String(verified.amount ?? ""), 10);
  if (
    expectedHalalas == null ||
    !Number.isFinite(paidHalalas) ||
    paidHalalas !== expectedHalalas
  ) {
    return json(200, { ok: false, reason: "amount_mismatch", expectedHalalas, paidHalalas });
  }

  const cur = String(verified.currency ?? "SAR").toUpperCase();
  if (String(row.currency ?? "SAR").toUpperCase() !== cur) {
    return json(200, { ok: false, reason: "currency_mismatch" });
  }

  if (row.status === "success" && String(row.gateway_transaction_id ?? "") === paymentId) {
    return json(200, { ok: true, duplicate: true, billing_transaction_id: billingId });
  }

  if (row.status !== "pending") {
    return json(200, { ok: false, reason: "billing_not_pending", status: row.status });
  }

  const { error: updErr } = await svc
    .from("billing_transactions")
    .update({
      status: "success",
      gateway_transaction_id: paymentId,
      gateway_response: verified,
      completed_at: new Date().toISOString(),
    })
    .eq("id", billingId)
    .eq("status", "pending");

  if (updErr) {
    return json(200, { ok: false, reason: "update_failed", detail: updErr.message });
  }

  const userId = String(row.user_id ?? "").trim();
  if (userId) {
    try {
      await upsertSavedCardFromMoyasarPayment(svc, userId, verified);
    } catch {
      // لا نُفشل الويب هوك إذا فشل حفظ البطاقة.
    }
  }

  try {
    await svc.rpc("activate_instant_market_request_credit", {
      p_billing_transaction_id: billingId,
    });
  } catch {
    // trigger may have already activated
  }

  const renewSid = row.subscription_id != null
    ? String(row.subscription_id).trim()
    : "";
  if (renewSid) {
    await svc
      .from("user_subscriptions")
      .update({
        auto_renew_last_failure_at: null,
        auto_renew_last_failure_reason: null,
      })
      .eq("id", renewSid);
  }

  const purpose = String(meta["purpose"] ?? "").trim();
  const payMethod = String(row.payment_method ?? "").trim();
  const autoRenewHeadless =
    purpose === "auto_renew" || payMethod === "card_auto_renew";

  if (autoRenewHeadless && renewSid) {
    const { error: rpcErr } = await svc.rpc("subscription_apply_auto_renew_extension", {
      p_subscription_id: renewSid,
      p_billing_transaction_id: billingId,
    });
    if (rpcErr) {
      return json(200, {
        ok: true,
        billing_transaction_id: billingId,
        moyasar_payment_id: paymentId,
        extension_warning: rpcErr.message,
      });
    }
  }

  // Subscription activation for manual (in-app) flows remains in the Flutter client after polling.
  return json(200, {
    ok: true,
    billing_transaction_id: billingId,
    moyasar_payment_id: paymentId,
  });
});
