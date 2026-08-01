-- =============================================================================
-- 2026-06-02 — توسعة باقات v6:
--   • إضافة باقة تجريبية للمالك الفردي (3 أيام، 5 إعلانات/عروض/طلبات).
--   • تَوب-أب الطلبات العقارية للأدوار التسويقية:
--       sort_order = 21  → شهري:    39 ر.س / 30 طلب/شهر
--       sort_order = 22  → سنوي:    374.40 ر.س / 30 طلب/شهر (خصم 20%)
--       sort_order = 23  → مرّة:    30 ر.س / 10 طلبات (lifetime_one_time)
-- =============================================================================
-- الفلسفة:
--   • كل دور تسويقي سيرى: «التجريبية» + «الباقة الرئيسية» + «تَوب-أب الطلبات»
--     (= 3 خيارات منظّمة بدون تكرار).
--   • المالك الفردي سيرى: «التجريبية» + «الأساسي» + «عروض السوق 11/12/13»
--     (= 5 خيارات: تجربة، رئيسي، 3 توب-أب).
-- =============================================================================

BEGIN;

-- =============================================================================
-- (A) باقة تجريبية للمالك الفردي
-- =============================================================================
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT
  N'تجريبي ٣ أيام', 'Trial 3 days', 'individual',
  0::numeric, 0::numeric,
  0::int, 5::int, 5::int, 5::int, 5::int,
  false, false, false, false,
  0::numeric, 0::numeric,
  0::numeric, 0::numeric,
  0::int, true, true, 'monthly'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type = 'individual'
     AND coalesce(sp.is_trial_plan, false) = true
);

-- =============================================================================
-- (B) تَوب-أب الطلبات العقارية للأدوار التسويقية
--     plan_program مثل عروض السوق: monthly / yearly / lifetime_one_time
-- =============================================================================

-- مساعدة: نُنشئ صفّاً واحداً لكل (role × sort) فقط إن لم يوجد.
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT * FROM (VALUES
  -- ─────── المسوّق ───────
  (N'طلبات إضافية — شهري (٣٠ طلب/شهر)', 'Listing Requests — Monthly (30/mo)',
     'marketer',
     39::numeric, 374.40::numeric,
     0::int, NULL::int, NULL::int, 30::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 0::numeric,
     21, true, false, 'monthly'),
  (N'طلبات إضافية — سنوي (٣٠ طلب/شهر · خصم ٢٠٪)', 'Listing Requests — Yearly',
     'marketer',
     374.40::numeric, 374.40::numeric,
     0::int, NULL::int, NULL::int, 30::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 0::numeric,
     22, true, false, 'yearly'),
  (N'طلبات إضافية — مرّة واحدة (١٠ طلبات)', 'Listing Requests — One-time',
     'marketer',
     30::numeric, 30::numeric,
     0::int, NULL::int, NULL::int, 10::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     0::numeric, 0::numeric,
     23, true, false, 'lifetime_one_time'),

  -- ─────── المكتب ───────
  (N'طلبات إضافية — شهري (٣٠ طلب/شهر)', 'Listing Requests — Monthly (30/mo)',
     'office',
     39::numeric, 374.40::numeric,
     0::int, NULL::int, NULL::int, 30::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 0::numeric,
     21, true, false, 'monthly'),
  (N'طلبات إضافية — سنوي (٣٠ طلب/شهر · خصم ٢٠٪)', 'Listing Requests — Yearly',
     'office',
     374.40::numeric, 374.40::numeric,
     0::int, NULL::int, NULL::int, 30::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 0::numeric,
     22, true, false, 'yearly'),
  (N'طلبات إضافية — مرّة واحدة (١٠ طلبات)', 'Listing Requests — One-time',
     'office',
     30::numeric, 30::numeric,
     0::int, NULL::int, NULL::int, 10::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     0::numeric, 0::numeric,
     23, true, false, 'lifetime_one_time'),

  -- ─────── المؤسسة ───────
  (N'طلبات إضافية — شهري (٣٠ طلب/شهر)', 'Listing Requests — Monthly (30/mo)',
     'institution',
     39::numeric, 374.40::numeric,
     0::int, NULL::int, NULL::int, 30::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 0::numeric,
     21, true, false, 'monthly'),
  (N'طلبات إضافية — سنوي (٣٠ طلب/شهر · خصم ٢٠٪)', 'Listing Requests — Yearly',
     'institution',
     374.40::numeric, 374.40::numeric,
     0::int, NULL::int, NULL::int, 30::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     20.0::numeric, 0::numeric,
     22, true, false, 'yearly'),
  (N'طلبات إضافية — مرّة واحدة (١٠ طلبات)', 'Listing Requests — One-time',
     'institution',
     30::numeric, 30::numeric,
     0::int, NULL::int, NULL::int, 10::int, NULL::int,
     false, false, false, false,
     0::numeric, 0::numeric,
     0::numeric, 0::numeric,
     23, true, false, 'lifetime_one_time')
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type  = v.user_type
     AND sp.sort_order = v.sort_order
     AND coalesce(sp.is_trial_plan, false) = false
);

-- =============================================================================
-- (C) تحديث activate_marketing_trial_subscription لقبول individual أيضاً
-- =============================================================================
CREATE OR REPLACE FUNCTION public.activate_marketing_trial_subscription()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_plan_type text;
  v_plan_id uuid;
  v_sub_id uuid;
  v_end date := current_date + 3;
  v_ends timestamptz := now() + interval '3 days';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'marketer')
  INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  IF lower(trim(v_at)) NOT IN
       ('marketer','office','institution','company','agency','individual','public_user') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'role_not_eligible_for_trial');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_subscriptions
    WHERE user_id = v_uid
      AND coalesce(is_trial, false) = false
      AND status IN ('active','cancelled')
      AND coalesce(ends_at, end_date::timestamptz) > now()
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'paid_subscription_active');
  END IF;

  v_plan_type := CASE trim(lower(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'agency' THEN 'office'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    ELSE 'marketer'
  END;

  SELECT id INTO v_plan_id
  FROM public.subscription_plans
  WHERE is_active = true
    AND is_trial_plan = true
    AND user_type = v_plan_type
  ORDER BY sort_order ASC
  LIMIT 1;

  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id
    FROM public.subscription_plans
    WHERE is_active = true
      AND coalesce(is_trial_plan, false) = false
      AND user_type = v_plan_type AND sort_order = 1
    LIMIT 1;
  END IF;

  IF v_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_plan_available');
  END IF;

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, auto_renew, starts_at, ends_at,
    is_trial
  )
  VALUES (
    v_uid, NULL, v_plan_id, 'active', 'monthly',
    current_date, v_end, false, now(), v_ends,
    true
  )
  RETURNING id INTO v_sub_id;

  INSERT INTO public.user_trial_subscriptions_used (user_id, subscription_id)
  VALUES (v_uid, v_sub_id);

  RETURN jsonb_build_object(
    'ok', true,
    'subscription_id', v_sub_id,
    'plan_id', v_plan_id,
    'plan_type', v_plan_type,
    'is_trial', true,
    'is_trial_plan', true,
    'ends_at', v_ends,
    'days', 3
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_marketing_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_marketing_trial_subscription()
  TO authenticated, service_role;

-- =============================================================================
-- (D) تشخيص نهائي: عرض كامل ما يَراه كل دور
-- =============================================================================
DO $$
DECLARE r record;
BEGIN
  RAISE NOTICE '== الباقات النشطة بعد v6 ==';
  FOR r IN
    SELECT user_type, sort_order, is_trial_plan, name_ar, price_monthly,
           is_active
      FROM public.subscription_plans
     WHERE is_active = true
     ORDER BY user_type, sort_order, is_trial_plan DESC
  LOOP
    RAISE NOTICE '  % / sort=% / trial=% / % / m=%',
      r.user_type, r.sort_order, r.is_trial_plan, r.name_ar, r.price_monthly;
  END LOOP;
END $$;

COMMIT;
