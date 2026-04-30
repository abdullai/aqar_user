import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const emailDomain =
    (Deno.env.get("INVITE_EMAIL_DOMAIN") ?? "users.internal.aqar").trim();

  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "Server misconfigured" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return json({ error: "Missing authorization" }, 401);
  }

  const body = await req.json().catch(() => ({}));
  const nationalId = String(body?.national_id ?? body?.nationalId ?? "")
    .replace(/\D/g, "");
  const tempPassword = String(body?.temp_password ?? body?.tempPassword ?? "");
  const permissions =
    typeof body?.permissions === "object" && body?.permissions !== null
      ? body.permissions
      : {};

  if (!/^\d{10}$/.test(nationalId)) {
    return json({ error: "invalid_national_id" }, 400);
  }
  if (tempPassword.length < 8) {
    return json({ error: "password_too_short" }, 400);
  }

  const anon = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });

  const { data: inviterData, error: inviterErr } = await anon.auth.getUser(jwt);
  if (inviterErr || !inviterData?.user) {
    return json({ error: "invalid_session" }, 401);
  }
  const inviterId = inviterData.user.id;

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: org, error: orgErr } = await admin
    .from("org_units")
    .select("id, account_type, base_seat_limit, purchased_extra_seats")
    .eq("owner_user_id", inviterId)
    .maybeSingle();

  if (orgErr || !org) {
    return json({ error: "not_org_owner" }, 403);
  }

  const { count: memberCount, error: cntErr } = await admin
    .from("org_memberships")
    .select("user_id", { count: "exact", head: true })
    .eq("org_id", org.id)
    .eq("status", "active");

  if (cntErr) {
    return json({ error: "count_failed", details: cntErr.message }, 500);
  }

  const limit =
    (org.base_seat_limit ?? 0) + (org.purchased_extra_seats ?? 0);
  if ((memberCount ?? 0) >= limit) {
    return json({ error: "seat_limit_reached", limit }, 400);
  }

  const email = `${nationalId}@${emailDomain}`.toLowerCase();

  const { data: existingProfile, error: profLookupErr } = await admin
    .from("users_profiles")
    .select("user_id, org_id, username, national_id")
    .or(`username.eq.${nationalId},national_id.eq.${nationalId}`)
    .maybeSingle();

  if (profLookupErr) {
    return json(
      { error: "profile_lookup_failed", details: profLookupErr.message },
      500,
    );
  }

  let newUserId: string;

  if (existingProfile?.user_id) {
    if (existingProfile.org_id) {
      return json({ error: "user_already_in_org" }, 400);
    }
    newUserId = existingProfile.user_id as string;

    const { error: upAuthErr } = await admin.auth.admin.updateUserById(
      newUserId,
      { password: tempPassword, email_confirm: true },
    );
    if (upAuthErr) {
      return json(
        { error: "auth_update_failed", details: upAuthErr.message },
        500,
      );
    }

    const { error: upProfErr } = await admin
      .from("users_profiles")
      .update({
        org_id: org.id,
        must_change_password: true,
        account_type: org.account_type,
      })
      .eq("user_id", newUserId);

    if (upProfErr) {
      return json(
        { error: "profile_update_failed", details: upProfErr.message },
        500,
      );
    }
  } else {
    const { data: created, error: createErr } = await admin.auth.admin
      .createUser({
        email,
        password: tempPassword,
        email_confirm: true,
        user_metadata: { username: nationalId },
      });

    if (createErr || !created?.user) {
      const msg = createErr?.message ?? "create_failed";
      if (msg.includes("already been registered")) {
        return json({ error: "email_already_registered" }, 400);
      }
      return json({ error: "create_user_failed", details: msg }, 500);
    }

    newUserId = created.user.id;

    const { error: insProfErr } = await admin.from("users_profiles").upsert(
      {
        user_id: newUserId,
        username: nationalId,
        national_id: nationalId,
        org_id: org.id,
        must_change_password: true,
        account_type: org.account_type,
        status: "active",
        verification_status: "none",
      },
      { onConflict: "user_id" },
    );

    if (insProfErr) {
      try {
        await admin.auth.admin.deleteUser(newUserId);
      } catch (_) {
        /* ignore */
      }
      return json(
        { error: "profile_insert_failed", details: insProfErr.message },
        500,
      );
    }
  }

  const { error: memErr } = await admin.from("org_memberships").upsert(
    {
      org_id: org.id,
      user_id: newUserId,
      member_role: "member",
      permissions,
      status: "active",
      invited_by_user_id: inviterId,
    },
    { onConflict: "user_id", ignoreDuplicates: false },
  );

  if (memErr) {
    return json(
      { error: "membership_failed", details: memErr.message },
      500,
    );
  }

  await admin.from("org_activity_log").insert({
    org_id: org.id,
    actor_user_id: inviterId,
    action: "member.invited",
    entity_type: "user",
    entity_id: newUserId,
    metadata: { national_id: nationalId },
  });

  return json({
    ok: true,
    user_id: newUserId,
    national_id: nationalId,
    email_hint: email,
  });
});
