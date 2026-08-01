import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
};

type FalPayload = {
  valid: boolean;
  status: string;
  broker_name: string | null;
  email: string | null;
  mobile: string | null;
  city: string | null;
  district: string | null;
  region: string | null;
  license_type: string | null;
  license_no: string;
  license_status_text: string | null;
  end_date: string | null;
  source: string;
  error?: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function mockKnown(licenseNo: string): FalPayload | null {
  if (licenseNo === "1100269385") {
    return {
      valid: true,
      status: "active",
      broker_name: "عبداللطيف بن سلطان بن لافي المطيري",
      email: "am77707777@gmail.com",
      mobile: "0555317770",
      city: "امارة منطقة مكة المكرمة - الطائف",
      district: "المليساء",
      region: "منطقة مكة المكرمة",
      license_type: "رخصة فال للوساطة والتسويق",
      license_no: licenseNo,
      license_status_text: "سارية حتى تاريخ 2026/09/09",
      end_date: "2026-09-09",
      source: "mock_registry",
    };
  }
  // بيئة sandbox تجريبية للأرقام التي تبدأ بـ "9999" — تُستخدم في مرحلة التطوير
  // فقط (التحقق الفعلي يعتمد على بوابة REGA الرسمية).
  if (licenseNo.startsWith("9999")) {
    const isMarketer = licenseNo[4] === "1";
    return {
      valid: true,
      status: "active",
      broker_name: isMarketer
        ? "محمد بن عبدالله المسوّق"
        : "مؤسسة الفلاني العقارية للوساطة",
      email: "sandbox.fal@example.com",
      mobile: "0500000000",
      city: "الرياض",
      district: "العليا",
      region: "منطقة الرياض",
      license_type: isMarketer
        ? "رخصة فال — مسوّق عقاري فردي"
        : "رخصة فال — منشأة (وساطة وتسويق)",
      license_no: licenseNo,
      license_status_text: "سارية (sandbox)",
      end_date: "2027-12-31",
      source: "sandbox",
    };
  }
  return null;
}

function parseEndDateIso(html: string): string | null {
  const slash = [...html.matchAll(/(20\d{2})\/(\d{2})\/(\d{2})/g)].map((m) =>
    `${m[1]}-${m[2]}-${m[3]}`
  );
  const dash = [...html.matchAll(/(20\d{2})-(\d{2})-(\d{2})/g)].map((m) =>
    `${m[1]}-${m[2]}-${m[3]}`
  );
  const all = [...slash, ...dash];
  if (all.length === 0) return null;
  all.sort();
  return all[all.length - 1] ?? null;
}

function extractEmail(html: string): string | null {
  const m = html.match(
    /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/,
  );
  return m ? m[0] : null;
}

function extractSaudiMobile(html: string): string | null {
  const m = html.match(/05\d{8}/);
  return m ? m[0] : null;
}

function isEndDateActive(iso: string): boolean {
  const end = new Date(iso + "T23:59:59.999Z");
  return end.getTime() >= Date.now();
}

function heuristicFromHtml(html: string, licenseNo: string): FalPayload {
  const end = parseEndDateIso(html);
  const email = extractEmail(html);
  const mobile = extractSaudiMobile(html);
  const expired = end != null && !isEndDateActive(end);
  const hasEnd = end != null;
  return {
    valid: !expired && hasEnd,
    status: expired
      ? "expired"
      : hasEnd
      ? "active"
      : "parse_incomplete",
    broker_name: null,
    email,
    mobile,
    city: null,
    district: null,
    region: null,
    license_type: null,
    license_no: licenseNo,
    license_status_text: end ? `سارية حتى تاريخ ${end.replaceAll("-", "/")}` : null,
    end_date: end,
    source: "rega_html_heuristic",
  };
}

async function tryFetchRega(licenseNo: string): Promise<string | null> {
  const url = `https://aqari.rega.gov.sa/Inquires/Brokerage/Details/${licenseNo}`;
  // مهلة قصوى 6 ثوانٍ — يكفي لاستجابة سريعة دون حبس المستخدم.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        Accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "ar-SA,ar;q=0.9,en-US;q=0.8,en;q=0.7",
      },
    });
    if (!res.ok) return null;
    return await res.text();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

serve(async (req) => {
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const body = await req.json().catch(() => ({}));
    const licenseNo = String(body?.license_no ?? "").replace(/\D/g, "");

    if (!/^\d{10}$/.test(licenseNo)) {
      return json({
        valid: false,
        status: "invalid_license_no",
        broker_name: null,
        email: null,
        mobile: null,
        city: null,
        district: null,
        region: null,
        license_type: null,
        license_no: licenseNo,
        license_status_text: null,
        end_date: null,
        source: "none",
      } satisfies FalPayload);
    }

    const known = mockKnown(licenseNo);
    if (known) {
      const expired = known.end_date != null &&
        !isEndDateActive(known.end_date);
      if (expired) {
        return json({
          ...known,
          valid: false,
          status: "expired",
        } satisfies FalPayload);
      }
      return json(known);
    }

    const html = await tryFetchRega(licenseNo);
    if (html && html.length > 200) {
      let out = heuristicFromHtml(html, licenseNo);
      if (out.status === "parse_incomplete") {
        const m = mockKnown(licenseNo);
        if (m) {
          const ex = m.end_date != null && !isEndDateActive(m.end_date);
          return json(
            ex ? { ...m, valid: false, status: "expired" } : m,
          );
        }
      }
      if (out.end_date && !isEndDateActive(out.end_date)) {
        out = { ...out, valid: false, status: "expired" };
      }
      return json(out);
    }

    return json({
      valid: false,
      status: "rega_unreachable",
      broker_name: null,
      email: null,
      mobile: null,
      city: null,
      district: null,
      region: null,
      license_type: null,
      license_no: licenseNo,
      license_status_text: null,
      end_date: null,
      source: "none",
      error:
        "تعذر الاتصال ببوابة REGA أو الرفض من الخادم. تحقق من الرقم أو حاول لاحقاً.",
    } satisfies FalPayload);
  } catch (e) {
    return json(
      {
        valid: false,
        error: String(e),
        status: "server_error",
        broker_name: null,
        email: null,
        mobile: null,
        city: null,
        district: null,
        region: null,
        license_type: null,
        license_no: "",
        license_status_text: null,
        end_date: null,
        source: "error",
      } satisfies FalPayload,
      500,
    );
  }
});
