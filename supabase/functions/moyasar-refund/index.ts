// Authenticated refund: instant unused credit only.
// Client: supabase.functions.invoke('moyasar-refund', { body: { credit_id } })
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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method_not_allowed" });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  const moyasarSecret = (Deno.env.get("MOYASAR_SECRET_KEY") ?? "").trim();
  if (!supabaseUrl || !serviceKey || !moyasarSecret) {
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
  const creditId = String(body.credit_id ?? "").trim();
  if (!creditId) {
    return json(400, { ok: false, error: "missing_credit_id" });
  }

  const userClient = createClient(supabaseUrl, serviceKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: prepared, error: prepErr } = await userClient.rpc(
    "prepare_instant_credit_refund",
    { p_credit_id: creditId },
  );
  if (prepErr) {
    return json(200, { ok: false, error: prepErr.message });
  }
  const prep = (prepared ?? {}) as Record<string, unknown>;
  if (prep.ok !== true) {
    return json(200, {
      ok: false,
      error: String(prep.error ?? "not_refundable"),
    });
  }

  const gatewayId = String(prep.gateway_transaction_id ?? "").trim();
  const halalas = Number(prep.amount_halalas ?? 0);
  if (!gatewayId || !Number.isFinite(halalas) || halalas < 1) {
    return json(200, { ok: false, error: "missing_gateway_id" });
  }

  const refundRes = await fetch(
    `${moyasarApiBase(moyasarSecret)}/payments/${encodeURIComponent(gatewayId)}/refund`,
    {
      method: "POST",
      headers: {
        Authorization: basicAuthHeader(moyasarSecret),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ amount: halalas }),
    },
  );
  const refundJson = await refundRes.json().catch(() => null);
  const refundStatus = String(
    (refundJson as Record<string, unknown> | null)?.status ?? "",
  ).toLowerCase();
  if (!refundRes.ok && refundStatus !== "refunded") {
    return json(200, {
      ok: false,
      error: "moyasar_refund_failed",
      moyasar_status: refundRes.status,
    });
  }

  const refundId = String(
    (refundJson as Record<string, unknown> | null)?.id ?? gatewayId,
  ).trim();

  const svc = createClient(supabaseUrl, serviceKey);
  const { data: applied, error: appErr } = await svc.rpc(
    "apply_instant_credit_refund",
    {
      p_credit_id: creditId,
      p_gateway_refund_id: refundId,
    },
  );
  if (appErr) {
    return json(200, { ok: false, error: appErr.message });
  }
  return json(200, { ok: true, refund: applied });
});
