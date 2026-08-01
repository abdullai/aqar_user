-- =============================================================================
-- 2026-06-17 — إصلاح كتالوج الاشتراكات + التجربة للفرد + RPC للواجهة
-- =============================================================================
-- المشكلة: بعد ترحيلات v5/v6 قد تبقى الباقات معطّلة أو لا يطابق فلتر
-- التطبيق ما في DB → شاشة فارغة. التجربة المجانية لا تظهر للمالك الفردي
-- لأن can_show_trial_tab كان يقتصر على أدوار التسويق فقط.
-- =============================================================================

BEGIN;

-- (1) إعادة تفعيل الكتالوج الكانوني (آمن — لا يحذف صفوفاً)
UPDATE public.subscription_plans
   SET is_active = true
 WHERE coalesce(is_trial_plan, false) = false
   AND (
     (user_type = 'marketer'     AND sort_order IN (1, 21, 22, 23))
     OR (user_type = 'office'    AND sort_order IN (2, 21, 22, 23))
     OR (user_type = 'institution' AND sort_order IN (2, 21, 22, 23))
     OR (user_type = 'company'   AND sort_order = 3)
     OR (user_type = 'individual' AND sort_order IN (1, 11, 12, 13))
   );

UPDATE public.subscription_plans
   SET is_active = true
 WHERE coalesce(is_trial_plan, false) = true
   AND user_type IN ('marketer','office','institution','company','individual');

-- (2) إنشاء أي باقة رئيسية ناقصة
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
     50::numeric, 49.50::numeric, 20.0::numeric, 20.0::numeric,
     1, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'office',
     149::numeric, 1430.40::numeric,
     6::int, NULL::int, 600::int, NULL::int, 49::int,
     true, true, false, true,
     50::numeric, 74.50::numeric, 20.0::numeric, 20.0::numeric,
     2, true, false, 'monthly'),
  (N'الاحترافية', 'Professional',  'institution',
     149::numeric, 1430.40::numeric,
     9::int, NULL::int, 900::int, NULL::int, 49::int,
     true, true, false, true,
     50::numeric, 74.50::numeric, 20.0::numeric, 20.0::numeric,
     2, true, false, 'monthly'),
  (N'المميّزة',  'Premium',       'company',
     499::numeric, 4790.40::numeric,
     12::int, NULL::int, NULL::int, NULL::int, NULL::int,
     true, true, true, true,
     50::numeric, 249.50::numeric, 20.0::numeric, 20.0::numeric,
     3, true, false, 'monthly'),
  (N'أساسي',     'Basic',         'individual',
     49::numeric,  470.40::numeric,
     0::int, NULL::int, 40::int, 15::int, 0::int,
     false, false, false, false,
     0::numeric, 0::numeric, 20.0::numeric, 20.0::numeric,
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
   WHERE sp.user_type = v.user_type
     AND sp.sort_order = v.sort_order
     AND coalesce(sp.is_trial_plan, false) = false
     AND sp.is_active = true
);

-- (3) RPC: قائمة الباقات المرئية للمستخدم الحالي (مصدر الحقيقة)
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
    WHEN 'marketer' THEN ARRAY[1, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3]
    ELSE ARRAY[1, 11, 12, 13]
  END;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
  INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND sp.user_type = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  -- احتياط: أي باقة نشطة للدور إن كان الفلتر أعاد صفراً
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

-- (4) التجربة المجانية: إظهار التبويب للفرد أيضاً
CREATE OR REPLACE FUNCTION public.resolve_subscription_billing_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_org_id uuid;
  v_owner_uid uuid;
  v_is_team_member boolean := false;
  v_is_org_owner boolean := false;
  v_member_role text;
  v_trial_self boolean := false;
  v_trial_owner boolean := false;
  v_has_paid_sub boolean := false;
  v_has_active_trial boolean := false;
  v_fal_expires timestamptz;
  v_fal_hold boolean := false;
  v_fal_status text := 'ok';
  v_disc numeric(5,2) := 50;
  v_seat_price numeric(10,2);
  v_plan_max_members int;
  v_trial_eligible boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT
    coalesce(nullif(trim(up.account_type::text), ''), 'user'),
    up.org_id,
    up.fal_license_expires_at,
    coalesce(up.fal_compliance_hold, false)
  INTO v_at, v_org_id, v_fal_expires, v_fal_hold
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  v_trial_eligible := lower(trim(v_at)) IN (
    'marketer','office','institution','company','agency',
    'individual','individual_seller','owner_individual','public_user','user'
  );

  SELECT o.owner_user_id, o.id, o.fal_license_expires_at
  INTO v_owner_uid, v_org_id, v_fal_expires
  FROM public.org_units o
  WHERE o.owner_user_id = v_uid
  LIMIT 1;

  IF FOUND THEN
    v_is_org_owner := true;
    v_owner_uid := v_uid;
  ELSE
    SELECT
      m.member_role,
      o.owner_user_id,
      o.id,
      o.fal_license_expires_at
    INTO v_member_role, v_owner_uid, v_org_id, v_fal_expires
    FROM public.org_memberships m
    JOIN public.org_units o ON o.id = m.org_id
    WHERE m.user_id = v_uid
      AND m.status = 'active'
    ORDER BY m.created_at DESC
    LIMIT 1;

    IF FOUND AND coalesce(v_member_role, '') <> 'owner' THEN
      v_is_team_member := true;
    END IF;
  END IF;

  v_trial_self := EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_uid
  );

  IF v_owner_uid IS NOT NULL AND v_owner_uid <> v_uid THEN
    v_trial_owner := EXISTS (
      SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_owner_uid
    );
  END IF;

  v_has_paid_sub := EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND coalesce(s.is_trial, false) = false
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  );

  IF v_is_team_member AND v_owner_uid IS NOT NULL THEN
    v_has_paid_sub := v_has_paid_sub OR EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner_uid
        AND coalesce(s.is_trial, false) = false
        AND s.status IN ('active', 'cancelled')
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    );
  END IF;

  v_has_active_trial := EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND coalesce(s.is_trial, false) = true
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  );

  IF v_is_team_member AND v_owner_uid IS NOT NULL AND NOT v_has_active_trial THEN
    v_has_active_trial := EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner_uid
        AND coalesce(s.is_trial, false) = true
        AND s.status IN ('active', 'cancelled')
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    );
  END IF;

  SELECT
    coalesce(p.team_member_discount_percent, 50),
    coalesce(p.seat_unit_price_sar, round(p.price_monthly * 0.5, 2)),
    p.max_members
  INTO v_disc, v_seat_price, v_plan_max_members
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = coalesce(v_owner_uid, v_uid)
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF lower(trim(v_at)) IN ('marketer','office','institution','company','agency') THEN
    IF v_fal_hold THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expires IS NOT NULL AND v_fal_expires <= timezone('utc', now()) THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expires IS NOT NULL
      AND v_fal_expires <= timezone('utc', now()) + interval '7 days' THEN
      v_fal_status := 'warn';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'billing_mode', CASE
      WHEN v_is_team_member THEN 'team_member'
      WHEN v_is_org_owner THEN 'org_owner'
      ELSE 'solo'
    END,
    'is_team_member', v_is_team_member,
    'is_org_owner', v_is_org_owner,
    'is_org_entity', lower(trim(v_at)) IN ('office','institution','company','agency'),
    'is_marketing_role', lower(trim(v_at)) IN ('marketer','office','institution','company','agency'),
    'org_id', v_org_id,
    'org_owner_user_id', v_owner_uid,
    'member_role', v_member_role,
    'trial_used_by_self', v_trial_self,
    'trial_used_by_org_owner', v_trial_owner,
    'can_show_trial_tab', (
      v_trial_eligible
      AND NOT v_is_team_member
      AND NOT v_trial_self
      AND NOT v_has_paid_sub
      AND NOT v_has_active_trial
    ),
    'show_team_member_note', v_is_team_member,
    'team_member_discount_percent', v_disc,
    'seat_unit_price_sar', v_seat_price,
    'plan_max_members', v_plan_max_members,
    'has_active_paid_subscription', v_has_paid_sub,
    'has_active_trial', v_has_active_trial,
    'has_marketing_feature_access', (v_has_paid_sub OR v_has_active_trial),
    'fal_status', v_fal_status,
    'fal_license_expires_at', v_fal_expires,
    'fal_compliance_hold', v_fal_hold,
    'payment_blocked_fal', (v_fal_status = 'blocked')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_subscription_billing_context() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_subscription_billing_context()
  TO authenticated, service_role;

COMMIT;
