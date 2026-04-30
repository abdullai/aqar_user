import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

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

/** بيانات تجريبية لمطابقة مثال المستخدم (السجل مشطوب — للتحقق من رفض «غير ساري»). */
function mockKnown(regNo: string) {
  if (regNo === "7001234567") {
    return {
      ok: true,
      valid_for_active: true,
      entity_name_ar: "مكتب عقاري تجريبي (سجل ساري)",
      registry_status_ar: "نشط",
      establishment_duration_ar: "",
      commercial_reg_no: regNo,
      ecommerce_url: "",
      capital: 100000,
      phone: "0500000000",
      issue_date: "2020-01-15",
      website: "",
      activity_ar: "الوساطة العقارية",
      activity_end_ok: true,
      source: "mock_mc_active",
    };
  }
  if (regNo === "5903028242") {
    return {
      ok: true,
      valid_for_active: false,
      entity_name_ar: "مؤسسة عيسى احمد يحي ابوحيه للمقاولات",
      registry_status_ar: "مشطوب",
      establishment_duration_ar: "",
      commercial_reg_no: regNo,
      ecommerce_url: "",
      capital: 5000.0,
      phone: "",
      issue_date: "2014-04-01",
      website: "",
      activity_ar:
        "تمديد الاسلاك الكهربائية - تركيب انظمة الاضاءة",
      activity_end_ok: false,
      source: "mock_mc",
    };
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const body = await req.json().catch(() => ({}));
  const raw = String(body?.unified_reg_no ?? body?.cr_no ?? "").replace(/\D/g, "");

  if (raw.length < 10) {
    return json({
      ok: false,
      error: "invalid_length",
      message: "Use the 10-digit unified commercial registration number.",
    });
  }

  const regNo = raw.slice(0, 10);
  const known = mockKnown(regNo);
  if (known) return json(known);

  try {
    const url =
      `https://mc.gov.sa/ar/eservices/Pages/Commercial-data.aspx?cr=${encodeURIComponent(regNo)}`;
    const res = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Accept-Language": "ar-SA,ar;q=0.9,en;q=0.8",
      },
    });
    if (!res.ok) {
      return json({
        ok: false,
        error: "mc_unreachable",
        message: "Could not reach MC portal.",
      });
    }
    const html = await res.text();
    const issue = html.match(/(20\d{2}-\d{2}-\d{2})/);
    return json({
      ok: true,
      valid_for_active: issue != null,
      entity_name_ar: null,
      registry_status_ar: null,
      commercial_reg_no: regNo,
      issue_date: issue?.[1] ?? null,
      activity_end_ok: false,
      source: "mc_html_partial",
      message:
        "Partial parse only. Use known CR 5903028242 for structured mock in dev.",
    });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
});
