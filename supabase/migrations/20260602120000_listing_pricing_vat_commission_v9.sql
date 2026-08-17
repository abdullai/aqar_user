-- =============================================================================
-- 2026-06-02 — Listing pricing transparency: VAT (5%) & marketing commission (v9)
-- =============================================================================
-- يضيف هذا الترحيل أعمدة الفوترة الواضحة للعقار/الطلب وفق متطلبات الهيئة العامة
-- للزكاة والضريبة والجمارك (ZATCA) والهيئة العامة للعقار (REGA):
--
--   (1) price_includes_vat       (bool, default true):
--       هل السعر الذي أدخله المعلن «شامل» ضريبة القيمة المضافة 5%؟
--         - true  → السعر الأساسي = price / (1 + vat_rate)؛ الضريبة محتسبة داخل المبلغ.
--         - false → السعر الأساسي = price؛ الضريبة تُضاف على الإجمالي.
--
--   (2) vat_rate                 (numeric(5,4), default 0.05):
--       نسبة الضريبة المعتمدة. 5% هي السقف الحالي بالمملكة (قابل للتعديل مستقبلاً).
--
--   (3) marketing_commission_kind (text default 'none' check in ('none','percent','fixed')):
--       طريقة احتساب عمولة التسويق:
--         - 'none'    → لا توجد عمولة على الفاتورة.
--         - 'percent' → نسبة مئوية من السعر الأساسي (التسويق العقاري 2.5% افتراضياً).
--         - 'fixed'   → مبلغ مقطوع يحدّده المعلن.
--
--   (4) marketing_commission_rate   (numeric(5,4), default 0.025): نسبة العمولة عند 'percent'.
--   (5) marketing_commission_amount (numeric(14,2), default 0):    المبلغ المقطوع عند 'fixed'.
--
--   (6) default_cover_used (bool, default false):
--       يُسجَّل true عندما يُستبدل غياب الصور بصورة المشروع/الشعار افتراضياً، لتوضيحه
--       في تقارير المحتوى وللمسوّق عند الانضمام.
--
-- المنطق المستهدف على الفاتورة:
--   base   = price_includes_vat ? price / (1 + vat_rate) : price
--   vat    = base * vat_rate
--   total_with_vat = base + vat   (= price إن كان شامل)
--   commission     = kind='percent' ? base * marketing_commission_rate
--                  : kind='fixed'   ? marketing_commission_amount : 0
--   final_total    = total_with_vat + commission
--
-- الإعلانات القديمة (قبل هذا الترحيل) تُعتبر «شاملة الضريبة» و«بدون عمولة»
-- وفق القرار المحافظ المتفق عليه — حتى لا يتغير المبلغ المعروض للعملاء.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (A) الجدول الرئيسي: properties
-- ---------------------------------------------------------------------------
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS price_includes_vat boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS vat_rate numeric(5,4) NOT NULL DEFAULT 0.0500,
  ADD COLUMN IF NOT EXISTS marketing_commission_kind text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS marketing_commission_rate numeric(5,4) NOT NULL DEFAULT 0.0250,
  ADD COLUMN IF NOT EXISTS marketing_commission_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_cover_used boolean NOT NULL DEFAULT false;

DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'properties_marketing_commission_kind_chk'
  ) THEN
    ALTER TABLE public.properties
      ADD CONSTRAINT properties_marketing_commission_kind_chk
      CHECK (marketing_commission_kind IN ('none', 'percent', 'fixed'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'properties_vat_rate_range_chk'
  ) THEN
    ALTER TABLE public.properties
      ADD CONSTRAINT properties_vat_rate_range_chk
      CHECK (vat_rate >= 0 AND vat_rate <= 0.5000);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'properties_commission_rate_range_chk'
  ) THEN
    ALTER TABLE public.properties
      ADD CONSTRAINT properties_commission_rate_range_chk
      CHECK (marketing_commission_rate >= 0 AND marketing_commission_rate <= 0.2500);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'properties_commission_amount_nonneg_chk'
  ) THEN
    ALTER TABLE public.properties
      ADD CONSTRAINT properties_commission_amount_nonneg_chk
      CHECK (marketing_commission_amount >= 0);
  END IF;
END
$check$;

COMMENT ON COLUMN public.properties.price_includes_vat IS
  'true: price already includes 5% VAT (base = price/1.05). false: VAT added on top.';
COMMENT ON COLUMN public.properties.vat_rate IS
  'Saudi VAT rate (currently 0.05). Stored per-row for historical correctness if rate changes.';
COMMENT ON COLUMN public.properties.marketing_commission_kind IS
  'none | percent | fixed — how marketing commission is computed on the invoice.';
COMMENT ON COLUMN public.properties.marketing_commission_rate IS
  'Marketing commission rate when kind=percent (default 0.025 = 2.5%).';
COMMENT ON COLUMN public.properties.marketing_commission_amount IS
  'Fixed marketing commission amount in listing currency when kind=fixed.';
COMMENT ON COLUMN public.properties.default_cover_used IS
  'true if the system substituted a default cover image (app logo) because owner did not upload media.';

-- ---------------------------------------------------------------------------
-- (B) الطلبات الفردية (قبل التحقق من فال): listing_requests
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS price_includes_vat boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS vat_rate numeric(5,4) NOT NULL DEFAULT 0.0500,
  ADD COLUMN IF NOT EXISTS marketing_commission_kind text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS marketing_commission_rate numeric(5,4) NOT NULL DEFAULT 0.0250,
  ADD COLUMN IF NOT EXISTS marketing_commission_amount numeric(14,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS default_cover_used boolean NOT NULL DEFAULT false;

DO $check2$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listing_requests_marketing_commission_kind_chk'
  ) THEN
    ALTER TABLE public.listing_requests
      ADD CONSTRAINT listing_requests_marketing_commission_kind_chk
      CHECK (marketing_commission_kind IN ('none', 'percent', 'fixed'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listing_requests_vat_rate_range_chk'
  ) THEN
    ALTER TABLE public.listing_requests
      ADD CONSTRAINT listing_requests_vat_rate_range_chk
      CHECK (vat_rate >= 0 AND vat_rate <= 0.5000);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listing_requests_commission_rate_range_chk'
  ) THEN
    ALTER TABLE public.listing_requests
      ADD CONSTRAINT listing_requests_commission_rate_range_chk
      CHECK (marketing_commission_rate >= 0 AND marketing_commission_rate <= 0.2500);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listing_requests_commission_amount_nonneg_chk'
  ) THEN
    ALTER TABLE public.listing_requests
      ADD CONSTRAINT listing_requests_commission_amount_nonneg_chk
      CHECK (marketing_commission_amount >= 0);
  END IF;
END
$check2$;

-- ---------------------------------------------------------------------------
-- (C) طلبات السوق (يبحث عن عقار): market_property_requests
--   نضيف فقط default_cover_used (الميزانية مختلفة عن سعر بيع/إيجار).
-- ---------------------------------------------------------------------------
ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS default_cover_used boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.listing_requests.price_includes_vat IS
  'Mirrors properties.price_includes_vat — set on owner-individual request before marketer publishes.';

-- ---------------------------------------------------------------------------
-- (D) دالة مساعدة لإرجاع تفصيل الفاتورة (للاستعلامات/التصدير)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_listing_invoice_breakdown(
  p_price numeric,
  p_includes_vat boolean,
  p_vat_rate numeric,
  p_commission_kind text,
  p_commission_rate numeric,
  p_commission_amount numeric
)
RETURNS TABLE (
  base_price numeric,
  vat_amount numeric,
  total_with_vat numeric,
  commission_amount numeric,
  final_total numeric
)
LANGUAGE sql
IMMUTABLE
AS $$
  WITH calc AS (
    SELECT
      CASE
        WHEN COALESCE(p_includes_vat, true) THEN
          ROUND(p_price / (1 + COALESCE(p_vat_rate, 0.05))::numeric, 2)
        ELSE
          ROUND(p_price, 2)
      END AS base
  ),
  vat AS (
    SELECT base, ROUND(base * COALESCE(p_vat_rate, 0.05)::numeric, 2) AS vat
    FROM calc
  ),
  comm AS (
    SELECT
      base,
      vat,
      CASE
        WHEN COALESCE(p_commission_kind, 'none') = 'percent'
          THEN ROUND(base * COALESCE(p_commission_rate, 0.025)::numeric, 2)
        WHEN COALESCE(p_commission_kind, 'none') = 'fixed'
          THEN ROUND(COALESCE(p_commission_amount, 0)::numeric, 2)
        ELSE 0::numeric
      END AS commission
    FROM vat
  )
  SELECT
    base,
    vat,
    base + vat AS total_with_vat,
    commission,
    base + vat + commission AS final_total
  FROM comm;
$$;

COMMENT ON FUNCTION public.fn_listing_invoice_breakdown(
  numeric, boolean, numeric, text, numeric, numeric
) IS
  'Returns the pricing breakdown matching the in-app invoice (base, VAT, total_with_vat, commission, final_total).';

GRANT EXECUTE ON FUNCTION public.fn_listing_invoice_breakdown(
  numeric, boolean, numeric, text, numeric, numeric
) TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (E) View للفوترة المبسّطة (سهلة الاستعلام من تقارير ZATCA/REGA)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_property_invoice_breakdown AS
SELECT
  p.id                         AS property_id,
  p.listing_public_code        AS listing_public_code,
  p.owner_id                   AS owner_id,
  p.currency                   AS currency,
  p.price                      AS entered_price,
  p.price_includes_vat         AS price_includes_vat,
  p.vat_rate                   AS vat_rate,
  p.marketing_commission_kind  AS commission_kind,
  p.marketing_commission_rate  AS commission_rate,
  p.marketing_commission_amount AS commission_amount,
  brk.base_price,
  brk.vat_amount,
  brk.total_with_vat,
  brk.commission_amount        AS commission_total,
  brk.final_total
FROM public.properties p
CROSS JOIN LATERAL public.fn_listing_invoice_breakdown(
  p.price,
  p.price_includes_vat,
  p.vat_rate,
  p.marketing_commission_kind,
  p.marketing_commission_rate,
  p.marketing_commission_amount
) brk;

COMMENT ON VIEW public.v_property_invoice_breakdown IS
  'Per-listing invoice breakdown view for ZATCA/REGA-aligned reporting.';

-- منح الصلاحيات على الـ view: SELECT للمستخدمين المسجّلين (سياسات RLS على properties تبقى نشطة)
GRANT SELECT ON public.v_property_invoice_breakdown TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (F) Backfill: الإعلانات الموجودة تُعامل بالقرار المحافظ (شامل ضريبة، بدون عمولة)
--    — لا حاجة لتشغيل UPDATE لأن DEFAULTs السابقة عيّنت القيم. تبقى هنا للتوثيق.
-- ---------------------------------------------------------------------------
-- UPDATE public.properties SET price_includes_vat = true, marketing_commission_kind = 'none' WHERE price_includes_vat IS NULL;

COMMIT;
