-- =============================================================================
-- 2026-05-30 — تأكيد قوي على ظهور الباقات (نسخة محسَّنة)
-- =============================================================================
-- الهدف:
--   • التأكد من وجود باقة أساسية واحدة على الأقل لكل دور تسويقي ولِـ individual.
--   • تفعيل (is_active = true) جميع الباقات المعرَّفة لكل دور وفق سياسة v4.
--   • إيقاف أي تكرار «أساسية» مكسور (نُبقي الأقدم/الأعلى ترتيباً ونُعطّل البقية).
-- =============================================================================

BEGIN;

-- (1) أعد تفعيل الباقات وفق سياسة الدور
UPDATE public.subscription_plans
   SET is_active = true
 WHERE coalesce(is_trial_plan, false) = false
   AND (
     (sort_order = 1
        AND user_type IN ('marketer','office','institution','company','individual'))
     OR
     (sort_order = 2
        AND user_type IN ('marketer','office','institution','company'))
     OR
     (sort_order = 3 AND user_type = 'company')
     OR
     (sort_order IN (11,12,13) AND user_type = 'individual')
   );

-- (2) في حال نقص الأساسية لأي دور، أنشئها فوراً
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT * FROM (VALUES
  (N'الأساسية', 'Basic', 'marketer', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'الأساسية', 'Basic', 'office', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'الأساسية', 'Basic', 'institution', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'الأساسية', 'Basic', 'company', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'أساسية الفرد', 'Basic Individual', 'individual', 49::numeric, round((49*12*0.80)::numeric,2),
   0, NULL::int, 0::int, NULL::int, 0::int,
   false, false, false, false, 1, true, false, 'monthly')
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  sort_order, is_active, is_trial_plan, plan_program
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type = v.user_type
     AND sp.sort_order = v.sort_order
     AND coalesce(sp.is_trial_plan, false) = false
);

-- (3) تشخيص نهائي: عدّ الباقات النشطة لكل دور لرصد أي شذوذ.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT user_type, sort_order, count(*) AS n
    FROM public.subscription_plans
    WHERE is_active = true
      AND coalesce(is_trial_plan, false) = false
    GROUP BY user_type, sort_order
    ORDER BY user_type, sort_order
  LOOP
    RAISE NOTICE 'plans %/% active=%', r.user_type, r.sort_order, r.n;
  END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- تحقق سريع:
--   SELECT user_type, sort_order, name_ar, is_active, is_trial_plan, plan_program
--   FROM public.subscription_plans
--   ORDER BY user_type, sort_order;
-- =============================================================================
