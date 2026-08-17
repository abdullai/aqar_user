// deno-lint-ignore-file no-explicit-any
// Scheduled auto-renew (Supabase Dashboard → Edge Functions → Schedules, or external cron):
//   POST https://<project>.supabase.co/functions/v1/subscription-renew-cron
//   Header: x-subscription-cron-secret: <SUBSCRIPTION_CRON_SECRET>
//
// Secrets (same project as moyasar-webhook):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   MOYASAR_SECRET_KEY, MOYASAR_CALLBACK_URL  (callback required for token payments)
//   SUBSCRIPTION_CRON_SECRET                  (required — do not expose publicly)
//
// Flow: picks active subscriptions with auto_renew whose ends_at is within a renewal window,
// skips if a recent pending billing exists, loads default saved_cards token, creates
// billing_transactions (pending), POSTs Moyasar /v1/payments with metadata.purpose=auto_renew.
// If Moyasar returns paid immediately, marks billing success; webhook + webhook helper extend
// the subscription when purpose=auto_renew. If initiated (3DS), leaves pending for webhook.
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

function halalasFromSar(amount: number): number {
  return Math.round(amount * 100);
}

function merchantContact(): string {
  return (Deno.env.get("MOYASAR_METADATA_MERCHANT_CONTACT") ?? "").trim() ||
    "Abdullah Issa Ahmed Abuhia";
}

async function hasRecentPendingBilling(
  svc: ReturnType<typeof createClient>,
  subscriptionId: string,
): Promise<boolean> {
  const since = new Date(Date.now() - 2 * 3600 * 1000).toISOString();
  const { data, error } = await svc
    .from("billing_transactions")
    .select("id")
    .eq("subscription_id", subscriptionId)
    .eq("status", "pending")
    .gte("created_at", since)
    .limit(1);
  if (error) return true;
  return (data?.length ?? 0) > 0;
}

serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { error: "method_not_allowed" });
  }

  const expected = (Deno.env.get("SUBSCRIPTION_CRON_SECRET") ?? "").trim();
  const hdr = (req.headers.get("x-subscription-cron-secret") ?? "").trim();
  if (!expected || hdr !== expected) {
    return json(401, { error: "invalid_cron_secret" });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const moyasarSecret = (Deno.env.get("MOYASAR_SECRET_KEY") ?? "").trim();
  const callbackUrl = (Deno.env.get("MOYASAR_CALLBACK_URL") ?? "").trim();

  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: "supabase_misconfigured" });
  }
  if (!moyasarSecret || !callbackUrl) {
    return json(200, {
      ok: true,
      skipped: true,
      reason: "moyasar_secret_or_callback_missing",
    });
  }

  const svc = createClient(supabaseUrl, serviceKey);
  const now = new Date();
  const soon = new Date(now.getTime() + 36 * 3600 * 1000).toISOString();
  const past = new Date(now.getTime() - 14 * 24 * 3600 * 1000).toISOString();

  const { data: subs, error: qErr } = await svc
    .from("user_subscriptions")
    .select("id,user_id,plan_id,period,ends_at,status,auto_renew")
    .eq("auto_renew", true)
    .eq("status", "active")
    .lte("ends_at", soon)
    .gt("ends_at", past)
    .limit(20);

  if (qErr) {
    return json(500, { error: "query_failed", detail: qErr.message });
  }

  const results: Record<string, unknown>[] = [];

  for (const raw of subs ?? []) {
    const s = raw as Record<string, unknown>;
    const subId = String(s.id ?? "").trim();
    const userId = String(s.user_id ?? "").trim();
    const planId = String(s.plan_id ?? "").trim();
    const period = String(s.period ?? "monthly").trim();
    if (!subId || !userId || !planId) {
      results.push({ subscription_id: subId, skipped: "bad_row" });
      continue;
    }

    const { data: planRow, error: pErr } = await svc
      .from("subscription_plans")
      .select("price_monthly,price_yearly")
      .eq("id", planId)
      .maybeSingle();
    if (pErr || !planRow) {
      results.push({ subscription_id: subId, error: "plan_fetch" });
      continue;
    }
    const plan = planRow as Record<string, unknown>;

    if (await hasRecentPendingBilling(svc, subId)) {
      results.push({ subscription_id: subId, skipped: "pending_billing_recent" });
      continue;
    }

    const { data: cards, error: cErr } = await svc
      .from("saved_cards")
      .select("id,card_token")
      .eq("user_id", userId)
      .order("is_default", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1);

    if (cErr || !cards?.length) {
      await svc.from("user_subscriptions").update({
        auto_renew_last_failure_at: new Date().toISOString(),
        auto_renew_last_failure_reason: "no_saved_card",
      }).eq("id", subId);
      results.push({ subscription_id: subId, error: "no_saved_card" });
      continue;
    }

    const cardId = String(cards[0].id ?? "").trim();
    const token = String(cards[0].card_token ?? "").trim();
    if (!token) {
      results.push({ subscription_id: subId, error: "empty_token" });
      continue;
    }

    const monthly = typeof plan.price_monthly === "number"
      ? plan.price_monthly
      : Number.parseFloat(String(plan.price_monthly ?? "0"));
    const yearly = typeof plan.price_yearly === "number"
      ? plan.price_yearly
      : Number.parseFloat(String(plan.price_yearly ?? "0"));
    const amountSar = period === "yearly" ? yearly : monthly;
    if (!Number.isFinite(amountSar) || amountSar <= 0) {
      results.push({ subscription_id: subId, error: "bad_plan_price" });
      continue;
    }

    const { data: ins, error: insErr } = await svc.from("billing_transactions").insert({
      user_id: userId,
      subscription_id: subId,
      amount: amountSar,
      currency: "SAR",
      status: "pending",
      payment_method: "card_auto_renew",
      card_id: cardId,
      title_ar: "تجديد اشتراك تلقائي",
      title_en: "Subscription auto-renewal",
      gateway_response: {
        pending_gateway: "moyasar",
        cron: "subscription-renew-cron",
      },
    }).select("id").single();

    if (insErr || !ins?.id) {
      results.push({ subscription_id: subId, error: insErr?.message ?? "insert_failed" });
      continue;
    }

    const billingId = String(ins.id).trim();
    const meta = {
      billing_transaction_id: billingId,
      user_id: userId,
      purpose: "auto_renew",
      merchant_contact: merchantContact(),
      product: "aqar_reliable",
    };

    const body = {
      given_id: billingId,
      amount: halalasFromSar(amountSar),
      currency: "SAR",
      description: "Aqar subscription auto-renewal",
      callback_url: callbackUrl,
      metadata: meta,
      source: {
        type: "token",
        token,
        "3ds": true,
        manual: false,
      },
    };

    let payJson: any = null;
    try {
      const payRes = await fetch(`${moyasarApiBase(moyasarSecret)}/payments`, {
        method: "POST",
        headers: {
          Authorization: basicAuthHeader(moyasarSecret),
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
      payJson = await payRes.json().catch(() => null);
      if (!payRes.ok) {
        await svc.from("billing_transactions").update({
          status: "failed",
          gateway_response: { moyasar_http_error: payRes.status, body: payJson },
          completed_at: new Date().toISOString(),
        }).eq("id", billingId).eq("status", "pending");
        await svc.from("user_subscriptions").update({
          auto_renew_last_failure_at: new Date().toISOString(),
          auto_renew_last_failure_reason: `moyasar_http_${payRes.status}`,
        }).eq("id", subId);
        results.push({ subscription_id: subId, billing_id: billingId, error: "moyasar_http", status: payRes.status });
        continue;
      }
    } catch (e) {
      await svc.from("billing_transactions").update({
        status: "failed",
        gateway_response: { network_error: String(e) },
        completed_at: new Date().toISOString(),
      }).eq("id", billingId).eq("status", "pending");
      await svc.from("user_subscriptions").update({
        auto_renew_last_failure_at: new Date().toISOString(),
        auto_renew_last_failure_reason: "moyasar_network",
      }).eq("id", subId);
      results.push({ subscription_id: subId, billing_id: billingId, error: "network" });
      continue;
    }

    const st = String(payJson?.status ?? "").toLowerCase();
    const payId = payJson?.id != null ? String(payJson.id).trim() : "";

    if (st === "paid" || st === "captured") {
      await svc.from("billing_transactions").update({
        status: "success",
        gateway_transaction_id: payId,
        gateway_response: payJson,
        completed_at: new Date().toISOString(),
      }).eq("id", billingId).eq("status", "pending");
      const { error: rpcErr } = await svc.rpc("subscription_apply_auto_renew_extension", {
        p_subscription_id: subId,
        p_billing_transaction_id: billingId,
      });
      if (rpcErr) {
        results.push({
          subscription_id: subId,
          billing_id: billingId,
          moyasar_status: st,
          rpc_error: rpcErr.message,
        });
      } else {
        results.push({ subscription_id: subId, billing_id: billingId, moyasar_status: st, pay_id: payId });
      }
    } else if (st === "failed" || st === "voided") {
      await svc.from("billing_transactions").update({
        status: "failed",
        gateway_transaction_id: payId || null,
        gateway_response: payJson,
        completed_at: new Date().toISOString(),
      }).eq("id", billingId).eq("status", "pending");
      await svc.from("user_subscriptions").update({
        auto_renew_last_failure_at: new Date().toISOString(),
        auto_renew_last_failure_reason: st,
      }).eq("id", subId);
      results.push({ subscription_id: subId, billing_id: billingId, moyasar_status: st });
    } else {
      // initiated / pending 3DS — leave billing pending; webhook finalizes
      await svc.from("billing_transactions").update({
        gateway_transaction_id: payId || null,
        gateway_response: payJson,
      }).eq("id", billingId).eq("status", "pending");
      results.push({ subscription_id: subId, billing_id: billingId, moyasar_status: st, note: "awaiting_webhook" });
    }
  }

  return json(200, { ok: true, count: results.length, results });
});
