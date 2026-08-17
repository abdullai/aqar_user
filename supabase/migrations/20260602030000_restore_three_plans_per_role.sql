-- =============================================================================
-- 2026-06-02 — استعادة الباقات الثلاث (أساسية / احترافية / مميّزة) لكل دور
-- =============================================================================
-- السياسة الجديدة وفق طلب المستخدم:
--   • المسوّق / المكتب / الوكالة / المؤسسة / الشركة:
--       تظهر «الأساسية» (sort_order=1) + «الاحترافية» (sort_order=2) + «المميّزة»
--       (sort_order=3) في تبويب «باقات الاشتراك».
--   • المالك الفردي / المستخدم العام: الأساسية + 11/12/13 (عروض السوق).
--
-- يضمن هذا الترحيل:
--   1) تفعيل (is_active=true) الباقات 1/2/3 لكل دور تسويقي ولِـ individual.
--   2) إنشاء أي باقة ناقصة بإعدادات افتراضية معقولة (لن تُعدّل الموجودة).
--   3) عدم لمس الباقات التجريبية (is_trial_plan=true) أو 11/12/13.
-- =============================================================================

BEGIN;

-- (1) أعد تفعيل الباقات وفق السياسة الموسّعة الجديدة
UPDATE public.subscription_plans
   SET is_active = true
 WHERE coalesce(is_trial_plan, false) = false
   AND (
     (sort_order IN (1, 2, 3)
        AND user_type IN ('marketer','office','institution','company'))
     OR (sort_order = 1 AND user_type = 'individual')
     OR (sort_order IN (11, 12, 13) AND user_type = 'individual')
   );

-- (2) أنشئ أي باقة ناقصة (sort_order 1/2/3) بأسعار 99/149/499 الحالية
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT * FROM (VALUES
  -- مسوّق فردي
  (N'الأساسية',  'Basic',         'marketer',
     99::numeric,  round((99*12*0.80)::numeric,2),
     0::int, NULL::int,  60::int, NULL::int, 49::int,
     true,  false, false, false, 50::numeric, 1, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'marketer',
     149::numeric, round((149*12*0.80)::numeric,2),
     0::int, NULL::int, 450::int, NULL::int, NULL::int,
     true,  true,  false, true,  50::numeric, 2, true, false, 'monthly'),
  (N'المميّزة',  'Premium',       'marketer',
     499::numeric, round((499*12*0.80)::numeric,2),
     0::int, NULL::int, NULL::int, NULL::int, NULL::int,
     true,  true,  true,  true,  50::numeric, 3, true, false, 'monthly'),

  -- مكتب عقاري
  (N'الأساسية',  'Basic',         'office',
     99::numeric,  round((99*12*0.80)::numeric,2),
     3::int, NULL::int,  60::int, NULL::int, 49::int,
     true,  false, false, false, 50::numeric, 1, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'office',
     149::numeric, round((149*12*0.80)::numeric,2),
     6::int, NULL::int, 600::int, NULL::int, NULL::int,
     true,  true,  false, true,  50::numeric, 2, true, false, 'monthly'),
  (N'المميّزة',  'Premium',       'office',
     499::numeric, round((499*12*0.80)::numeric,2),
     6::int, NULL::int, NULL::int, NULL::int, NULL::int,
     true,  true,  true,  true,  50::numeric, 3, true, false, 'monthly'),

  -- مؤسسة عقارية
  (N'الأساسية',  'Basic',         'institution',
     99::numeric,  round((99*12*0.80)::numeric,2),
     6::int, NULL::int,  60::int, NULL::int, 49::int,
     true,  false, false, false, 50::numeric, 1, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'institution',
     149::numeric, round((149*12*0.80)::numeric,2),
     9::int, NULL::int, 900::int, NULL::int, NULL::int,
     true,  true,  false, true,  50::numeric, 2, true, false, 'monthly'),
  (N'المميّزة',  'Premium',       'institution',
     499::numeric, round((499*12*0.80)::numeric,2),
     9::int, NULL::int, NULL::int, NULL::int, NULL::int,
     true,  true,  true,  true,  50::numeric, 3, true, false, 'monthly'),

  -- شركة عقارية
  (N'الأساسية',  'Basic',         'company',
     99::numeric,  round((99*12*0.80)::numeric,2),
     9::int, NULL::int,  60::int, NULL::int, 49::int,
     true,  false, false, false, 50::numeric, 1, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'company',
     149::numeric, round((149*12*0.80)::numeric,2),
     12::int, NULL::int, 1200::int, NULL::int, NULL::int,
     true,  true,  false, true,  50::numeric, 2, true, false, 'monthly'),
  (N'المميّزة',  'Premium',       'company',
     499::numeric, round((499*12*0.80)::numeric,2),
     12::int, NULL::int, NULL::int, NULL::int, NULL::int,
     true,  true,  true,  true,  50::numeric, 3, true, false, 'monthly')
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent,
  sort_order, is_active, is_trial_plan, plan_program
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type  = v.user_type
     AND sp.sort_order = v.sort_order
     AND coalesce(sp.is_trial_plan, false) = false
);

-- (3) تشخيص نهائي
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT user_type, sort_order, count(*) AS n,
           bool_or(is_active) AS any_active
      FROM public.subscription_plans
     WHERE coalesce(is_trial_plan, false) = false
       AND user_type IN ('marketer','office','institution','company','individual')
       AND (sort_order IN (1,2,3) OR (user_type = 'individual' AND sort_order IN (11,12,13)))
     GROUP BY user_type, sort_order
     ORDER BY user_type, sort_order
  LOOP
    RAISE NOTICE 'plan %/%/%  active=%', r.user_type, r.sort_order, r.n, r.any_active;
  END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- تحقق سريع:
--   SELECT user_type, sort_order, name_ar, price_monthly, is_active
--     FROM public.subscription_plans
--    WHERE coalesce(is_trial_plan, false) = false
--    ORDER BY user_type, sort_order;
-- =============================================================================
