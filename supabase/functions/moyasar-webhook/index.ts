// deno-lint-ignore-file no-explicit-any
// Moyasar dashboard webhook:
//   https://<project>.supabase.co/functions/v1/moyasar-webhook
// Events this project handles (from the live Moyasar webhook config):
//   payment_paid, payment_failed, payment_voided, payment_authorized,
//   payment_captured, payment_refunded, payment_abandoned, payment_verified,
//   payment_canceled, payment_expired
// Payout/balance events are acknowledged and ignored.
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
  const res = await fetch(
    `${moyasarApiBase(secretKey)}/payments/${encodeURIComponent(paymentId)}`,
    {
      method: "GET",
      headers: {
        Authorization: basicAuthHeader(secretKey),
        Accept: "application/json",
      },
    },
  );
  if (!res.ok) return null;
  try {
    return await res.json();
  } catch {
    return null;
  }
}

async function refundMoyasarPayment(
  secretKey: string,
  paymentId: string,
  amountHalalas: number,
): Promise<Record<string, unknown> | null> {
  const res = await fetch(
    `${moyasarApiBase(secretKey)}/payments/${encodeURIComponent(paymentId)}/refund`,
    {
      method: "POST",
      headers: {
        Authorization: basicAuthHeader(secretKey),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ amount: amountHalalas }),
    },
  );
  try {
    return await res.json();
  } catch {
    return { ok: res.ok, status: res.status };
  }
}

function halalasFromSarRow(amount: unknown): number | null {
  const n = typeof amount === "number"
    ? amount
    : Number.parseFloat(String(amount ?? ""));
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
  const month = Number.parseInt(String(src.month ?? src.exp_month ?? "12"), 10);
  const yearRaw = Number.parseInt(String(src.year ?? src.exp_year ?? "0"), 10);
  const year = yearRaw > 0 ? (yearRaw < 100 ? yearRaw + 2000 : yearRaw) : 2099;

  const { data: existing } = await svc
    .from("saved_cards")
    .select("id")
    .eq("user_id", userId)
    .eq("card_token", token)
    .maybeSingle();
  if (existing) return;

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
    expiry_month: Number.isFinite(month) && month >= 1 && month <= 12 ? month : 12,
    expiry_year: year,
    is_default: isDefault,
  });
}

const FAIL_TYPES = new Set([
  "payment_failed",
  "payment_faild",
  "payment_voided",
  "payment_abandoned",
  "payment_canceled",
  "payment_cancelled",
  "payment_expired",
]);

const SUCCESS_TYPES = new Set(["payment_paid", "payment_captured"]);

const IGNORE_TYPES = new Set([
  "payment_verified",
  "card_auth_authenticated",
  "card_auth_failed",
  "balance_transferred",
  "payout_initiated",
  "payout_paid",
  "payout_failed",
  "payout_canceled",
  "payout_returned",
]);

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

  const eventMeta = data?.metadata && typeof data.metadata === "object"
    ? (data.metadata as Record<string, unknown>)
    : {};
  const eventBillingId = String(eventMeta["billing_transaction_id"] ?? "").trim() || null;
  const recorded = await svc.rpc("record_moyasar_webhook_event", {
    p_event_type: type,
    p_payment_id: paymentId || null,
    p_billing_transaction_id: eventBillingId,
    p_payload: payload,
  });
  if (recorded?.data?.duplicate === true && SUCCESS_TYPES.has(type)) {
    return json(200, { ok: true, duplicate: true, type });
  }

  if (IGNORE_TYPES.has(type)) {
    return json(200, { ok: true, ignored: true, type });
  }

  if (type === "payment_authorized") {
    const meta = data?.metadata && typeof data.metadata === "object"
      ? (data.metadata as Record<string, unknown>)
      : {};
    const bid = String(meta["billing_transaction_id"] ?? "").trim();
    if (bid) {
      await svc.rpc("mark_billing_gateway_outcome", {
        p_billing_transaction_id: bid,
        p_status: "authorized",
        p_gateway_transaction_id: paymentId || null,
        p_gateway_response: payload,
      });
    }
    return json(200, { ok: true, handled: type, pending_capture: true });
  }

  if (FAIL_TYPES.has(type)) {
    const meta = data?.metadata && typeof data.metadata === "object"
      ? (data.metadata as Record<string, unknown>)
      : {};
    const bid = String(meta["billing_transaction_id"] ?? "").trim();
    if (bid && paymentId) {
      await svc.rpc("mark_billing_gateway_outcome", {
        p_billing_transaction_id: bid,
        p_status: type === "payment_expired" ? "expired" : "failed",
        p_gateway_transaction_id: paymentId,
        p_gateway_response: { moyasar_webhook: payload },
        p_failure_code: type,
        p_failure_reason: type,
      });
    }
    return json(200, { ok: true, handled: type });
  }

  if (type === "payment_refunded") {
    const meta = data?.metadata && typeof data.metadata === "object"
      ? (data.metadata as Record<string, unknown>)
      : {};
    const bid = String(meta["billing_transaction_id"] ?? "").trim();
    if (bid) {
      const { data: credit } = await svc
        .from("market_request_instant_credits")
        .select("id")
        .eq("billing_transaction_id", bid)
        .maybeSingle();
      if (credit?.id) {
        await svc.rpc("apply_instant_credit_refund", {
          p_credit_id: credit.id,
          p_gateway_refund_id: paymentId,
        });
      } else {
        await svc.rpc("mark_billing_gateway_outcome", {
          p_billing_transaction_id: bid,
          p_status: "refunded",
          p_gateway_transaction_id: paymentId,
          p_gateway_response: payload,
          p_failure_code: "payment_refunded",
        });
      }
    }
    return json(200, { ok: true, handled: type });
  }

  if (!SUCCESS_TYPES.has(type)) {
    return json(200, { ok: true, ignored: true, type, reason: "unhandled_event" });
  }

  if (!paymentId) {
    return json(200, { ok: false, reason: "missing_payment_id" });
  }

  const verified = await fetchMoyasarPayment(moyasarSecret, paymentId);
  const st = String(verified?.status ?? "").toLowerCase();
  if (!verified || (st !== "paid" && st !== "captured")) {
    return json(200, { ok: false, reason: "payment_not_verified_or_not_paid" });
  }

  const secretIsLive = moyasarSecret.startsWith("sk_live_");
  const secretIsTest = moyasarSecret.startsWith("sk_test_");
  const payLive = verified.livemode === true || verified.livemode === "true";
  if ((secretIsLive && !payLive) || (secretIsTest && payLive)) {
    return json(200, { ok: false, reason: "environment_mismatch" });
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
    .select(
      "id,user_id,amount,currency,status,gateway_transaction_id,subscription_id,payment_method,purpose,fulfillment_applied_at,expires_at",
    )
    .eq("id", billingId)
    .maybeSingle();

  if (selErr || !row) {
    return json(200, { ok: false, reason: "billing_row_not_found" });
  }

  if (metaUser && String(row.user_id) !== metaUser) {
    await svc.rpc("mark_billing_gateway_outcome", {
      p_billing_transaction_id: billingId,
      p_status: "failed",
      p_gateway_transaction_id: paymentId,
      p_gateway_response: verified,
      p_failure_code: "user_mismatch",
      p_failure_reason: "user_id_metadata_mismatch",
      p_review_required: true,
    });
    return json(200, { ok: false, reason: "user_id_metadata_mismatch" });
  }

  const expectedHalalas = halalasFromSarRow(row.amount);
  const paidHalalas = typeof verified.amount === "number"
    ? verified.amount
    : Number.parseInt(String(verified.amount ?? ""), 10);

  const expiresAt = row.expires_at ? Date.parse(String(row.expires_at)) : NaN;
  if (Number.isFinite(expiresAt) && Date.now() > expiresAt && row.status === "pending") {
    await svc.rpc("mark_billing_gateway_outcome", {
      p_billing_transaction_id: billingId,
      p_status: "expired",
      p_gateway_transaction_id: paymentId,
      p_gateway_response: verified,
      p_failure_code: "intent_expired",
      p_review_required: true,
    });
    if (Number.isFinite(paidHalalas) && paidHalalas > 0) {
      await refundMoyasarPayment(moyasarSecret, paymentId, paidHalalas);
    }
    return json(200, { ok: false, reason: "intent_expired", refund_attempted: true });
  }

  if (
    expectedHalalas == null ||
    !Number.isFinite(paidHalalas) ||
    paidHalalas !== expectedHalalas
  ) {
    await svc.rpc("mark_billing_gateway_outcome", {
      p_billing_transaction_id: billingId,
      p_status: "failed",
      p_gateway_transaction_id: paymentId,
      p_gateway_response: verified,
      p_failure_code: "amount_mismatch",
      p_failure_reason: "moyasar_amount_ne_billing",
      p_review_required: true,
    });
    if (Number.isFinite(paidHalalas) && paidHalalas > 0) {
      await refundMoyasarPayment(moyasarSecret, paymentId, paidHalalas);
    }
    return json(200, {
      ok: false,
      reason: "amount_mismatch",
      expectedHalalas,
      paidHalalas,
      refund_attempted: true,
    });
  }

  const cur = String(verified.currency ?? "SAR").toUpperCase();
  if (String(row.currency ?? "SAR").toUpperCase() !== cur) {
    await svc.rpc("mark_billing_gateway_outcome", {
      p_billing_transaction_id: billingId,
      p_status: "failed",
      p_gateway_transaction_id: paymentId,
      p_gateway_response: verified,
      p_failure_code: "currency_mismatch",
      p_failure_reason: "moyasar_currency_ne_billing",
      p_review_required: true,
    });
    if (Number.isFinite(paidHalalas) && paidHalalas > 0) {
      await refundMoyasarPayment(moyasarSecret, paymentId, paidHalalas);
    }
    return json(200, {
      ok: false,
      reason: "currency_mismatch",
      refund_attempted: true,
    });
  }

  if (row.status === "success" && row.fulfillment_applied_at) {
    return json(200, {
      ok: true,
      duplicate: true,
      billing_transaction_id: billingId,
    });
  }

  const marked = await svc.rpc("mark_billing_gateway_outcome", {
    p_billing_transaction_id: billingId,
    p_status: "success",
    p_gateway_transaction_id: paymentId,
    p_gateway_response: verified,
  });

  if (marked?.error) {
    return json(200, { ok: false, reason: "mark_failed", detail: marked.error.message });
  }

  const userId = String(row.user_id ?? "").trim();
  if (userId) {
    try {
      await upsertSavedCardFromMoyasarPayment(svc, userId, verified);
    } catch {
      // لا نفشل التفعيل إن فشل حفظ البطاقة.
    }
  }

  const { data: fulfilled, error: fulErr } = await svc.rpc("fulfill_paid_billing", {
    p_billing_transaction_id: billingId,
  });

  if (fulErr) {
    return json(200, {
      ok: true,
      billing_transaction_id: billingId,
      moyasar_payment_id: paymentId,
      fulfillment_warning: fulErr.message,
    });
  }

  return json(200, {
    ok: true,
    billing_transaction_id: billingId,
    moyasar_payment_id: paymentId,
    fulfillment: fulfilled,
  });
});
