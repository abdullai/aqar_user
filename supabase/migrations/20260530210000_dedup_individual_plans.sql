-- =============================================================================
-- تنظيف باقات «individual» المكرّرة + إلغاء تنشيط النسخ القديمة
-- =============================================================================
-- في قاعدة البيانات الحالية يوجد:
--   * 3 نسخ من "أساسي" (49 ر, 15 طلب, sort=1)
--   * 1 نسخة من "الباقة الأساسية" (59 ر, 20 طلب, sort=1) — قديمة من ترحيل 2026-05-03
--   * 2 نسخة من "احترافي" (119 ر, 100 طلب, sort=2)
--   * 1 نسخة من "الباقة الاحترافية" (149 ر, 200 طلب, sort=2) — قديمة
--   * 2 نسخة من "مميز" (349 ر, sort=3)
--   * 1 نسخة من "الباقة المؤسسية" (499 ر, sort=3) — قديمة
--   * 3 نسخ جديدة من "عروض السوق …" (sort 11/12/13)
--
-- المطلوب: الإبقاء على نسخة واحدة فقط من كل باقة فريدة.
-- =============================================================================

BEGIN;

-- (أ) إلغاء تنشيط الباقات القديمة من ترحيل 2026-05-03 (المسماة "الباقة …")
UPDATE public.subscription_plans
SET is_active = false
WHERE user_type = 'individual'
  AND is_active = true
  AND name_ar IN (N'الباقة الأساسية', N'الباقة الاحترافية', N'الباقة المؤسسية');

-- (ب) إبقاء أحدث نسخة فقط من كل (name_ar, sort_order) — إلغاء تنشيط الباقي
WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY name_ar, sort_order
      ORDER BY created_at DESC, id DESC
    ) AS rn
  FROM public.subscription_plans
  WHERE user_type = 'individual'
    AND is_active = true
)
UPDATE public.subscription_plans p
SET is_active = false
FROM ranked r
WHERE p.id = r.id
  AND r.rn > 1;

COMMIT;

-- تحقق:
-- SELECT name_ar, plan_program, price_monthly, price_yearly,
--        max_listing_requests, sort_order, is_active
-- FROM public.subscription_plans
-- WHERE user_type = 'individual' AND is_active = true
-- ORDER BY sort_order;
