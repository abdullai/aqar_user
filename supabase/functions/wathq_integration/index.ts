export {};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

type JsonObject = Record<string, unknown>;

function response(body: JsonObject, status = 200): Response {
  return new Response(JSON.stringify({ ...body, statusCode: status }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function failure(status: number, error: string, message: string): Response {
  return response({ success: false, error, message }, status);
}

function value(input: unknown): string {
  return typeof input === "string" ? input.trim() : "";
}

const deedIdTypes = new Set([
  "National_ID",
  "Resident_ID",
  "Passport",
  "CR_NO",
  "Endowment_Deed_No",
  "license_No",
  "Foreign_CR_No",
  "Gov_National_ID",
]);

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return failure(405, "method_not_allowed", "Use POST for Wathq requests.");
  }

  let body: JsonObject;
  try {
    const parsed: unknown = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return failure(400, "invalid_body", "The request body must be an object.");
    }
    body = parsed as JsonObject;
  } catch {
    return failure(400, "invalid_json", "The request body must be valid JSON.");
  }

  const action = value(body.action);
  const crNumber = value(body.crNumber);
  const deedNumber = value(body.deedNumber);
  const idNumber = value(body.idNumber);
  const idType = value(body.idType);
  const language = value(body.language) || "ar";
  let resourceType: string;
  let identifier: string;
  let providerPath: string;

  if (action === "get_commercial_registration" || action === "get_national_address") {
    if (!/^\d{10}$/.test(crNumber)) {
      return failure(400, "invalid_cr_number", "crNumber must contain 10 digits.");
    }
    identifier = crNumber;
    if (action === "get_commercial_registration") {
      if (!["ar", "en"].includes(language)) {
        return failure(400, "invalid_language", "language must be ar or en.");
      }
      resourceType = "commercial_registration";
      providerPath = `/sandbox/commercial-registration/info/${crNumber}?language=${language}`;
    } else {
      resourceType = "national_address";
      providerPath = `/spl/national/address/info/${crNumber}`;
    }
  } else if (action === "get_real_estate_deed") {
    if (!/^\d{1,50}$/.test(deedNumber) ||
      !/^[A-Za-z0-9-]{1,50}$/.test(idNumber) || !deedIdTypes.has(idType)) {
      return failure(400, "invalid_deed_parameters", "Provide a valid deedNumber, idNumber and idType.");
    }
    resourceType = "real_estate_deed";
    identifier = deedNumber;
    providerPath = `/moj/real-estate/deed/${encodeURIComponent(deedNumber)}/${encodeURIComponent(idNumber)}/${encodeURIComponent(idType)}`;
  } else {
    return failure(400, "invalid_action", "Unknown or unsupported Wathq action.");
  }

  const authorization = req.headers.get("authorization") ?? "";
  if (!/^Bearer \S+$/i.test(authorization)) {
    return failure(401, "authentication_required", "A user access token is required.");
  }
  const supabaseUrl = value(Deno.env.get("SUPABASE_URL")).replace(/\/+$/, "");
  const anonKey = value(Deno.env.get("SUPABASE_ANON_KEY"));
  const serviceKey = value(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
  const apiKey = value(Deno.env.get("WATHQ_API_KEY"));
  if (!supabaseUrl || !anonKey || !serviceKey || !apiKey) {
    return failure(503, "not_configured", "Wathq or Supabase server configuration is missing.");
  }

  try {
    const auth = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: anonKey, Authorization: authorization },
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
    if (!auth.ok) {
      if (auth.status === 401 || auth.status === 403) {
        return failure(401, "invalid_session", "The user session is invalid or expired.");
      }
      return failure(503, "auth_unavailable", "Could not verify the user session.");
    }
    const user = await auth.json() as JsonObject;
    const userId = value(user.id);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId)) {
      return failure(503, "invalid_auth_response", "The authentication service returned an invalid user.");
    }

    const query = new URLSearchParams({
      select: "id",
      user_id: `eq.${userId}`,
      resource_type: `eq.${resourceType}`,
      identifier: `eq.${identifier}`,
      owner_id: `eq.${resourceType === "real_estate_deed" ? idNumber : ""}`,
      owner_id_type: `eq.${resourceType === "real_estate_deed" ? idType : ""}`,
      limit: "1",
    });
    const grantResponse = await fetch(`${supabaseUrl}/rest/v1/wathq_access_grants?${query}`, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      redirect: "error",
      signal: AbortSignal.timeout(15000),
    });
    if (!grantResponse.ok) {
      console.error("Wathq authorization lookup failed:", grantResponse.status);
      return failure(503, "authorization_unavailable", "Could not verify access to this resource.");
    }
    const grants: unknown = await grantResponse.json();
    if (!Array.isArray(grants)) {
      return failure(503, "invalid_authorization_response", "Could not verify access to this resource.");
    }
    if (grants.length === 0) {
      return failure(403, "access_denied", "Access to this resource has not been granted.");
    }

    const upstream = await fetch(`https://api.wathq.sa${providerPath}`, {
      headers: { apiKey, Accept: "application/json" },
      redirect: "error",
      signal: AbortSignal.timeout(30000),
    });
    if (!upstream.ok) {
      console.error("Wathq API request failed:", upstream.status);
      const status = [400, 404, 429].includes(upstream.status) ? upstream.status : 502;
      return failure(status, "wathq_request_failed", "The Wathq service could not complete the request.");
    }
    let data: unknown;
    try {
      data = await upstream.json();
    } catch {
      return failure(502, "invalid_wathq_response", "The Wathq service returned invalid JSON.");
    }
    if (data === null || typeof data !== "object") {
      return failure(502, "invalid_wathq_response", "The Wathq service returned invalid data.");
    }
    if (action === "get_national_address" && !Array.isArray(data)) data = [data];
    if (action === "get_real_estate_deed" && !Array.isArray(data)) {
      data = (data as JsonObject).deedDetails ?? data;
    }
    return response({ success: true, data });
  } catch (error) {
    console.error("Wathq integration request failed:", error instanceof Error ? error.name : "unknown");
    return failure(502, "upstream_unavailable", "A required service is unavailable.");
  }
});
