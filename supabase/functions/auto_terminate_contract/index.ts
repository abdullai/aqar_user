import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: cors,
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const expected = (Deno.env.get("AUTO_TERMINATE_CONTRACT_CRON_SECRET") ?? "")
    .trim();
  const got = (req.headers.get("x-cron-secret") ?? "").trim();

  if (!url || !serviceKey) {
    return json({ error: "server_misconfigured" }, 500);
  }
  if (!expected || got !== expected) {
    return json({ error: "forbidden" }, 403);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await admin.rpc("auto_terminate_expired_permit_contracts");
  if (error) {
    return json({ ok: false, error: error.message }, 500);
  }
  return json({ ok: true, result: data }, 200);
});
