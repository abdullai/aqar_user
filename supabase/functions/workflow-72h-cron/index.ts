// deno-lint-ignore-file no-explicit-any
//
// 72-hour Marketing Workflow Expirations — scheduled.
//
// تَستدعي RPC `cron_run_72h_workflow_expirations()` التي تُحوّل التصاريح
// والعقود المنتهية المهلة إلى `owner_action_required`، وتَفسخ العقود
// غير الموقَّعة، وتُرسل الإشعارات للمالك والمسوّق.
//
// Schedule (Supabase Dashboard → Edge Functions → Schedules): every 10 minutes.
//   POST https://<project>.supabase.co/functions/v1/workflow-72h-cron
//   Header: x-workflow-cron-secret: <WORKFLOW_CRON_SECRET>
//
// Required env vars:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   WORKFLOW_CRON_SECRET   (any random string ≥ 32 chars)
//
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { error: "method_not_allowed" });
  }

  const expected = (Deno.env.get("WORKFLOW_CRON_SECRET") ?? "").trim();
  const hdr = (req.headers.get("x-workflow-cron-secret") ?? "").trim();
  if (!expected || hdr !== expected) {
    return json(401, { error: "invalid_cron_secret" });
  }

  const supabaseUrl = (Deno.env.get("SUPABASE_URL") ?? "").trim();
  const serviceKey = (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "").trim();
  if (!supabaseUrl || !serviceKey) {
    return json(500, { error: "supabase_misconfigured" });
  }

  const svc = createClient(supabaseUrl, serviceKey);
  try {
    const { data, error } = await svc.rpc("cron_run_72h_workflow_expirations");
    if (error) {
      return json(500, { error: "rpc_failed", detail: error.message });
    }
    return json(200, { ok: true, ran_at: new Date().toISOString(), result: data });
  } catch (e) {
    return json(500, { error: "exception", detail: String(e) });
  }
});
