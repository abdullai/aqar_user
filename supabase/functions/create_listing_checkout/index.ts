// deno-lint-ignore-file no-explicit-any
// Hosted checkout for listing / escrow payments (Stripe when configured).
// Moyasar: add server-side integration with MOYASAR_SECRET_KEY (Saudi cards / Mada).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import Stripe from "https://esm.sh/stripe@14.21.0?target=deno";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Body = {
  payment_event_id?: string;
  success_url?: string;
  cancel_url?: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "missing_authorization" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (!supabaseUrl || !anonKey || !serviceKey) {
    return new Response(JSON.stringify({ error: "server_misconfigured" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const paymentEventId = (body.payment_event_id ?? "").trim();
  if (!paymentEventId) {
    return new Response(JSON.stringify({ error: "payment_event_id_required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user?.id) {
    return new Response(JSON.stringify({ error: "invalid_session" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  const uid = userData.user.id;

  const svc = createClient(supabaseUrl, serviceKey);
  const { data: ev, error: evErr } = await svc
    .from("listing_payment_events")
    .select(
      "id,initiator_id,property_id,amount_sar,provider,status,kind,metadata",
    )
    .eq("id", paymentEventId)
    .maybeSingle();

  if (evErr || !ev) {
    return new Response(JSON.stringify({ error: "payment_event_not_found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (ev.initiator_id !== uid) {
    return new Response(JSON.stringify({ error: "forbidden" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (ev.status !== "pending_gateway") {
    return new Response(
      JSON.stringify({ error: "event_not_pending_gateway", status: ev.status }),
      {
        status: 409,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  if (ev.provider === "moyasar") {
    return new Response(
      JSON.stringify({
        configured: false,
        provider: "moyasar",
        hint:
          "Saudi stack: implement Moyasar Payments API server-side (secret key in vault). " +
          "Return hosted payment URL or 3DS payload to the app.",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  if (ev.provider !== "stripe") {
    return new Response(
      JSON.stringify({
        error: "checkout_only_for_stripe_or_moyasar_stub",
        provider: ev.provider,
      }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
  if (!stripeSecret) {
    return new Response(
      JSON.stringify({
        configured: false,
        provider: "stripe",
        hint: "Set STRIPE_SECRET_KEY in Edge Function secrets to enable Checkout.",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const stripe = new Stripe(stripeSecret, {
    apiVersion: "2023-10-16",
  });

  const amount = Number(ev.amount_sar);
  if (!Number.isFinite(amount) || amount <= 0) {
    return new Response(JSON.stringify({ error: "invalid_amount" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const unitAmount = Math.round(amount * 100);
  if (unitAmount < 50) {
    return new Response(
      JSON.stringify({ error: "amount_too_small_for_stripe" }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const origin = new URL(req.url).origin;
  const successUrl = body.success_url ??
    `${origin}/listing-payment-return?status=success&event=${paymentEventId}`;
  const cancelUrl = body.cancel_url ??
    `${origin}/listing-payment-return?status=cancel&event=${paymentEventId}`;

  try {
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      customer_email: userData.user.email ?? undefined,
      line_items: [
        {
          price_data: {
            currency: "sar",
            product_data: {
              name: `Aqar — ${ev.kind}`,
              metadata: { property_id: ev.property_id },
            },
            unit_amount: unitAmount,
          },
          quantity: 1,
        },
      ],
      success_url: successUrl,
      cancel_url: cancelUrl,
      metadata: {
        payment_event_id: paymentEventId,
        property_id: ev.property_id,
        supabase_user_id: uid,
      },
    });

    return new Response(
      JSON.stringify({
        configured: true,
        checkout_url: session.url,
        stripe_session_id: session.id,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e: any) {
    return new Response(
      JSON.stringify({
        error: "stripe_checkout_failed",
        message: e?.message ?? String(e),
      }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
