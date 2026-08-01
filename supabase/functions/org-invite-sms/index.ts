/**
 * Placeholder for future SMS when a team invitation is created.
 * Wire from DB webhook or call from `org_create_team_invitation` when SMS provider is ready.
 */
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const body = await req.json().catch(() => ({}));
  const mobile = String(body?.mobile ?? body?.mobile_local ?? "").trim();
  const nationalId = String(body?.national_id ?? "").replace(/\D/g, "");

  // TODO: integrate SMS provider (Unifonic, Twilio, etc.)
  console.log("[org-invite-sms] queued", { mobile, nationalId });

  return new Response(
    JSON.stringify({ ok: true, queued: true, sms: "not_configured" }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
