-- Individual owner catalog: monthly/yearly main plans plus a lifetime main plan.
-- Apply manually after review. This migration is intentionally not deployed here.

BEGIN;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS published_at timestamptz;

UPDATE public.market_property_requests
SET published_at = coalesce(updated_at, created_at, timezone('utc', now()))
WHERE lower(coalesce(status, '')) = 'published'
  AND published_at IS NULL;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(
  p_audience text
)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_audience, '')))
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    WHEN 'photographer' THEN ARRAY[31, 32, 33]
    WHEN 'individual' THEN ARRAY[1, 14, 15, 11, 12, 13]
    ELSE ARRAY[]::int[]
  END;
$$;

-- Keep existing monthly/yearly individual prices and quotas canonical.
UPDATE public.subscription_plans
SET name_ar = N'باقة الشريك',
    name_en = 'Partner Plan',
    price_monthly = 49,
    price_yearly = 470.40,
    max_members = 0,
    max_ads_per_month = 0,
    max_listing_requests = 10,
    max_market_offers = 3,
    plan_program = 'monthly',
    is_active = true
WHERE user_type = 'individual'
  AND sort_order = 1
  AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans
SET name_ar = N'باقة الشامل',
    name_en = 'Comprehensive Plan',
    price_monthly = 89,
    price_yearly = 854.40,
    max_members = 0,
    max_ads_per_month = 0,
    max_listing_requests = 49,
    max_market_offers = 40,
    plan_program = 'monthly',
    is_active = true
WHERE user_type = 'individual'
  AND sort_order = 14
  AND coalesce(is_trial_plan, false) = false;

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
  N'باقة الشريك', 'Partner Plan', 'individual',
  49, 470.40,
  0, NULL, 0,
  10, 3,
  false, false, false, false,
  0, 0,
  10, 0,
  1, true, false, 'monthly'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans
  WHERE user_type = 'individual' AND sort_order = 1
    AND coalesce(is_trial_plan, false) = false
);

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
  N'باقة الشامل', 'Comprehensive Plan', 'individual',
  89, 854.40,
  0, NULL, 0,
  49, 40,
  false, false, false, false,
  0, 0,
  10, 0,
  14, true, false, 'monthly'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans
  WHERE user_type = 'individual' AND sort_order = 14
    AND coalesce(is_trial_plan, false) = false
);

UPDATE public.subscription_plans
SET name_ar = N'باقة الشريك — مرة واحدة',
    name_en = 'Partner Plan — One-time',
    price_monthly = 79,
    price_yearly = 79,
    max_members = 0,
    max_ads_per_month = 0,
    max_listing_requests = 10,
    max_market_offers = 10,
    auto_pay_discount_percent = 0,
    plan_program = 'lifetime_one_time',
    is_active = true
WHERE user_type = 'individual'
  AND sort_order = 15
  AND coalesce(is_trial_plan, false) = false;

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
  N'باقة الشريك — مرة واحدة', 'Partner Plan — One-time', 'individual',
  79, 79,
  0, NULL, 0,
  10, 10,
  false, false, false, false,
  0, 0,
  0, 0,
  15, true, false, 'lifetime_one_time'
WHERE NOT EXISTS (
  SELECT 1
  FROM public.subscription_plans
  WHERE user_type = 'individual'
    AND sort_order = 15
    AND coalesce(is_trial_plan, false) = false
);

-- Three-day trial: one listing, one published request, and one completed deal.
UPDATE public.subscription_plans
SET name_ar = N'تجربة ٣ أيام',
    name_en = '3-day trial',
    price_monthly = 0,
    price_yearly = 0,
    max_members = 0,
    max_properties = 1,
    max_ads_per_month = 1,
    max_listing_requests = 1,
    max_market_offers = 1,
    has_fal_license = user_type <> 'individual',
    has_analytics = user_type <> 'individual',
    auto_pay_discount_percent = 0,
    plan_program = 'monthly',
    is_active = true
WHERE coalesce(is_trial_plan, false) = true
  AND user_type IN ('individual', 'marketer', 'office', 'institution', 'company');

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
  N'تجربة ٣ أيام', '3-day trial', v.user_type,
  0, 0,
  0, 1, 1,
  1, 1,
  v.user_type <> 'individual', v.user_type <> 'individual', false, false,
  0, 0, 0, 0,
  0, true, true, 'monthly'
FROM (VALUES ('individual'), ('marketer'), ('office'), ('institution'), ('company'))
  AS v(user_type)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans p
  WHERE p.user_type = v.user_type
    AND coalesce(p.is_trial_plan, false) = true
);

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

  PERFORM pg_advisory_xact_lock(hashtext('user-trial:' || v_uid::text));
  IF EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used
    WHERE user_id = v_uid
  ) OR EXISTS (
    SELECT 1 FROM public.photographer_trial_subscriptions_used
    WHERE user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
  END IF;

  SELECT coalesce(nullif(lower(trim(account_type::text)), ''), 'user')
    INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;
  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  IF v_at NOT IN (
    'marketer', 'office', 'institution', 'company', 'agency',
    'individual', 'public_user', 'owner_individual', 'individual_seller', 'user'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'role_not_eligible_for_trial');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND coalesce(s.is_trial, false) = false
      AND s.status IN ('active', 'cancelled')
      AND (
        coalesce(s.is_lifetime, false)
        OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
      )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'paid_subscription_active');
  END IF;

  v_plan_type := CASE v_at
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'institution' THEN 'institution'
    WHEN 'company' THEN 'company'
    WHEN 'agency' THEN 'office'
    ELSE 'individual'
  END;

  SELECT p.id INTO v_plan_id
  FROM public.subscription_plans p
  WHERE p.is_active = true
    AND coalesce(p.is_trial_plan, false) = true
    AND p.user_type = v_plan_type
  ORDER BY p.sort_order
  LIMIT 1;
  IF v_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_plan_missing');
  END IF;

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, auto_renew, starts_at, ends_at, is_trial
  ) VALUES (
    v_uid, NULL, v_plan_id, 'active', 'monthly',
    current_date, v_end, false, now(), v_ends, true
  ) RETURNING id INTO v_sub_id;

  INSERT INTO public.user_trial_subscriptions_used (user_id, subscription_id)
  VALUES (v_uid, v_sub_id);

  RETURN jsonb_build_object(
    'ok', true,
    'subscription_id', v_sub_id,
    'plan_id', v_plan_id,
    'plan_type', v_plan_type,
    'is_trial', true,
    'ends_at', v_ends,
    'days', 3,
    'limits', jsonb_build_object(
      'max_members', 0,
      'max_ads_per_month', 1,
      'max_listing_requests', 1,
      'max_market_offers', 1
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_marketing_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_marketing_trial_subscription()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.photographer_trial_already_used()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used
    WHERE user_id = auth.uid()
  ) OR EXISTS (
    SELECT 1 FROM public.photographer_trial_subscriptions_used
    WHERE user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.photographer_trial_already_used() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_trial_already_used()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.activate_photographer_trial_subscription()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_plan_id uuid;
  v_subscription_id uuid;
  v_start timestamptz := now();
  v_ends timestamptz := now() + interval '3 days';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('user-trial:' || v_uid::text));
  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles
    WHERE user_id = v_uid AND status = 'verified'
  ) THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'photographer_profile_not_verified'
    );
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_uid
  ) OR EXISTS (
    SELECT 1 FROM public.photographer_trial_subscriptions_used WHERE user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
  END IF;
  IF public.user_has_active_photographer_subscription(v_uid) THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'photographer_subscription_active'
    );
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND coalesce(s.is_trial, false) = false
      AND s.status IN ('active', 'cancelled')
      AND (
        coalesce(s.is_lifetime, false)
        OR coalesce(s.ends_at, s.end_date::timestamptz) > v_start
      )
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'paid_subscription_active');
  END IF;

  SELECT id INTO v_plan_id
  FROM public.subscription_plans
  WHERE user_type = 'photographer'
    AND is_active = true
    AND coalesce(is_trial_plan, false) = true
    AND sort_order = 0
  ORDER BY id
  LIMIT 1;
  IF v_plan_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'photographer_trial_plan_missing'
    );
  END IF;

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, starts_at, ends_at, auto_renew, is_trial
  ) VALUES (
    v_uid, NULL, v_plan_id, 'active', 'monthly',
    v_start::date, (v_ends::date), v_start, v_ends, false, true
  ) RETURNING id INTO v_subscription_id;

  INSERT INTO public.user_trial_subscriptions_used (user_id, subscription_id)
  VALUES (v_uid, v_subscription_id);
  INSERT INTO public.photographer_trial_subscriptions_used(user_id, subscription_id)
  VALUES (v_uid, v_subscription_id);

  RETURN jsonb_build_object(
    'ok', true,
    'subscription_id', v_subscription_id,
    'plan_id', v_plan_id,
    'is_trial', true,
    'ends_at', v_ends,
    'days', 3
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_photographer_trial_subscription()
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_photographer_trial_subscription()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._individual_main_plan_for_uid(p_uid uuid)
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
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_topup, false) = false
    AND p.user_type = 'individual'
    AND (coalesce(s.is_trial, false) OR p.sort_order IN (1, 14, 15))
    AND coalesce(p.max_market_offers, 0) > 0
    AND (
      coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY coalesce(s.is_trial, false) DESC, s.created_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public._individual_main_plan_for_uid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._individual_main_plan_for_uid(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.market_offer_unified_allowance(
  p_organization_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bill_uid uuid;
  v_at text;
  v_is_marketing boolean := false;
  v_main_record record;
  v_topup record;
  v_main_max int := 0;
  v_main_used int := 0;
  v_main_period_start date;
  v_main_period_end date;
  v_main_lifetime boolean := false;
  v_main_unlimited boolean := false;
  v_topup_max int := 0;
  v_topup_used int := 0;
  v_total_max int := 0;
  v_total_used int := 0;
  v_main_program text;
  v_main_is_trial boolean := false;
  v_topup_records jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'user')
    INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;

  v_is_marketing := lower(coalesce(v_at, '')) IN
    ('marketer', 'office', 'institution', 'company', 'agency');
  v_bill_uid := v_uid;

  IF v_is_marketing THEN
    IF p_organization_id IS NOT NULL THEN
      SELECT o.owner_user_id INTO v_bill_uid
      FROM public.org_units o
      WHERE o.id = p_organization_id;
    ELSE
      SELECT o.owner_user_id INTO v_bill_uid
      FROM public.org_memberships m
      JOIN public.org_units o ON o.id = m.org_id
      WHERE m.user_id = v_uid AND m.status = 'active'
      ORDER BY m.created_at DESC
      LIMIT 1;
    END IF;
    v_bill_uid := coalesce(v_bill_uid, v_uid);
    SELECT * INTO v_main_record
    FROM public._marketing_active_plan_for_uid(v_bill_uid);
  ELSE
    SELECT * INTO v_main_record
    FROM public._individual_main_plan_for_uid(v_uid);
  END IF;

  IF v_main_record.plan_id IS NOT NULL THEN
    v_main_program := v_main_record.plan_program;
    v_main_is_trial := v_main_record.is_trial;
      IF v_main_record.max_count IS NULL THEN
      v_main_unlimited := true;
      v_main_max := 999999;
    ELSE
      v_main_max := coalesce(v_main_record.max_count, 0);
    END IF;
    v_main_lifetime := v_main_record.plan_program = 'lifetime_one_time';
    SELECT pb.period_start, pb.period_end
      INTO v_main_period_start, v_main_period_end
    FROM public._offer_quota_period_bounds(
      v_main_record.starts_at, v_main_record.plan_program
    ) pb;
    IF NOT v_main_unlimited THEN
      v_main_used := public._count_offer_usage_for_user(
        v_bill_uid, v_main_record.subscription_id,
        v_main_period_start, v_main_lifetime
      );
    END IF;
  END IF;

  IF v_main_record.plan_id IS NULL THEN
    v_topup_max := 0;
    v_topup_used := 0;
    v_topup_records := '[]'::jsonb;
  END IF;

  FOR v_topup IN
    SELECT * FROM public._market_offer_topup_plans_for_uid(v_uid)
    WHERE v_main_record.plan_id IS NOT NULL
  LOOP
    DECLARE
      v_t_period_start date;
      v_t_period_end date;
      v_t_used int;
      v_t_lifetime boolean := v_topup.plan_program = 'lifetime_one_time';
    BEGIN
      SELECT pb.period_start, pb.period_end
        INTO v_t_period_start, v_t_period_end
      FROM public._offer_quota_period_bounds(
        v_topup.starts_at, v_topup.plan_program
      ) pb;
      v_t_used := public._count_offer_usage_for_user(
        v_uid, v_topup.subscription_id, v_t_period_start, v_t_lifetime
      );
      v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
      v_topup_used := v_topup_used + coalesce(v_t_used, 0);
      v_topup_records := v_topup_records || jsonb_build_array(
        jsonb_build_object(
          'subscription_id', v_topup.subscription_id,
          'plan_id', v_topup.plan_id,
          'plan_program', v_topup.plan_program,
          'max', v_topup.max_count,
          'used', v_t_used,
          'remaining', greatest(0, v_topup.max_count - coalesce(v_t_used, 0)),
          'period_start', v_t_period_start,
          'period_end', v_t_period_end,
          'starts_at', v_topup.starts_at,
          'ends_at', v_topup.ends_at
        )
      );
    END;
  END LOOP;

  IF v_main_unlimited THEN
    v_total_max := 999999;
  ELSE
    v_total_max := v_main_max + v_topup_max;
  END IF;
  v_total_used := v_main_used + v_topup_used;

  RETURN jsonb_build_object(
    'ok', true,
    'authenticated', true,
    'audience', CASE WHEN v_is_marketing THEN 'marketing' ELSE 'individual' END,
    'has_subscription', v_main_record.plan_id IS NOT NULL,
    'has_main_plan', v_main_record.plan_id IS NOT NULL,
    'main', CASE
      WHEN v_main_record.plan_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'subscription_id', v_main_record.subscription_id,
        'plan_id', v_main_record.plan_id,
        'plan_program', v_main_program,
        'is_trial', v_main_is_trial,
        'unlimited', v_main_unlimited,
        'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
        'used', v_main_used,
        'remaining', CASE WHEN v_main_unlimited THEN NULL
          ELSE greatest(0, v_main_max - v_main_used) END,
        'period_start', v_main_period_start,
        'period_end', v_main_period_end,
        'starts_at', v_main_record.starts_at,
        'ends_at', v_main_record.ends_at
      )
    END,
    'topups', v_topup_records,
    'total_used', v_total_used,
    'total_max', CASE WHEN v_main_unlimited THEN NULL ELSE v_total_max END,
    'total_remaining', CASE WHEN v_main_unlimited THEN NULL
      ELSE greatest(0, v_total_max - v_total_used) END,
    'unlimited', v_main_unlimited,
    'needs_paywall', NOT v_main_unlimited AND v_total_used >= v_total_max,
    'billing_user_id', v_bill_uid
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.record_market_request_offer_usage(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_is_marketing boolean := false;
  v_plan record;
  v_candidate record;
  v_audience text;
  v_period_start date;
  v_period_end date;
  v_max int := 0;
  v_used int := 0;
  v_lifetime boolean := false;
  v_unlimited boolean := false;
  v_selected boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_request');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));

  SELECT coalesce(nullif(trim(account_type::text), ''), 'user')
    INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;
  v_is_marketing := lower(coalesce(v_at, '')) IN
    ('marketer', 'office', 'institution', 'company', 'agency');

  IF v_is_marketing THEN
    SELECT * INTO v_candidate
    FROM public._marketing_active_plan_for_uid(v_uid);
    IF v_candidate.plan_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'no_subscription');
    END IF;
    v_plan := v_candidate;
    v_audience := 'marketing';
    v_unlimited := v_plan.max_count IS NULL;
    v_max := CASE WHEN v_unlimited THEN 999999
      ELSE coalesce(v_plan.max_count, 0) END;
    v_lifetime := v_plan.plan_program = 'lifetime_one_time';
    SELECT pb.period_start, pb.period_end INTO v_period_start, v_period_end
    FROM public._offer_quota_period_bounds(v_plan.starts_at, v_plan.plan_program) pb;
    IF NOT v_unlimited THEN
      v_used := public._count_offer_usage_for_user(
        v_uid, v_plan.subscription_id, v_period_start, v_lifetime
      );
      IF v_used >= v_max THEN
        RETURN jsonb_build_object('ok', false, 'error', 'quota_exhausted',
          'used', v_used, 'max', v_max, 'remaining', 0);
      END IF;
    END IF;
  ELSE
    v_audience := 'individual';
    SELECT * INTO v_candidate
    FROM public._individual_main_plan_for_uid(v_uid);
    IF v_candidate.plan_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'main_subscription_required');
    END IF;
    IF v_candidate.plan_id IS NOT NULL THEN
      v_period_start := NULL;
      v_period_end := NULL;
      v_lifetime := v_candidate.plan_program = 'lifetime_one_time';
      SELECT pb.period_start, pb.period_end INTO v_period_start, v_period_end
      FROM public._offer_quota_period_bounds(
        v_candidate.starts_at, v_candidate.plan_program
      ) pb;
      v_used := public._count_offer_usage_for_user(
        v_uid, v_candidate.subscription_id, v_period_start, v_lifetime
      );
      IF v_used < coalesce(v_candidate.max_count, 0) THEN
        v_plan := v_candidate;
        v_max := coalesce(v_candidate.max_count, 0);
        v_selected := true;
      END IF;
    END IF;

    IF NOT v_selected THEN
      FOR v_candidate IN
        SELECT * FROM public._market_offer_topup_plans_for_uid(v_uid)
      LOOP
        v_lifetime := v_candidate.plan_program = 'lifetime_one_time';
        SELECT pb.period_start, pb.period_end INTO v_period_start, v_period_end
        FROM public._offer_quota_period_bounds(
          v_candidate.starts_at, v_candidate.plan_program
        ) pb;
        v_used := public._count_offer_usage_for_user(
          v_uid, v_candidate.subscription_id, v_period_start, v_lifetime
        );
        IF v_used < coalesce(v_candidate.max_count, 0) THEN
          v_plan := v_candidate;
          v_max := coalesce(v_candidate.max_count, 0);
          v_selected := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    IF NOT v_selected THEN
      RETURN jsonb_build_object('ok', false, 'error',
        CASE WHEN v_candidate.plan_id IS NULL THEN 'no_subscription'
          ELSE 'quota_exhausted' END,
        'used', v_used, 'max', v_max, 'remaining', 0);
    END IF;
  END IF;

  INSERT INTO public.market_request_offer_usage_events (
    user_id, market_request_id, subscription_id, plan_program, period_start
  ) VALUES (
    v_uid, p_request_id, v_plan.subscription_id,
    coalesce(v_plan.plan_program, 'monthly'), v_period_start
  );

  INSERT INTO public.market_request_offer_quotas (
    user_id, subscription_id, plan_program, period_start, period_end,
    used_count, max_count
  ) VALUES (
    v_uid, v_plan.subscription_id, coalesce(v_plan.plan_program, 'monthly'),
    v_period_start, v_period_end, 1, v_max
  ) ON CONFLICT (user_id, subscription_id, period_start)
    DO UPDATE SET
      used_count = market_request_offer_quotas.used_count + 1,
      updated_at = now();

  v_used := public._count_offer_usage_for_user(
    v_uid, v_plan.subscription_id, v_period_start, v_lifetime
  );
  RETURN jsonb_build_object(
    'ok', true, 'used', v_used, 'max', v_max,
    'remaining', greatest(0, v_max - v_used), 'audience', v_audience
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.listing_requests_unified_allowance(
  p_organization_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bill_uid uuid;
  v_at text;
  v_main record;
  v_main_max int := 0;
  v_main_unlimited boolean := false;
  v_main_is_lifetime boolean := false;
  v_main_usage_start timestamptz;
  v_topup record;
  v_topup_max int := 0;
  v_topup_records jsonb := '[]'::jsonb;
  v_total_max int := 0;
  v_used int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'authenticated', false,
      'audience', 'guest', 'has_subscription', false,
      'unlimited', false, 'total_max', 0, 'total_used', 0,
      'total_remaining', 0, 'needs_paywall', true, 'note', 'auth_required');
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'user')
    INTO v_at
  FROM public.users_profiles WHERE user_id = v_uid;
  v_bill_uid := v_uid;
  IF lower(coalesce(v_at, '')) IN
      ('marketer', 'office', 'institution', 'company', 'agency') THEN
    IF p_organization_id IS NOT NULL THEN
      SELECT o.owner_user_id INTO v_bill_uid
      FROM public.org_units o WHERE o.id = p_organization_id;
    ELSE
      SELECT o.owner_user_id INTO v_bill_uid
      FROM public.org_memberships m
      JOIN public.org_units o ON o.id = m.org_id
      WHERE m.user_id = v_uid AND m.status = 'active'
      ORDER BY m.created_at DESC LIMIT 1;
    END IF;
    v_bill_uid := coalesce(v_bill_uid, v_uid);
  END IF;

  SELECT s.id AS subscription_id, p.id AS plan_id,
         p.max_listing_requests, p.plan_program,
         coalesce(s.is_trial, false) AS is_trial,
         coalesce(s.is_lifetime, false) AS is_lifetime,
         s.starts_at, s.ends_at, s.end_date
    INTO v_main
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_bill_uid
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_topup, false) = false
    AND (
      coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_main.subscription_id IS NOT NULL THEN
    v_main_is_lifetime := v_main.is_lifetime
      OR coalesce(v_main.plan_program, '') = 'lifetime_one_time';
    v_main_usage_start := CASE
      WHEN v_main_is_lifetime THEN coalesce(v_main.starts_at, now())
      ELSE date_trunc('month', timezone('utc', now()))
    END;
    IF v_main.max_listing_requests IS NULL THEN
      v_main_unlimited := true;
      v_main_max := 999999;
    ELSE
      v_main_max := greatest(0, v_main.max_listing_requests);
    END IF;
  END IF;

  FOR v_topup IN
    SELECT * FROM public._listing_requests_topup_plans_for_uid(v_uid)
  LOOP
    v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
    v_topup_records := v_topup_records || jsonb_build_array(jsonb_build_object(
      'subscription_id', v_topup.subscription_id,
      'plan_id', v_topup.plan_id,
      'plan_program', v_topup.plan_program,
      'max', v_topup.max_count,
      'starts_at', v_topup.starts_at,
      'ends_at', v_topup.ends_at
    ));
  END LOOP;

  IF v_main.subscription_id IS NOT NULL THEN
    SELECT count(*) INTO v_used
    FROM public.market_property_requests
    WHERE requester_id = v_bill_uid
      AND lower(coalesce(status, '')) = 'published'
      AND (
        v_is_marketing
        OR coalesce(published_at, created_at) >= v_main_usage_start
      );
  END IF;

  IF v_main_unlimited THEN
    v_total_max := 999999;
  ELSE
    v_total_max := v_main_max + v_topup_max;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'authenticated', true,
    'audience', CASE WHEN lower(coalesce(v_at, '')) IN
      ('marketer', 'office', 'institution', 'company', 'agency')
      THEN 'marketing' ELSE 'individual' END,
    'has_subscription', v_main.subscription_id IS NOT NULL,
    'has_main_plan', v_main.subscription_id IS NOT NULL,
    'main', CASE WHEN v_main.subscription_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'subscription_id', v_main.subscription_id,
        'plan_id', v_main.plan_id,
        'is_trial', v_main.is_trial,
        'is_lifetime', v_main_is_lifetime,
        'unlimited', v_main_unlimited,
        'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
        'starts_at', v_main.starts_at,
        'ends_at', v_main.ends_at
      ) END,
    'topups', v_topup_records,
    'total_used', v_used,
    'total_max', CASE WHEN v_main_unlimited THEN NULL ELSE v_total_max END,
    'total_remaining', CASE WHEN v_main_unlimited THEN NULL
      ELSE greatest(0, v_total_max - v_used) END,
    'unlimited', v_main_unlimited,
    'needs_paywall', v_main.subscription_id IS NULL
      OR (NOT v_main_unlimited AND v_used >= v_total_max),
    'billing_user_id', v_bill_uid
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_market_request_subscription_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_allowance jsonb;
  v_remaining int := 0;
  v_uid uuid := auth.uid();
BEGIN
  IF lower(coalesce(NEW.status, '')) <> 'published' OR v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND lower(coalesce(OLD.status, '')) = 'published' THEN
    RETURN NEW;
  END IF;

  NEW.updated_at := timezone('utc', now());

  IF NEW.requester_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'requester_not_authenticated_user';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));
  v_allowance := public.listing_requests_unified_allowance(NULL);
  v_remaining := coalesce((v_allowance->>'total_max')::int, 0)
    - coalesce((v_allowance->>'total_used')::int, 0);

  IF coalesce((v_allowance->>'ok')::boolean, false) IS DISTINCT FROM true
     OR coalesce((v_allowance->>'has_subscription')::boolean, false) IS DISTINCT FROM true
     OR (
       coalesce((v_allowance->>'unlimited')::boolean, false) IS DISTINCT FROM true
       AND v_remaining <= 0
     ) THEN
    RAISE EXCEPTION 'subscription_required_to_publish_market_request';
  END IF;

  NEW.published_at := timezone('utc', now());
  NEW.updated_at := NEW.published_at;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_market_request_subscription_quota
  ON public.market_property_requests;
CREATE TRIGGER tr_market_request_subscription_quota
  BEFORE INSERT OR UPDATE ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_market_request_subscription_quota();

REVOKE ALL ON FUNCTION public.enforce_market_request_subscription_quota()
  FROM PUBLIC;

COMMIT;