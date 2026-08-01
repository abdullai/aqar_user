-- =============================================================================
-- v4 — سياسة الباقات الموحَّدة (طلب المستخدم 2026-05-30)
-- =============================================================================
-- المتطلبات (ملخّص شفّاف):
--
-- (أ) الباقات للأدوار التسويقية (marketer / office / institution / company):
--      الأساسية (sort_order = 1)     — 99 ر/شهر
--          • أعضاء فريق: حتى 3
--          • كل عضو إضافي خصم 50%
--          • طلبات عقارية أنشرها: غير محدود
--          • إعلانات عقارية: 60 / شهر
--          • تقديم عرض من الرئيسية على طلبات الآخرين: 49 / شهر
--          • رخصة فال سارية المفعول: مطلوبة
--
--      الاحترافية (sort_order = 2)   — 149 ر/شهر
--          • أعضاء فريق:
--                مكتب  = 6   ·   مؤسسة = 9   ·   شركة = 9   ·   مسوّق فردي = 3
--          • كل عضو إضافي خصم 50%
--          • طلبات عقارية: غير محدود
--          • إعلانات عقارية: 120 / شهر
--          • تقديم عرض من الرئيسية: 99 / شهر
--          • رخصة فال: مطلوبة
--
--      المميزة (sort_order = 3)      — للشركات فقط  (499 ر/شهر)
--          • أعضاء فريق: 12
--          • كل عضو إضافي خصم 50%
--          • طلبات عقارية: غير محدود
--          • إعلانات عقارية: 180 / شهر
--          • تقديم عرض من الرئيسية: 149 / شهر
--          • رخصة فال: مطلوبة
--          → نُعطّل المميزة لـ marketer/office/institution (تظهر فقط للشركات).
--
--      الباقات السنوية = شهري × 12 × 0.80  (خصم 20%) — بدون تغيير في الحدود.
--
-- (ب) الباقات للمعلن الفرد / المستخدم العادي (individual):
--      أساسية الفرد (sort_order = 1) — 49 ر/شهر
--          • نشر إعلاناته الخاصة وطلباته الخاصة (يبقى كما هو)
--          • تقديم عرض من الرئيسية: 0  ← يلزم باقة إضافية للعروض
--
--      عروض السوق — شهري (sort_order = 11) — 49 ر/شهر
--          • تقديم عرض من الرئيسية: 40 / شهر
--
--      عروض السوق — سنوي (sort_order = 12) — 49 × 12 × 0.80 = 470.40 ر/سنة
--          • تقديم عرض من الرئيسية: 40 / شهر مع تجديد شهري لمدة سنة
--
--      عروض السوق — مرة واحدة (sort_order = 13) — 40 ر (دفع واحد)
--          • تقديم عرض من الرئيسية: 3 إجمالاً (لا يُجدَّد)
--
-- (ج) التفعيل يُحسب من أول اشتراك. للباقات الشهرية = 30 يوم · السنوية = 365 يوم
--      · «مرة واحدة» لا تنتهي بالوقت بل بنفاد الرصيد.
--
-- (د) الفترة التجريبية الحالية (3 أيام لمرة واحدة) تبقى كما هي بلا تغيير.
--
-- (هـ) عمود جديد: max_market_offers  (مستقل عن max_listing_requests).
--      هذا يحلّ التضارب الدلالي السابق:
--          • max_listing_requests  = حد إضافة طلب عقاري بنشره من قِبل المستخدم.
--          • max_market_offers     = حد تقديم عرض من الرئيسية على طلبات الآخرين.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (1) عمود جديد: max_market_offers
-- ---------------------------------------------------------------------------
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS max_market_offers int;

COMMENT ON COLUMN public.subscription_plans.max_market_offers IS
  'حد تقديم العروض من تبويب الرئيسية على طلبات السوق التابعة لمستخدمين آخرين. '
  'NULL = غير محدود · 0 = غير مسموح بدون باقة عروض إضافية. '
  'منفصل عن max_listing_requests الذي يخصّ الطلبات التي ينشرها المستخدم نفسه.';

-- ---------------------------------------------------------------------------
-- (2) الأدوار التسويقية — الباقة الأساسية (sort_order = 1)
--     99 ر/شهر · 3 مقاعد · 60 إعلان · طلبات غير محدودة · 49 عرض من الرئيسية
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans SET
  max_members                   = 3,
  max_ads_per_month             = 60,
  max_listing_requests          = NULL,
  max_market_offers             = 49,
  max_properties                = NULL,
  team_member_discount_percent  = 50,
  seat_unit_price_sar           = round(price_monthly * 0.5, 2),
  has_fal_license               = true
WHERE is_active = true
  AND coalesce(is_trial_plan, false) = false
  AND sort_order = 1
  AND user_type IN ('marketer','office','institution','company');

-- ---------------------------------------------------------------------------
-- (3) الأدوار التسويقية — الباقة الاحترافية (sort_order = 2)
--     149 ر/شهر · 120 إعلان · طلبات غير محدودة · 99 عرض من الرئيسية
--     عدد الأعضاء حسب نوع الحساب (3 / 6 / 9 / 9)
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans SET
  max_ads_per_month             = 120,
  max_listing_requests          = NULL,
  max_market_offers             = 99,
  max_properties                = NULL,
  team_member_discount_percent  = 50,
  seat_unit_price_sar           = round(price_monthly * 0.5, 2),
  has_fal_license               = true,
  max_members                   = 3
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'marketer';

UPDATE public.subscription_plans SET
  max_ads_per_month             = 120,
  max_listing_requests          = NULL,
  max_market_offers             = 99,
  max_properties                = NULL,
  team_member_discount_percent  = 50,
  seat_unit_price_sar           = round(price_monthly * 0.5, 2),
  has_fal_license               = true,
  max_members                   = 6
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'office';

UPDATE public.subscription_plans SET
  max_ads_per_month             = 120,
  max_listing_requests          = NULL,
  max_market_offers             = 99,
  max_properties                = NULL,
  team_member_discount_percent  = 50,
  seat_unit_price_sar           = round(price_monthly * 0.5, 2),
  has_fal_license               = true,
  max_members                   = 9
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'institution';

UPDATE public.subscription_plans SET
  max_ads_per_month             = 120,
  max_listing_requests          = NULL,
  max_market_offers             = 99,
  max_properties                = NULL,
  team_member_discount_percent  = 50,
  seat_unit_price_sar           = round(price_monthly * 0.5, 2),
  has_fal_license               = true,
  max_members                   = 9
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'company';

-- ---------------------------------------------------------------------------
-- (4) المميزة (sort_order = 3) — للشركات فقط
--     499 ر/شهر · 12 مقعد · 180 إعلان · طلبات غير محدودة · 149 عرض من الرئيسية
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans SET
  max_ads_per_month             = 180,
  max_listing_requests          = NULL,
  max_market_offers             = 149,
  max_properties                = NULL,
  team_member_discount_percent  = 50,
  seat_unit_price_sar           = round(price_monthly * 0.5, 2),
  has_fal_license               = true,
  max_members                   = 12
WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'company';

-- نُعطّل المميزة للأدوار غير الشركات لأن المتطلب يحصرها بالشركات فقط
UPDATE public.subscription_plans SET is_active = false
WHERE coalesce(is_trial_plan, false) = false
  AND sort_order = 3
  AND user_type IN ('marketer','office','institution');

-- ---------------------------------------------------------------------------
-- (5) المعلن الفرد (individual)
--     أ) الأساسية (sort_order = 1, 49 ر/شهر): لا تشمل تقديم عروض من الرئيسية
--     ب) العروض الشهرية  (sort_order = 11): 40 عرض / شهر
--     ج) العروض السنوية  (sort_order = 12): 40 عرض / شهر (12 شهر)
--     د) عروض مرة واحدة (sort_order = 13): 3 عروض إجمالية
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans SET
  max_market_offers = 0,
  has_fal_license   = false
WHERE is_active = true
  AND coalesce(is_trial_plan, false) = false
  AND sort_order = 1
  AND user_type = 'individual';

UPDATE public.subscription_plans SET
  max_market_offers    = 40,
  max_listing_requests = 0,
  max_ads_per_month    = 0,
  has_fal_license      = false,
  -- الاسم العربي محدَّث ليعكس الحصّة الجديدة 40 عرضاً
  name_ar              = N'عروض السوق — شهري (40 عرض)',
  name_en              = 'Market offers — monthly (40 offers)'
WHERE is_active = true
  AND user_type = 'individual'
  AND sort_order = 11;

UPDATE public.subscription_plans SET
  max_market_offers    = 40,
  max_listing_requests = 0,
  max_ads_per_month    = 0,
  has_fal_license      = false,
  price_monthly        = 49::numeric,
  price_yearly         = round((49 * 12 * 0.80)::numeric, 2),
  name_ar              = N'عروض السوق — سنوي (40 عرض/شهر · خصم 20%)',
  name_en              = 'Market offers — yearly (40 offers/mo · 20% off)'
WHERE is_active = true
  AND user_type = 'individual'
  AND sort_order = 12;

UPDATE public.subscription_plans SET
  max_market_offers    = 3,
  max_listing_requests = 0,
  max_ads_per_month    = 0,
  has_fal_license      = false,
  price_monthly        = 40::numeric,
  price_yearly         = 40::numeric,
  name_ar              = N'عروض السوق — مرة واحدة (3 عروض)',
  name_en              = 'Market offers — one-time (3 offers)'
WHERE is_active = true
  AND user_type = 'individual'
  AND sort_order = 13;

-- ---------------------------------------------------------------------------
-- (6) الباقات التجريبية: تبقى كما هي (إعلانات + طلبات + عروض = غير محدود)
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans SET
  max_ads_per_month    = NULL,
  max_properties       = NULL,
  max_listing_requests = NULL,
  max_market_offers    = NULL
WHERE coalesce(is_trial_plan, false) = true;

-- ---------------------------------------------------------------------------
-- (7) تحديث RPC: _individual_active_plan_for_uid لاستخدام العمود الجديد
--     max_market_offers بدلاً من max_listing_requests
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._individual_active_plan_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  is_trial boolean,
  starts_at timestamptz,
  ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    p.id,
    coalesce(p.plan_program, 'monthly'),
    coalesce(p.max_market_offers, 0),
    coalesce(s.is_trial, false),
    coalesce(s.starts_at, s.start_date::timestamptz),
    coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active','cancelled')
    AND p.user_type = 'individual'
    AND coalesce(p.max_market_offers, 0) > 0
    AND (
      coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public._individual_active_plan_for_uid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._individual_active_plan_for_uid(uuid)
  TO authenticated, service_role;

COMMIT;

-- =============================================================================
-- تحقّق:
-- SELECT user_type, sort_order, name_ar, plan_program,
--        price_monthly, price_yearly, max_members,
--        max_ads_per_month, max_listing_requests, max_market_offers,
--        has_fal_license, is_active
-- FROM public.subscription_plans
-- WHERE is_active = true
-- ORDER BY user_type, sort_order;
-- =============================================================================
