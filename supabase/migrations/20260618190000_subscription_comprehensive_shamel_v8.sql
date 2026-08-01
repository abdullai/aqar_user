-- =============================================================================
-- 2026-06-18 — باقة «الشامل» + تحديث حدود الأساسي/عروض السوق للفرد
-- =============================================================================
BEGIN;

-- ── (1) الفرد — الأساسي (sort 1): 40 إعلان، طلبات غير محدودة، 3 عروض/شهر ──
UPDATE public.subscription_plans SET
  max_ads_per_month    = 40,
  max_listing_requests = NULL,
  max_market_offers    = 3,
  max_members          = 0,
  has_fal_license      = false,
  name_ar              = N'أساسي',
  name_en              = 'Basic',
  price_monthly        = 49::numeric,
  price_yearly         = round((49 * 12 * 0.80)::numeric, 2)
WHERE is_active = true
  AND coalesce(is_trial_plan, false) = false
  AND user_type = 'individual'
  AND sort_order = 1;

-- ── (2) الفرد — عروض السوق شهري (sort 11): 3 إعلانات + 40 عرض ────────────
UPDATE public.subscription_plans SET
  max_ads_per_month    = 3,
  max_listing_requests = 0,
  max_market_offers    = 40,
  max_members          = 0,
  has_fal_license      = false,
  name_ar              = N'عروض السوق — شهري (40 عرض)',
  name_en              = 'Market offers — monthly (40 offers)',
  price_monthly        = 49::numeric,
  price_yearly         = round((49 * 12 * 0.80)::numeric, 2)
WHERE is_active = true
  AND coalesce(is_trial_plan, false) = false
  AND user_type = 'individual'
  AND sort_order = 11;

-- ── (3) الفرد — باقة الشامل (sort 14) — 89 ر/شهر ─────────────────────────
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
SELECT
  N'الشامل', 'Comprehensive', 'individual',
  89::numeric, round((89 * 12 * 0.80)::numeric, 2),
  3, NULL::int, 49::int,
  49::int, 40::int,
  true, false, false, false,
  50::numeric, round(89 * 0.5, 2),
  20.0::numeric, 20.0::numeric,
  14, true, false, 'monthly'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
  WHERE sp.user_type = 'individual'
    AND sp.sort_order = 14
    AND coalesce(sp.is_trial_plan, false) = false
);

UPDATE public.subscription_plans SET
  is_active = true,
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 89,
  price_yearly = round((89 * 12 * 0.80)::numeric, 2),
  max_ads_per_month = 49,
  max_listing_requests = 49,
  max_market_offers = 40,
  max_members = 3,
  has_fal_license = true,
  seat_unit_price_sar = round(89 * 0.5, 2)
WHERE user_type = 'individual'
  AND sort_order = 14
  AND coalesce(is_trial_plan, false) = false;

-- ── (4) المسوّق — الشامل (sort 4) — 149 ر/شهر ─────────────────────────────
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
SELECT
  N'الشامل', 'Comprehensive', 'marketer',
  149::numeric, round((149 * 12 * 0.80)::numeric, 2),
  6, NULL::int, 99::int,
  NULL::int, 49::int,
  true, true, false, true,
  50::numeric, round(149 * 0.5, 2),
  20.0::numeric, 20.0::numeric,
  4, true, false, 'monthly'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
  WHERE sp.user_type = 'marketer' AND sp.sort_order = 4
    AND coalesce(sp.is_trial_plan, false) = false
);

UPDATE public.subscription_plans SET
  is_active = true,
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 149,
  price_yearly = round((149 * 12 * 0.80)::numeric, 2),
  max_ads_per_month = 99,
  max_listing_requests = NULL,
  max_market_offers = 49,
  max_members = 6,
  has_fal_license = true
WHERE user_type = 'marketer'
  AND sort_order = 4
  AND coalesce(is_trial_plan, false) = false;

-- ── (5) المكتب / المؤسسة — الشامل (sort 4) ───────────────────────────────
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
SELECT v.name_ar, v.name_en, v.user_type,
  v.price_monthly, v.price_yearly,
  v.max_members, v.max_properties, v.max_ads_per_month,
  v.max_listing_requests, v.max_market_offers,
  v.has_fal_license, v.has_analytics, v.has_api_access, v.has_priority_support,
  v.team_member_discount_percent, v.seat_unit_price_sar,
  v.auto_pay_discount_percent, v.cancellation_retention_offer_pct,
  v.sort_order, v.is_active, v.is_trial_plan, v.plan_program
FROM (VALUES
  (N'الشامل', 'Comprehensive', 'office',
   199::numeric, round((199 * 12 * 0.80)::numeric, 2),
   9::int, NULL::int, 699::int, NULL::int, 49::int,
   true, true, false, true,
   50::numeric, round(199 * 0.5, 2), 20.0::numeric, 20.0::numeric,
   4, true, false, 'monthly'),
  (N'الشامل', 'Comprehensive', 'institution',
   199::numeric, round((199 * 12 * 0.80)::numeric, 2),
   12::int, NULL::int, 999::int, NULL::int, 49::int,
   true, true, false, true,
   50::numeric, round(199 * 0.5, 2), 20.0::numeric, 20.0::numeric,
   4, true, false, 'monthly')
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
  WHERE sp.user_type = v.user_type
    AND sp.sort_order = 4
    AND coalesce(sp.is_trial_plan, false) = false
);

UPDATE public.subscription_plans SET
  is_active = true,
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 199,
  price_yearly = round((199 * 12 * 0.80)::numeric, 2),
  max_ads_per_month = CASE user_type WHEN 'office' THEN 699 ELSE 999 END,
  max_listing_requests = NULL,
  max_market_offers = 49,
  max_members = CASE user_type WHEN 'office' THEN 9 ELSE 12 END,
  has_fal_license = true
WHERE user_type IN ('office', 'institution')
  AND sort_order = 4
  AND coalesce(is_trial_plan, false) = false;

-- ── (6) الشركة — الشامل (sort 4) — 399 ر/شهر ──────────────────────────────
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
SELECT
  N'الشامل', 'Comprehensive', 'company',
  399::numeric, round((399 * 12 * 0.80)::numeric, 2),
  18, NULL::int, NULL::int, NULL::int, NULL::int,
  true, true, true, true,
  50::numeric, round(399 * 0.5, 2),
  20.0::numeric, 20.0::numeric,
  4, true, false, 'monthly'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
  WHERE sp.user_type = 'company' AND sp.sort_order = 4
    AND coalesce(sp.is_trial_plan, false) = false
);

UPDATE public.subscription_plans SET
  is_active = true,
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 399,
  price_yearly = round((399 * 12 * 0.80)::numeric, 2),
  max_ads_per_month = NULL,
  max_listing_requests = NULL,
  max_market_offers = NULL,
  max_members = 18,
  has_fal_license = true
WHERE user_type = 'company'
  AND sort_order = 4
  AND coalesce(is_trial_plan, false) = false;

-- ── (7) كتالوج RPC — إظهار باقة الشامل ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_plan_type text;
  v_allowed int[];
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required', 'plans', '[]'::jsonb);
  END IF;

  SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
  INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;

  v_allowed := CASE v_plan_type
    WHEN 'marketer' THEN ARRAY[1, 4, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4]
    ELSE ARRAY[1, 14, 11, 12, 13]
  END;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
  INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND sp.user_type = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  IF v_rows IS NULL OR jsonb_array_length(v_rows) = 0 THEN
    SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
    INTO v_rows
    FROM public.subscription_plans sp
    WHERE sp.is_active = true
      AND coalesce(sp.is_trial_plan, false) = false
      AND sp.user_type = v_plan_type;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans()
  TO authenticated, service_role;

COMMIT;
