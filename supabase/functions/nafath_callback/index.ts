// This Edge Function is intentionally disabled: Nafath requires the callback
// endpoint itself to be hosted in Saudi Arabia. Deploy server.mjs there instead.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(() => new Response(
  JSON.stringify({ error: "callback_must_be_hosted_in_saudi_arabia" }),
  {
    status: 410,
    headers: { "content-type": "application/json; charset=utf-8" },
  },
));
