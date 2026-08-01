-- =============================================================================
-- 2026-06-02 — السياسة الكاملة للاشتراكات (v5):
--   • باقة واحدة فقط نشطة لكل دور.
--   • تنظيف صارم لكل التكرار من الترحيلات السابقة (دون حذف لحفظ FK).
--   • أعمدة جديدة: خصم الدفع التلقائي 20%، خصم الاحتفاظ عند الإلغاء 20%،
--     علم تلقي العضو خصم 50% للمقعد، حد المقاعد للأدوار.
-- =============================================================================
-- خريطة الأدوار → الباقة الوحيدة المرئية:
--   • marketer       → الأساسية (sort=1)            99 ر.س | 950.40 سنوي | 3 مقاعد
--   • office         → الاحترافية (sort=2)         149 ر.س | 1430.40 سنوي | 6 مقاعد
--   • institution    → الاحترافية (sort=2)         149 ر.س | 1430.40 سنوي | 9 مقاعد
--   • company        → المميّزة (sort=3)           499 ر.س | 4790.40 سنوي | 12 مقعد
--   • individual     → الأساسية فردية (sort=1)      49 ر.س |  470.40 سنوي | 0 مقاعد
--   • individual     → عروض السوق (11/12/13) كما هي
-- =============================================================================

BEGIN;

-- (A) أعمدة جديدة على subscription_plans
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS auto_pay_discount_percent numeric(5,2) NOT NULL DEFAULT 20.0,
  ADD COLUMN IF NOT EXISTS cancellation_retention_offer_pct numeric(5,2) NOT NULL DEFAULT 20.0;

COMMENT ON COLUMN public.subscription_plans.auto_pay_discount_percent IS
  'خصم تلقائي يُطبَّق على الفاتورة عند تفعيل الدفع التلقائي (auto_renew=true).';
COMMENT ON COLUMN public.subscription_plans.cancellation_retention_offer_pct IS
  'نسبة خصم الاحتفاظ المعروض لمالك الاشتراك مرّة واحدة عند ضغط «إلغاء».';

-- (B) أعمدة جديدة على user_subscriptions
ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS auto_pay_discount_applied boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS retention_offer_used_at timestamptz,
  ADD COLUMN IF NOT EXISTS retention_offer_pct_applied numeric(5,2);

-- (C) جدول مساعد لتسجيل عرض «الاحتفاظ عند الإلغاء» مرّة واحدة لكل (user_id):
CREATE TABLE IF NOT EXISTS public.user_retention_offers_consumed (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  consumed_at timestamptz NOT NULL DEFAULT now(),
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  pct_applied numeric(5,2) NOT NULL DEFAULT 20.0
);

ALTER TABLE public.user_retention_offers_consumed ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS retention_offer_select_own ON public.user_retention_offers_consumed;
CREATE POLICY retention_offer_select_own ON public.user_retention_offers_consumed
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- =============================================================================
-- (D) تعطيل الكاتلوج بأكمله (غير التجريبية)، ثم تفعيل واحدة كانونية فقط لكل دور.
-- =============================================================================
UPDATE public.subscription_plans
   SET is_active = false
 WHERE coalesce(is_trial_plan, false) = false
   AND is_active = true;

-- (D.1) اختر صفاً كانونياً واحداً لكل (user_type, sort_order) المطلوب،
--       مع تفضيل سعرنا الكانوني، ثم الأحدث.
WITH targets AS (
  SELECT * FROM (VALUES
    ('marketer',    1, 99::numeric,  950.40::numeric),
    ('office',      2, 149::numeric, 1430.40::numeric),
    ('institution', 2, 149::numeric, 1430.40::numeric),
    ('company',     3, 499::numeric, 4790.40::numeric),
    ('individual',  1, 49::numeric,  470.40::numeric)
  ) AS t(user_type, sort_order, price_m, price_y)
),
ranked AS (
  SELECT sp.id,
         sp.user_type,
         sp.sort_order,
         sp.price_monthly,
         t.price_m AS target_m,
         row_number() OVER (
           PARTITION BY sp.user_type, sp.sort_order
           ORDER BY
             CASE WHEN sp.price_monthly = t.price_m THEN 0 ELSE 1 END,
             CASE WHEN sp.name_ar IN (N'الأساسي', N'الاحترافي', N'المميّزة', N'المميزة', N'أساسي') THEN 0 ELSE 1 END,
             sp.created_at DESC NULLS LAST,
             sp.id DESC
         ) AS rn
    FROM public.subscription_plans sp
    JOIN targets t
      ON t.user_type = sp.user_type
     AND t.sort_order = sp.sort_order
   WHERE coalesce(sp.is_trial_plan, false) = false
)
UPDATE public.subscription_plans sp
   SET is_active = true
  FROM ranked r
 WHERE sp.id = r.id
   AND r.rn = 1;

-- (D.2) أعد تفعيل باقات «عروض السوق» (11/12/13) للمالك الفردي — الأحدث فقط لكل sort.
WITH ranked11 AS (
  SELECT id, sort_order,
         row_number() OVER (
           PARTITION BY sort_order
           ORDER BY created_at DESC NULLS LAST, id DESC
         ) AS rn
    FROM public.subscription_plans
   WHERE coalesce(is_trial_plan, false) = false
     AND user_type = 'individual'
     AND sort_order IN (11, 12, 13)
)
UPDATE public.subscription_plans sp
   SET is_active = true
  FROM ranked11 r
 WHERE sp.id = r.id
   AND r.rn = 1;

-- =============================================================================
-- (E) تثبيت الأسعار/الحدود الكانونية على الصفوف النشطة (لكل دور)
-- =============================================================================

-- مسوّق فردي → الأساسية فقط
UPDATE public.subscription_plans
   SET name_ar = N'الأساسية',
       name_en = 'Basic',
       price_monthly = 99,
       price_yearly  = 950.40,
       max_members = 3,
       max_properties = NULL,
       max_ads_per_month = 60,
       max_listing_requests = NULL,
       max_market_offers = 49,
       has_fal_license = true,
       has_analytics = false,
       has_api_access = false,
       has_priority_support = false,
       team_member_discount_percent = 50,
       seat_unit_price_sar = round(99 * 0.5, 2),
       auto_pay_discount_percent = 20.0,
       cancellation_retention_offer_pct = 20.0
 WHERE is_active = true
   AND coalesce(is_trial_plan, false) = false
   AND user_type = 'marketer'
   AND sort_order = 1;

-- مكتب → الاحترافية فقط
UPDATE public.subscription_plans
   SET name_ar = N'الاحترافية',
       name_en = 'Professional',
       price_monthly = 149,
       price_yearly  = 1430.40,
       max_members = 6,
       max_properties = NULL,
       max_ads_per_month = 600,
       max_listing_requests = NULL,
       max_market_offers = 49,
       has_fal_license = true,
       has_analytics = true,
       has_api_access = false,
       has_priority_support = true,
       team_member_discount_percent = 50,
       seat_unit_price_sar = round(149 * 0.5, 2),
       auto_pay_discount_percent = 20.0,
       cancellation_retention_offer_pct = 20.0
 WHERE is_active = true
   AND coalesce(is_trial_plan, false) = false
   AND user_type = 'office'
   AND sort_order = 2;

-- مؤسسة → الاحترافية فقط (9 مقاعد)
UPDATE public.subscription_plans
   SET name_ar = N'الاحترافية',
       name_en = 'Professional',
       price_monthly = 149,
       price_yearly  = 1430.40,
       max_members = 9,
       max_properties = NULL,
       max_ads_per_month = 900,
       max_listing_requests = NULL,
       max_market_offers = 49,
       has_fal_license = true,
       has_analytics = true,
       has_api_access = false,
       has_priority_support = true,
       team_member_discount_percent = 50,
       seat_unit_price_sar = round(149 * 0.5, 2),
       auto_pay_discount_percent = 20.0,
       cancellation_retention_offer_pct = 20.0
 WHERE is_active = true
   AND coalesce(is_trial_plan, false) = false
   AND user_type = 'institution'
   AND sort_order = 2;

-- شركة → المميّزة فقط (12 مقعد)
UPDATE public.subscription_plans
   SET name_ar = N'المميّزة',
       name_en = 'Premium',
       price_monthly = 499,
       price_yearly  = 4790.40,
       max_members = 12,
       max_properties = NULL,
       max_ads_per_month = NULL,
       max_listing_requests = NULL,
       max_market_offers = NULL,
       has_fal_license = true,
       has_analytics = true,
       has_api_access = true,
       has_priority_support = true,
       team_member_discount_percent = 50,
       seat_unit_price_sar = round(499 * 0.5, 2),
       auto_pay_discount_percent = 20.0,
       cancellation_retention_offer_pct = 20.0
 WHERE is_active = true
   AND coalesce(is_trial_plan, false) = false
   AND user_type = 'company'
   AND sort_order = 3;

-- مالك فردي → أساسية بسيطة 49 (ثابتة)
UPDATE public.subscription_plans
   SET name_ar = N'أساسي',
       name_en = 'Basic',
       price_monthly = 49,
       price_yearly  = 470.40,
       max_members = 0,
       max_properties = NULL,
       max_ads_per_month = 40,
       max_listing_requests = 15,
       has_fal_license = false,
       has_analytics = false,
       has_api_access = false,
       has_priority_support = false,
       team_member_discount_percent = 0,
       seat_unit_price_sar = 0,
       auto_pay_discount_percent = 20.0,
       cancellation_retention_offer_pct = 20.0
 WHERE is_active = true
   AND coalesce(is_trial_plan, false) = false
   AND user_type = 'individual'
   AND sort_order = 1;

-- =============================================================================
-- (F) إنشاء أي صف ناقص بالكانون
-- =============================================================================
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT * FROM (VALUES
  (N'الأساسية',  'Basic',         'marketer',
     99::numeric,  950.40::numeric,
     3::int, NULL::int, 60::int, NULL::int, 49::int,
     true, false, false, false,
     50::numeric, 49.50::numeric,
     20.0::numeric, 20.0::numeric,
     1, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'office',
     149::numeric, 1430.40::numeric,
     6::int, NULL::int, 600::int, NULL::int, 49::int,
     true, true, false, true,
     50::numeric, 74.50::numeric,
     20.0::numeric, 20.0::numeric,
     2, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'institution',
     149::numeric, 1430.40::numeric,
     9::int, NULL::int, 900::int, NULL::int, 49::int,
     true, true, false, true,
     50::numeric, 74.50::numeric,
     20.0::numeric, 20.0::numeric,
     2, true, false, 'monthly'),
  (N'المميّزة',  'Premium',       'company',
     499::numeric, 4790.40::numeric,
     12::int, NULL::int, NULL::int, NULL::int, NULL::int,
     true, true, true, true,
     50::numeric, 249.50::numeric,
     20.0::numeric, 20.0::numeric,
     3, true, false, 'monthly'),
  (N'أساسي',     'Basic',         'individual',
     49::numeric,  470.40::numeric,
     0::int, NULL::int, 40::int, 15::int, 0::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 20.0::numeric,
     1, true, false, 'monthly')
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type  = v.user_type
     AND sp.sort_order = v.sort_order
     AND sp.is_active  = true
     AND coalesce(sp.is_trial_plan, false) = false
);

-- =============================================================================
-- (G) تشخيص نهائي
-- =============================================================================
DO $$
DECLARE r record;
BEGIN
  RAISE NOTICE '== الباقات النشطة بعد التنظيف v5 ==';
  FOR r IN
    SELECT user_type, sort_order, name_ar, price_monthly, price_yearly,
           max_members, is_active
      FROM public.subscription_plans
     WHERE coalesce(is_trial_plan, false) = false
     ORDER BY user_type, sort_order, is_active DESC, created_at DESC
  LOOP
    RAISE NOTICE '  %/% % | % monthly=%, yearly=%, seats=%',
      r.user_type, r.sort_order,
      CASE WHEN r.is_active THEN '[نشط]' ELSE '[معطّل]' END,
      r.name_ar, r.price_monthly, r.price_yearly, r.max_members;
  END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- تحقق:
--   SELECT user_type, sort_order, name_ar, price_monthly, price_yearly,
--          max_members, is_active
--     FROM public.subscription_plans
--    WHERE coalesce(is_trial_plan,false) = false
--      AND is_active = true
--    ORDER BY user_type, sort_order;
--
-- يجب أن تعود 7 صفوف فقط:
--   marketer/1, office/2, institution/2, company/3,
--   individual/1, individual/11, individual/12, individual/13.
-- =============================================================================
