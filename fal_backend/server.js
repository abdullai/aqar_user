import express from "express";
import cors from "cors";
import fs from "fs";
import { chromium } from "playwright";

const app = express();

app.use(cors());
app.use(express.json({ limit: "1mb" }));

const PORT = 8787;

function onlyDigits(v) {
  return String(v ?? "").replace(/\D/g, "");
}

function norm(v) {
  return String(v ?? "").replace(/\s+/g, " ").trim();
}

function parseDateToIso(text) {
  const m = String(text || "").match(/(\d{2})\/(\d{2})\/(\d{4})/);
  if (!m) return null;
  const [, dd, mm, yyyy] = m;
  return `${yyyy}-${mm}-${dd}`;
}

async function clickIfExists(page, selectors, timeout = 12000) {
  for (const s of selectors) {
    try {
      const loc = page.locator(s).first();
      await loc.waitFor({ state: "visible", timeout });
      await loc.click({ timeout });
      return true;
    } catch (_) {}
  }
  return false;
}

async function getVisibleLocator(page, selectors, timeout = 15000) {
  for (const s of selectors) {
    try {
      const loc = page.locator(s).first();
      await loc.waitFor({ state: "visible", timeout });
      return loc;
    } catch (_) {}
  }
  return null;
}

async function extractResult(page, license) {
  const bodyText = norm(await page.locator("body").innerText());

  const result = {
    valid: false,
    owner_name: null,
    national_id: null,
    phone: null,
    email: null,
    region: null,
    city: null,
    district: null,
    broker_type: null,
    license_type: null,
    license_no: license,
    start_date: null,
    end_date: null,
    status: "unknown",
    status_text: null,
    raw_page: bodyText.substring(0, 4000),
  };

  const lines = bodyText
    .split("\n")
    .map((x) => norm(x))
    .filter(Boolean);

  function valueAfter(label) {
    const idx = lines.findIndex((x) => x === label || x.includes(label));
    if (idx >= 0 && idx + 1 < lines.length) return lines[idx + 1];
    return "";
  }

  result.owner_name =
    valueAfter("اسم الوسيط") ||
    valueAfter("اسم الوسيط فرد / المنشأة") ||
    valueAfter("الاسم") ||
    null;

  result.national_id =
    valueAfter("رقم الهوية") ||
    valueAfter("رقم الهوية / السجل التجاري") ||
    null;

  result.phone =
    valueAfter("رقم الجوال") ||
    valueAfter("الجوال") ||
    valueAfter("الهاتف") ||
    null;

  result.email =
    valueAfter("البريد الإلكتروني") ||
    valueAfter("البريد الالكتروني") ||
    null;

  result.region = valueAfter("المنطقة") || null;
  result.city = valueAfter("المدينة") || null;
  result.district = valueAfter("الحي") || null;
  result.broker_type = valueAfter("نوع الوسيط") || null;
  result.license_type = valueAfter("نوع الرخصة") || null;

  const startText =
    valueAfter("تاريخ بداية الرخصة") ||
    valueAfter("تاريخ البداية") ||
    "";

  const endText =
    valueAfter("تاريخ انتهاء الرخصة") ||
    valueAfter("تاريخ النهاية") ||
    "";

  result.start_date = parseDateToIso(startText);
  result.end_date = parseDateToIso(endText);

  const statusText =
    valueAfter("حالة الرخصة") ||
    lines.find((x) => x.includes("سارية")) ||
    lines.find((x) => x.includes("منتهية")) ||
    "";

  result.status_text = statusText || null;

  if (statusText.includes("سارية")) {
    result.status = "active";
  } else if (statusText.includes("منتهية")) {
    result.status = "expired";
  }

  result.valid = !!(
    result.owner_name ||
    result.national_id ||
    result.phone ||
    result.email ||
    result.status_text ||
    result.start_date ||
    result.end_date
  );

  return result;
}

async function fillInputRobustly(locator, value) {
  await locator.click();
  await locator.fill("");
  await locator.type(value, { delay: 80 });

  await locator.evaluate((el, v) => {
    el.value = v;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    el.dispatchEvent(new Event("blur", { bubbles: true }));
  }, value);
}

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.post("/verify-fal-license", async (req, res) => {
  const license = onlyDigits(req.body?.license_no);

  if (!/^\d{10}$/.test(license)) {
    return res.json({
      valid: false,
      error: "license number must be 10 digits",
    });
  }

  let browser;
  let context;

  try {
    browser = await chromium.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox"],
    });

    context = await browser.newContext({
      locale: "ar-SA",
      viewport: { width: 1440, height: 1100 },
      userAgent:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
    });

    const page = await context.newPage();

    await page.goto(
      "https://eservicesredp.rega.gov.sa/auth/queries/Brokerage",
      {
        waitUntil: "domcontentloaded",
        timeout: 90000,
      }
    );

    await page.waitForTimeout(5000);

    const clickedTab = await clickIfExists(
      page,
      [
        'button:has-text("رقم رخصة الوسيط")',
        'text="رقم رخصة الوسيط"',
        '[role="tab"]:has-text("رقم رخصة الوسيط")',
        'xpath=//button[normalize-space()="رقم رخصة الوسيط"]',
      ],
      15000
    );

    if (!clickedTab) {
      throw new Error("لم يتم العثور على تبويب رقم رخصة الوسيط");
    }

    await page.waitForTimeout(1500);

    const licenseInput = await getVisibleLocator(
      page,
      [
        'xpath=//*[contains(normalize-space(.),"رقم رخصة الوسيط")]/following::input[1]',
        'input[name*="license"]',
        'input[id*="license"]',
        'input[placeholder*="رقم رخصة"]',
        'input[placeholder*="الرخصة"]',
        'input[inputmode="numeric"]',
        'input[inputmode="decimal"]',
        'input[type="text"]',
        'input',
      ],
      20000
    );

    if (!licenseInput) {
      throw new Error("لم يتم العثور على حقل رقم رخصة الوسيط");
    }

    await fillInputRobustly(licenseInput, license);
    await page.waitForTimeout(1000);

    const currentValue = await licenseInput.inputValue().catch(() => "");
    if (currentValue !== license) {
      throw new Error(`فشل تثبيت قيمة الرخصة داخل الحقل. current="${currentValue}"`);
    }

    const clickedSearch = await clickIfExists(
      page,
      [
        'button:has-text("استعلم")',
        '[type="submit"]:has-text("استعلم")',
        'text="استعلم"',
        'xpath=//button[contains(normalize-space(),"استعلم")]',
      ],
      15000
    );

    if (!clickedSearch) {
      throw new Error("لم يتم العثور على زر استعلم");
    }

    await page.waitForTimeout(2500);

    // محاولة إضافية: Enter على الحقل
    try {
      await licenseInput.press("Enter");
    } catch (_) {}

    try {
      await Promise.race([
        page.waitForSelector('text="الاطلاع على التفاصيل"', { timeout: 12000 }),
        page.waitForSelector('text="اسم الوسيط"', { timeout: 12000 }),
        page.waitForSelector('text="حالة الرخصة"', { timeout: 12000 }),
        page.waitForURL(/BrokerageDetails/i, { timeout: 12000 }),
      ]);
    } catch (_) {}

    await clickIfExists(
      page,
      [
        'button:has-text("الاطلاع على التفاصيل")',
        'text="الاطلاع على التفاصيل"',
        'a:has-text("الاطلاع على التفاصيل")',
        'xpath=//button[contains(normalize-space(),"الاطلاع على التفاصيل")]',
      ],
      5000
    );

    await page.waitForTimeout(4000);

    const result = await extractResult(page, license);

    // حفظ ملفات تشخيص لو لم تنجح
    if (!result.valid) {
      await page.screenshot({ path: "rega_debug.png", fullPage: true });
      fs.writeFileSync("rega_debug.html", await page.content(), "utf8");
    }

    await context.close();
    await browser.close();

    return res.json(result);
  } catch (e) {
    if (context) {
      try {
        await context.close();
      } catch (_) {}
    }

    if (browser) {
      try {
        await browser.close();
      } catch (_) {}
    }

    return res.json({
      valid: false,
      error: String(e),
    });
  }
});

app.listen(PORT, () => {
  console.log(`SERVER RUNNING http://localhost:${PORT}`);
});