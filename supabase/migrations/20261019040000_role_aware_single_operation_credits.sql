-- Role-aware single-operation credits and atomic quota consumption.
-- Apply after 20261019030000_individual_operation_credit_consumption.sql.
-- New individual request credits retain sort 23; marketing one-request credits use sort 24
-- because marketing sort 23 is a legacy ten-request product.

BEGIN;

ALTER TABLE public.market_request_offer_usage_events
  ADD COLUMN IF NOT EXISTS single_use_credit boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX IF NOT EXISTS uq_market_offer_single_use_credit
  ON public.market_request_offer_usage_events (subscription_id)
  WHERE single_use_credit AND subscription_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.market_offer_single_use_credit_usage (
  subscription_id uuid PRIMARY KEY
    REFERENCES public.user_subscriptions (id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  market_request_id uuid,
  used_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);
CREATE INDEX IF NOT EXISTS idx_market_offer_single_use_credit_user
  ON public.market_offer_single_use_credit_usage (user_id, used_at DESC);
ALTER TABLE public.market_offer_single_use_credit_usage ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.market_offer_single_use_credit_usage
  FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.market_request_offer_atomic_authorizations (
  backend_pid integer NOT NULL,
  transaction_id bigint NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  market_request_id uuid NOT NULL,
  PRIMARY KEY (backend_pid, transaction_id, user_id, market_request_id)
);
ALTER TABLE public.market_request_offer_atomic_authorizations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.market_request_offer_atomic_authorizations
  FROM PUBLIC, anon, authenticated;

INSERT INTO public.market_offer_single_use_credit_usage (
  subscription_id, user_id, market_request_id, used_at
)
SELECT DISTINCT ON (e.subscription_id)
  e.subscription_id, e.user_id, e.market_request_id, e.created_at
FROM public.market_request_offer_usage_events e
JOIN public.user_subscriptions s ON s.id = e.subscription_id
JOIN public.subscription_plans p ON p.id = s.plan_id
WHERE p.sort_order = 16
  AND p.plan_program = 'lifetime_one_time'
  AND coalesce(p.max_market_offers, 0) = 1
  AND e.subscription_id IS NOT NULL
ORDER BY e.subscription_id, e.created_at
ON CONFLICT (subscription_id) DO NOTHING;

INSERT INTO public.market_offer_single_use_credit_usage (
  subscription_id, user_id, market_request_id, used_at
)
SELECT q.subscription_id, q.user_id, NULL, q.updated_at
FROM public.market_request_offer_quotas q
JOIN public.user_subscriptions s ON s.id = q.subscription_id
JOIN public.subscription_plans p ON p.id = s.plan_id
WHERE p.sort_order = 16
  AND p.plan_program = 'lifetime_one_time'
  AND coalesce(p.max_market_offers, 0) = 1
  AND q.used_count > 0
  AND q.subscription_id IS NOT NULL
ON CONFLICT (subscription_id) DO NOTHING;

WITH credit_plans AS (
  SELECT * FROM (VALUES
    ('marketer', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
    ('office', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
    ('institution', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
    ('company', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
    ('marketer', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0),
    ('office', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0),
    ('institution', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0),
    ('company', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0)
  ) AS p(user_type, sort_order, name_en, name_ar, price, max_listing_requests, max_market_offers)
)
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type, price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT p.name_ar, p.name_en, p.user_type, p.price, p.price,
  0, NULL, 0, p.max_listing_requests, p.max_market_offers,
  false, false, false, false, 0, 0, 0, 0,
  p.sort_order, true, false, 'lifetime_one_time'
FROM credit_plans p
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans existing
  WHERE existing.user_type = p.user_type
    AND existing.sort_order = p.sort_order
    AND coalesce(existing.is_trial_plan, false) = false
);

UPDATE public.subscription_plans p
SET name_ar = cp.name_ar,
    name_en = cp.name_en,
    price_monthly = cp.price,
    price_yearly = cp.price,
    max_members = 0,
    max_properties = NULL,
    max_ads_per_month = 0,
    max_listing_requests = cp.max_listing_requests,
    max_market_offers = cp.max_market_offers,
    auto_pay_discount_percent = 0,
    sort_order = cp.sort_order,
    is_active = true,
    plan_program = 'lifetime_one_time'
FROM (VALUES
  ('marketer', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
  ('office', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
  ('institution', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
  ('company', 16, 'One Deal Credit', N'رصيد صفقة واحدة', 5::numeric, 0, 1),
  ('marketer', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0),
  ('office', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0),
  ('institution', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0),
  ('company', 24, 'One Property Request Credit', N'رصيد نشر طلب واحد', 3::numeric, 1, 0)
) AS cp(user_type, sort_order, name_en, name_ar, price, max_listing_requests, max_market_offers)
WHERE p.user_type = cp.user_type
  AND p.sort_order = cp.sort_order
  AND coalesce(p.is_trial_plan, false) = false;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(
  p_audience text
)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_audience, '')))
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 16, 21, 22, 24]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 16, 21, 22, 24]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 16, 21, 22, 24]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 16, 24]
    WHEN 'photographer' THEN ARRAY[31, 32, 33]
    WHEN 'individual' THEN ARRAY[1, 14, 11, 12, 16, 23]
    ELSE ARRAY[]::int[]
  END;
$$;

CREATE OR REPLACE FUNCTION public.subscription_can_subscribe(
  p_target_plan_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_owner_active boolean := false;
  v_self_active record;
  v_is_team_member boolean := false;
  v_member_role text;
  v_target_sort int;
  v_target_audience text;
  v_target_program text;
  v_target_listing_count int := 0;
  v_target_deal_count int := 0;
  v_target_is_topup boolean := false;
  v_standalone_once boolean := false;
  v_assert jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_target_plan_id IS NOT NULL THEN
    v_assert := public.subscription_assert_plan_allowed(v_uid, p_target_plan_id);
    IF (v_assert->>'ok')::boolean IS DISTINCT FROM true THEN
      RETURN jsonb_build_object(
        'ok', true, 'can_subscribe', false,
        'reason', coalesce(v_assert->>'error', 'plan_account_mismatch'),
        'detail', v_assert
      );
    END IF;
    SELECT sort_order, lower(trim(user_type)), lower(trim(plan_program)),
           coalesce(max_listing_requests, 0), coalesce(max_market_offers, 0)
      INTO v_target_sort, v_target_audience, v_target_program,
           v_target_listing_count, v_target_deal_count
    FROM public.subscription_plans
    WHERE id = p_target_plan_id;
    v_target_is_topup := coalesce(
      v_target_sort IN (11, 12, 13, 16, 21, 22, 23, 24), false
    );
    v_standalone_once := v_target_program = 'lifetime_one_time'
      AND (
        (v_target_sort = 16 AND v_target_deal_count = 1)
        OR (v_target_audience = 'individual' AND v_target_sort = 23
            AND v_target_listing_count = 1)
        OR (v_target_sort = 24 AND v_target_listing_count = 1
            AND v_target_audience IN ('marketer', 'office', 'institution', 'company'))
      );
  ELSE
    v_target_audience := public.subscription_audience_for_uid(v_uid);
  END IF;

  SELECT m.member_role, o.owner_user_id
    INTO v_member_role, v_owner
  FROM public.org_memberships m
  JOIN public.org_units o ON o.id = m.org_id
  WHERE m.user_id = v_uid AND m.status = 'active'
  ORDER BY m.created_at DESC
  LIMIT 1;
  IF FOUND AND v_owner IS NOT NULL AND v_owner <> v_uid
     AND coalesce(v_member_role, '') <> 'owner' THEN
    v_is_team_member := true;
  END IF;

  IF v_is_team_member AND v_target_audience <> 'photographer' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner
        AND coalesce(s.is_trial, false) = false
        AND coalesce(s.is_topup, false) = false
        AND s.status IN ('active', 'cancelled')
        AND (coalesce(s.is_lifetime, false)
          OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
    ) INTO v_owner_active;
    RETURN jsonb_build_object(
      'ok', true, 'can_subscribe', false,
      'reason', 'team_member_uses_owner_subscription',
      'owner_user_id', v_owner,
      'owner_has_active_subscription', v_owner_active
    );
  END IF;

  IF v_standalone_once THEN
    RETURN jsonb_build_object(
      'ok', true, 'can_subscribe', true,
      'standalone_operation_credit', true
    );
  END IF;

  SELECT s.id, s.plan_id, s.period, s.starts_at, s.ends_at, s.status
    INTO v_self_active
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND coalesce(s.is_trial, false) = false
    AND coalesce(s.is_topup, false) = false
    AND s.status = 'active'
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
    AND (v_target_audience IS NULL OR s.service_audience = v_target_audience)
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_target_is_topup THEN
    IF v_self_active.id IS NULL THEN
      RETURN jsonb_build_object('ok', true, 'can_subscribe', false,
        'reason', 'topup_requires_main_subscription');
    END IF;
    RETURN jsonb_build_object('ok', true, 'can_subscribe', true,
      'topup_purchase', true, 'main_subscription_id', v_self_active.id);
  END IF;

  IF v_self_active.id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'can_subscribe', false,
      'reason', 'already_active_subscription',
      'subscription_id', v_self_active.id, 'plan_id', v_self_active.plan_id,
      'period', v_self_active.period, 'starts_at', v_self_active.starts_at,
      'ends_at', v_self_active.ends_at, 'upgrade_only', true);
  END IF;
  RETURN jsonb_build_object('ok', true, 'can_subscribe', true);
END;
$$;

CREATE OR REPLACE FUNCTION public._set_user_subscription_is_topup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sort int;
  v_type text;
  v_program text;
BEGIN
  SELECT sort_order, lower(trim(user_type)), lower(trim(plan_program))
    INTO v_sort, v_type, v_program
  FROM public.subscription_plans WHERE id = NEW.plan_id;
  NEW.is_topup := coalesce(v_sort IN (11, 12, 13, 21, 22, 23, 24), false)
    OR (v_sort = 16 AND v_program = 'lifetime_one_time'
        AND v_type IN ('individual', 'marketer', 'office', 'institution', 'company'));
  RETURN NEW;
END;
$$;

UPDATE public.user_subscriptions s
SET is_topup = coalesce(p.sort_order IN (11, 12, 13, 21, 22, 23, 24), false)
  OR (p.sort_order = 16 AND lower(trim(p.plan_program)) = 'lifetime_one_time'
      AND lower(trim(p.user_type)) IN
        ('individual', 'marketer', 'office', 'institution', 'company'))
FROM public.subscription_plans p
WHERE p.id = s.plan_id
  AND s.is_topup IS DISTINCT FROM (
    coalesce(p.sort_order IN (11, 12, 13, 21, 22, 23, 24), false)
    OR (p.sort_order = 16 AND lower(trim(p.plan_program)) = 'lifetime_one_time'
        AND lower(trim(p.user_type)) IN
          ('individual', 'marketer', 'office', 'institution', 'company'))
  );

CREATE OR REPLACE FUNCTION public._market_offer_topup_plans_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  starts_at timestamptz,
  ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, p.id, coalesce(p.plan_program, 'monthly'),
         coalesce(p.max_market_offers, 0),
         coalesce(s.starts_at, s.start_date::timestamptz),
         coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active', 'cancelled')
    AND coalesce(p.max_market_offers, 0) > 0
    AND public.subscription_audience_for_uid(p_uid) IN
      ('individual', 'marketer', 'office', 'institution', 'company')
    AND (p.user_type = public.subscription_audience_for_uid(p_uid)
      OR (public.subscription_audience_for_uid(p_uid) = 'office'
          AND p.user_type = 'agency'))
    AND (
      (p.sort_order IN (11, 12, 13)
       AND p.user_type IN ('marketer', 'office', 'institution', 'company', 'agency'))
      OR (p.user_type = 'individual' AND p.sort_order IN (11, 12, 13, 16))
      OR (p.sort_order = 16 AND p.plan_program = 'lifetime_one_time'
          AND p.user_type IN ('marketer', 'office', 'institution', 'company'))
    )
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(p.plan_program, '') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
  ORDER BY s.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public._listing_requests_topup_plans_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  starts_at timestamptz,
  ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, p.id, coalesce(p.plan_program, 'monthly'),
         coalesce(p.max_listing_requests, 0),
         coalesce(s.starts_at, s.start_date::timestamptz),
         coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active', 'cancelled')
    AND coalesce(p.max_listing_requests, 0) > 0
    AND public.subscription_audience_for_uid(p_uid) IN
      ('individual', 'marketer', 'office', 'institution', 'company')
    AND (p.user_type = public.subscription_audience_for_uid(p_uid)
      OR (public.subscription_audience_for_uid(p_uid) = 'office'
          AND p.user_type = 'agency'))
    AND (
      (p.user_type IN ('marketer', 'office', 'institution', 'company', 'agency')
       AND p.sort_order IN (21, 22, 23, 24))
      OR (p.user_type = 'individual' AND p.sort_order = 23
          AND coalesce(p.plan_program, '') = 'lifetime_one_time')
    )
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(p.plan_program, '') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
  ORDER BY s.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public._count_offer_usage_for_user(
  p_uid uuid,
  p_subscription_id uuid,
  p_period_start date,
  p_lifetime boolean
)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN p_lifetime AND EXISTS (
    SELECT 1
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.id = p_subscription_id
      AND p.sort_order = 16
      AND coalesce(p.max_market_offers, 0) = 1
  ) THEN (
    SELECT count(*)::int
    FROM public.market_offer_single_use_credit_usage u
    WHERE u.user_id = p_uid AND u.subscription_id = p_subscription_id
  ) ELSE (
    SELECT count(*)::int
    FROM public.market_request_offer_usage_events e
    WHERE e.user_id = p_uid
      AND (p_lifetime OR (e.subscription_id = p_subscription_id
                          AND e.period_start = p_period_start))
  ) END;
$$;

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
  v_main record;
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
  SELECT coalesce(nullif(lower(trim(account_type::text)), ''), 'user')
    INTO v_at FROM public.users_profiles WHERE user_id = v_uid;
  v_is_marketing := v_at IN ('marketer', 'office', 'institution', 'company', 'agency');
  v_bill_uid := v_uid;
  IF v_is_marketing THEN
    IF p_organization_id IS NOT NULL THEN
      SELECT o.owner_user_id INTO v_bill_uid FROM public.org_units o
      WHERE o.id = p_organization_id;
    ELSE
      SELECT o.owner_user_id INTO v_bill_uid
      FROM public.org_memberships m JOIN public.org_units o ON o.id = m.org_id
      WHERE m.user_id = v_uid AND m.status = 'active'
      ORDER BY m.created_at DESC LIMIT 1;
    END IF;
    v_bill_uid := coalesce(v_bill_uid, v_uid);
    SELECT * INTO v_main FROM public._marketing_active_plan_for_uid(v_bill_uid);
  ELSE
    SELECT * INTO v_main FROM public._individual_main_plan_for_uid(v_uid);
  END IF;

  IF v_main.plan_id IS NOT NULL THEN
    v_main_program := v_main.plan_program;
    v_main_is_trial := v_main.is_trial;
    v_main_unlimited := v_main.max_count IS NULL;
    v_main_max := CASE WHEN v_main_unlimited THEN 999999
      ELSE coalesce(v_main.max_count, 0) END;
    v_main_lifetime := v_main.plan_program = 'lifetime_one_time';
    SELECT pb.period_start, pb.period_end
      INTO v_main_period_start, v_main_period_end
    FROM public._offer_quota_period_bounds(v_main.starts_at, v_main.plan_program) pb;
    IF NOT v_main_unlimited THEN
      v_main_used := public._count_offer_usage_for_user(
        v_bill_uid, v_main.subscription_id, v_main_period_start, v_main_lifetime
      );
    END IF;
  END IF;

  FOR v_topup IN
    SELECT t.*, p.sort_order
    FROM public._market_offer_topup_plans_for_uid(v_uid) t
    JOIN public.subscription_plans p ON p.id = t.plan_id
    WHERE v_main.plan_id IS NOT NULL
       OR (t.plan_program = 'lifetime_one_time'
           AND ((p.sort_order = 16 AND coalesce(p.max_market_offers, 0) = 1)
             OR (NOT v_is_marketing AND p.user_type = 'individual'
                 AND p.sort_order = 13)))
  LOOP
    DECLARE
      v_t_period_start date;
      v_t_period_end date;
      v_t_used int;
      v_t_lifetime boolean := v_topup.plan_program = 'lifetime_one_time';
    BEGIN
      SELECT pb.period_start, pb.period_end INTO v_t_period_start, v_t_period_end
      FROM public._offer_quota_period_bounds(v_topup.starts_at, v_topup.plan_program) pb;
      v_t_used := public._count_offer_usage_for_user(
        v_uid, v_topup.subscription_id, v_t_period_start, v_t_lifetime
      );
      v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
      v_topup_used := v_topup_used + coalesce(v_t_used, 0);
      v_topup_records := v_topup_records || jsonb_build_array(jsonb_build_object(
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
      ));
    END;
  END LOOP;

  v_total_max := CASE WHEN v_main_unlimited THEN 999999
    ELSE v_main_max + v_topup_max END;
  v_total_used := v_main_used + v_topup_used;
  RETURN jsonb_build_object(
    'ok', true, 'authenticated', true,
    'audience', CASE WHEN v_is_marketing THEN 'marketing' ELSE 'individual' END,
    'has_subscription', v_main.plan_id IS NOT NULL OR v_topup_max > 0,
    'has_main_plan', v_main.plan_id IS NOT NULL,
    'main', CASE WHEN v_main.plan_id IS NULL THEN NULL ELSE jsonb_build_object(
      'subscription_id', v_main.subscription_id, 'plan_id', v_main.plan_id,
      'plan_program', v_main_program, 'is_trial', v_main_is_trial,
      'unlimited', v_main_unlimited,
      'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
      'used', v_main_used,
      'remaining', CASE WHEN v_main_unlimited THEN NULL
        ELSE greatest(0, v_main_max - v_main_used) END,
      'period_start', v_main_period_start, 'period_end', v_main_period_end,
      'starts_at', v_main.starts_at, 'ends_at', v_main.ends_at
    ) END,
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

CREATE OR REPLACE FUNCTION public.consume_single_market_offer_credit(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_audience text;
  v_credit record;
  v_start date;
  v_end date;
BEGIN
  IF v_uid IS NULL OR p_request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));
  v_audience := public.subscription_audience_for_uid(v_uid);

  IF EXISTS (
    SELECT 1 FROM public.market_offer_single_use_credit_usage u
    WHERE u.user_id = v_uid AND u.market_request_id = p_request_id
  ) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'single_use_credit_already_used');
  END IF;

  SELECT s.id AS subscription_id, p.id AS plan_id,
         coalesce(p.plan_program, 'lifetime_one_time') AS plan_program,
         p.max_market_offers AS max_count, s.starts_at
    INTO v_credit
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_uid
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_topup, false)
    AND p.sort_order = 16
    AND p.plan_program = 'lifetime_one_time'
    AND p.max_market_offers = 1
    AND p.user_type = v_audience
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
    AND NOT EXISTS (
      SELECT 1 FROM public.market_offer_single_use_credit_usage u
      WHERE u.subscription_id = s.id
    )
  ORDER BY s.created_at
  LIMIT 1
  FOR UPDATE OF s;

  IF v_credit.subscription_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_single_use_credit');
  END IF;
  SELECT pb.period_start, pb.period_end INTO v_start, v_end
  FROM public._offer_quota_period_bounds(v_credit.starts_at, v_credit.plan_program) pb;

  INSERT INTO public.market_offer_single_use_credit_usage (
    subscription_id, user_id, market_request_id
  ) VALUES (v_credit.subscription_id, v_uid, p_request_id);

  INSERT INTO public.market_request_offer_usage_events (
    user_id, market_request_id, subscription_id, plan_program, period_start,
    single_use_credit
  ) VALUES (
    v_uid, p_request_id, v_credit.subscription_id,
    v_credit.plan_program, v_start, true
  );
  INSERT INTO public.market_request_offer_quotas (
    user_id, subscription_id, plan_program, period_start, period_end,
    used_count, max_count
  ) VALUES (
    v_uid, v_credit.subscription_id, v_credit.plan_program,
    v_start, v_end, 1, 1
  ) ON CONFLICT (user_id, subscription_id, period_start)
  DO UPDATE SET used_count = market_request_offer_quotas.used_count + 1,
                updated_at = now();
  RETURN jsonb_build_object('ok', true, 'subscription_id', v_credit.subscription_id,
    'used', 1, 'max', 1, 'remaining', 0, 'single_use_credit', true);
END;
$$;

DO $$
BEGIN
  IF to_regprocedure('public.record_market_request_offer_usage(uuid)') IS NOT NULL
     AND to_regprocedure('public.record_market_request_offer_usage_legacy(uuid)') IS NULL THEN
    ALTER FUNCTION public.record_market_request_offer_usage(uuid)
      RENAME TO record_market_request_offer_usage_legacy;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_market_request_offer_usage(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  v_result := public.consume_single_market_offer_credit(p_request_id);
  IF coalesce((v_result->>'ok')::boolean, false)
     OR coalesce(v_result->>'error', '') <> 'no_single_use_credit' THEN
    IF coalesce(v_result->>'error', '') <> 'single_use_credit_already_used' THEN
      RETURN v_result;
    END IF;
  END IF;
  RETURN public.record_market_request_offer_usage_legacy(p_request_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_market_request_offer_usage(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.submit_market_request_offer_with_quota(
  p_request_id uuid,
  p_message text DEFAULT NULL,
  p_price_offer numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_requester uuid;
  v_request_status text;
  v_existing_id uuid;
  v_existing_status text;
  v_is_instant_paid boolean := false;
  v_usage jsonb;
  v_updated boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_request');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));

  SELECT r.requester_id, lower(coalesce(r.status, '')),
         coalesce(r.request_priority, 'standard') = 'immediate'
           AND c.status = 'consumed'
           AND c.market_request_id = r.id AS is_instant_paid
    INTO v_requester, v_request_status, v_is_instant_paid
  FROM public.market_property_requests r
  LEFT JOIN public.market_request_instant_credits c
    ON c.id = r.instant_credit_id AND c.user_id = r.requester_id
  WHERE r.id = p_request_id
  FOR SHARE OF r;
  IF NOT FOUND OR v_requester = v_uid
     OR v_request_status NOT IN ('published', 'active', 'open') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_unavailable');
  END IF;

  SELECT id, lower(coalesce(status, ''))
    INTO v_existing_id, v_existing_status
  FROM public.market_request_offers
  WHERE market_request_id = p_request_id AND offerer_id = v_uid
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing_status IN ('submitted', 'pending') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'offer_already_active');
    END IF;
    IF v_existing_status NOT IN
      ('withdrawn', 'rejected', 'declined',
       'cancelled', 'canceled') THEN
      RETURN jsonb_build_object('ok', false, 'error', 'offer_already_active');
    END IF;
    v_updated := true;
  END IF;

  IF NOT coalesce(v_is_instant_paid, false) THEN
    v_usage := public.record_market_request_offer_usage(p_request_id);
    IF coalesce((v_usage->>'ok')::boolean, false) IS DISTINCT FROM true THEN
      RETURN jsonb_build_object('ok', false,
        'error', coalesce(v_usage->>'error', 'quota_rejected'));
    END IF;
  END IF;

  INSERT INTO public.market_request_offer_atomic_authorizations (
    backend_pid, transaction_id, user_id, market_request_id
  ) VALUES (pg_backend_pid(), txid_current(), v_uid, p_request_id);

  IF v_updated THEN
    UPDATE public.market_request_offers
    SET message = nullif(trim(coalesce(p_message, '')), ''),
        price_offer = p_price_offer,
        status = 'submitted'
    WHERE id = v_existing_id;
  ELSE
    INSERT INTO public.market_request_offers (
      market_request_id, offerer_id, message, price_offer, status
    ) VALUES (
      p_request_id, v_uid, nullif(trim(coalesce(p_message, '')), ''),
      p_price_offer, 'submitted'
    );
  END IF;
  DELETE FROM public.market_request_offer_atomic_authorizations
  WHERE backend_pid = pg_backend_pid()
    AND transaction_id = txid_current()
    AND user_id = v_uid
    AND market_request_id = p_request_id;

  RETURN jsonb_build_object('ok', true, 'updated', v_updated,
    'quota', v_usage);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_market_request_offer_with_quota(uuid, text, numeric)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.submit_market_request_offer_with_quota(uuid, text, numeric)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_market_offer_quota_before_submit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_usage jsonb;
  v_atomic_authorized boolean := false;
BEGIN
  IF lower(coalesce(NEW.status, '')) NOT IN ('submitted', 'pending') THEN
    RETURN NEW;
  END IF;
  IF v_uid IS NULL OR NEW.offerer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'offerer_not_authenticated_user';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.market_property_requests r
    WHERE r.id = NEW.market_request_id
      AND r.requester_id <> v_uid
      AND lower(coalesce(r.status, '')) IN ('published', 'active', 'open')
  ) THEN
    RAISE EXCEPTION 'request_unavailable';
  END IF;

  DELETE FROM public.market_request_offer_atomic_authorizations a
  WHERE a.backend_pid = pg_backend_pid()
    AND a.transaction_id = txid_current()
    AND a.user_id = v_uid
    AND a.market_request_id = NEW.market_request_id
  RETURNING true INTO v_atomic_authorized;

  IF coalesce(v_atomic_authorized, false)
     OR (TG_OP = 'UPDATE'
         AND lower(coalesce(OLD.status, '')) IN ('submitted', 'pending')
         AND lower(coalesce(NEW.status, '')) IN ('submitted', 'pending')) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.market_request_offer_usage_events e
    WHERE e.user_id = v_uid AND e.market_request_id = NEW.market_request_id
      AND e.single_use_credit
  ) THEN
    RAISE EXCEPTION 'single_use_credit_already_used';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.market_property_requests r
    JOIN public.market_request_instant_credits c
      ON c.id = r.instant_credit_id AND c.user_id = r.requester_id
    WHERE r.id = NEW.market_request_id
      AND coalesce(r.request_priority, 'standard') = 'immediate'
      AND c.status = 'consumed'
      AND c.market_request_id = r.id
  ) THEN
    RETURN NEW;
  END IF;

  v_usage := public.record_market_request_offer_usage(NEW.market_request_id);
  IF coalesce((v_usage->>'ok')::boolean, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION '%', coalesce(v_usage->>'error', 'offer_quota_rejected');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_market_offer_quota_before_submit
  ON public.market_request_offers;
CREATE TRIGGER tr_market_offer_quota_before_submit
  BEFORE INSERT OR UPDATE OF status ON public.market_request_offers
  FOR EACH ROW EXECUTE FUNCTION public.enforce_market_offer_quota_before_submit();

REVOKE ALL ON FUNCTION public.consume_single_market_offer_credit(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_market_request_offer_usage(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_market_offer_quota_before_submit()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_market_request_offer_usage(uuid)
  TO service_role;
REVOKE ALL ON FUNCTION public.record_market_request_offer_usage_legacy(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_market_request_offer_usage_legacy(uuid)
  TO service_role;

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
  v_is_marketing boolean := false;
  v_main record;
  v_main_max int := 0;
  v_main_unlimited boolean := false;
  v_main_is_lifetime boolean := false;
  v_main_usage_start timestamptz;
  v_main_used int := 0;
  v_topup record;
  v_topup_max int := 0;
  v_topup_used int := 0;
  v_topup_records jsonb := '[]'::jsonb;
  v_total_max int := 0;
  v_total_used int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true, 'authenticated', false, 'audience', 'guest',
      'has_subscription', false, 'has_main_plan', false,
      'unlimited', false, 'total_max', 0, 'total_used', 0,
      'total_remaining', 0, 'needs_paywall', true, 'note', 'auth_required'
    );
  END IF;
  SELECT coalesce(nullif(lower(trim(account_type::text)), ''), 'user')
    INTO v_at FROM public.users_profiles WHERE user_id = v_uid;
  v_is_marketing := v_at IN ('marketer', 'office', 'institution', 'company', 'agency');
  v_bill_uid := v_uid;
  IF v_is_marketing THEN
    IF p_organization_id IS NOT NULL THEN
      SELECT o.owner_user_id INTO v_bill_uid FROM public.org_units o
      WHERE o.id = p_organization_id;
    ELSE
      SELECT o.owner_user_id INTO v_bill_uid
      FROM public.org_memberships m JOIN public.org_units o ON o.id = m.org_id
      WHERE m.user_id = v_uid AND m.status = 'active'
      ORDER BY m.created_at DESC LIMIT 1;
    END IF;
    v_bill_uid := coalesce(v_bill_uid, v_uid);
  END IF;

  SELECT s.id AS subscription_id, p.id AS plan_id, p.max_listing_requests,
         p.plan_program, coalesce(s.is_trial, false) AS is_trial,
         coalesce(s.is_lifetime, false) AS is_lifetime,
         s.starts_at, s.ends_at, s.end_date
    INTO v_main
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_bill_uid AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_topup, false) = false
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
  ORDER BY s.created_at DESC LIMIT 1;

  IF v_main.subscription_id IS NOT NULL THEN
    v_main_is_lifetime := v_main.is_lifetime
      OR coalesce(v_main.plan_program, '') = 'lifetime_one_time';
    v_main_usage_start := CASE WHEN v_main_is_lifetime
      THEN coalesce(v_main.starts_at, now())
      ELSE date_trunc('month', timezone('utc', now())) END;
    IF v_main.max_listing_requests IS NULL THEN
      v_main_unlimited := true;
      v_main_max := 999999;
    ELSE
      v_main_max := greatest(0, v_main.max_listing_requests);
    END IF;
    SELECT count(*) INTO v_main_used
    FROM public.market_property_requests r
    WHERE r.requester_id = v_bill_uid
      AND lower(coalesce(r.status, '')) = 'published'
      AND r.instant_credit_id IS NULL
      AND r.request_quota_subscription_id IS NULL
      AND (v_is_marketing OR coalesce(r.published_at, r.created_at) >= v_main_usage_start);
  END IF;

  FOR v_topup IN
    SELECT t.*, p.sort_order, p.user_type
    FROM public._listing_requests_topup_plans_for_uid(v_uid) t
    JOIN public.subscription_plans p ON p.id = t.plan_id
    WHERE v_main.subscription_id IS NOT NULL
       OR (t.plan_program = 'lifetime_one_time'
           AND ((p.sort_order = 24 AND coalesce(p.max_listing_requests, 0) = 1)
             OR (p.user_type = 'individual' AND p.sort_order = 23
                 AND coalesce(p.max_listing_requests, 0) = 1)))
  LOOP
    v_topup_used := 0;
    IF v_topup.plan_program = 'lifetime_one_time'
       AND coalesce(v_topup.max_count, 0) = 1
       AND (v_topup.sort_order = 24
         OR (v_topup.user_type = 'individual' AND v_topup.sort_order = 23)) THEN
      SELECT count(*) INTO v_topup_used
      FROM public.market_request_subscription_usage u
      WHERE u.subscription_id = v_topup.subscription_id
        AND u.single_use_credit;
    END IF;
    v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
    v_total_used := v_total_used + v_topup_used;
    v_topup_records := v_topup_records || jsonb_build_array(jsonb_build_object(
      'subscription_id', v_topup.subscription_id, 'plan_id', v_topup.plan_id,
      'plan_program', v_topup.plan_program, 'max', v_topup.max_count,
      'used', v_topup_used,
      'remaining', greatest(0, v_topup.max_count - v_topup_used),
      'starts_at', v_topup.starts_at, 'ends_at', v_topup.ends_at
    ));
  END LOOP;

  v_total_used := v_total_used + v_main_used;
  v_total_max := CASE WHEN v_main_unlimited THEN 999999
    ELSE v_main_max + v_topup_max END;
  RETURN jsonb_build_object(
    'ok', true, 'authenticated', true,
    'audience', CASE WHEN v_is_marketing THEN 'marketing' ELSE 'individual' END,
    'has_subscription', v_main.subscription_id IS NOT NULL OR v_topup_max > 0,
    'has_main_plan', v_main.subscription_id IS NOT NULL,
    'main', CASE WHEN v_main.subscription_id IS NULL THEN NULL ELSE jsonb_build_object(
      'subscription_id', v_main.subscription_id, 'plan_id', v_main.plan_id,
      'is_trial', v_main.is_trial, 'is_lifetime', v_main_is_lifetime,
      'unlimited', v_main_unlimited,
      'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
      'used', v_main_used,
      'remaining', CASE WHEN v_main_unlimited THEN NULL
        ELSE greatest(0, v_main_max - v_main_used) END,
      'starts_at', v_main.starts_at, 'ends_at', v_main.ends_at
    ) END,
    'topups', v_topup_records, 'total_used', v_total_used,
    'total_max', CASE WHEN v_main_unlimited THEN NULL ELSE v_total_max END,
    'total_remaining', CASE WHEN v_main_unlimited THEN NULL
      ELSE greatest(0, v_total_max - v_total_used) END,
    'unlimited', v_main_unlimited,
    'needs_paywall', (v_main.subscription_id IS NULL AND v_topup_max = 0)
      OR (NOT v_main_unlimited AND v_total_used >= v_total_max),
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
  v_uid uuid := auth.uid();
  v_allowance jsonb;
  v_remaining int := 0;
  v_credit_subscription_id uuid;
BEGIN
  IF lower(coalesce(NEW.status, '')) <> 'published' OR v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND lower(coalesce(OLD.status, '')) = 'published' THEN
    NEW.request_quota_subscription_id := OLD.request_quota_subscription_id;
    RETURN NEW;
  END IF;
  IF NEW.requester_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'requester_not_authenticated_user';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));
  NEW.request_quota_subscription_id := NULL;

  IF coalesce(NEW.request_priority, 'standard') = 'immediate'
     AND NEW.instant_credit_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.market_request_instant_credits c
       WHERE c.id = NEW.instant_credit_id AND c.user_id = v_uid
         AND c.status = 'consumed' AND c.market_request_id = NEW.id
     ) THEN
    NEW.published_at := timezone('utc', now());
    NEW.updated_at := NEW.published_at;
    RETURN NEW;
  END IF;

  v_allowance := public.listing_requests_unified_allowance(NULL);
  v_remaining := coalesce((v_allowance->>'total_max')::int, 0)
    - coalesce((v_allowance->>'total_used')::int, 0);
  IF coalesce((v_allowance->>'ok')::boolean, false) IS DISTINCT FROM true
     OR coalesce((v_allowance->>'has_subscription')::boolean, false) IS DISTINCT FROM true
     OR (coalesce((v_allowance->>'unlimited')::boolean, false) IS DISTINCT FROM true
         AND v_remaining <= 0) THEN
    RAISE EXCEPTION 'subscription_required_to_publish_market_request';
  END IF;

  SELECT s.id INTO v_credit_subscription_id
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_uid AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_topup, false)
    AND p.plan_program = 'lifetime_one_time'
    AND coalesce(p.max_listing_requests, 0) = 1
    AND ((p.user_type = 'individual' AND p.sort_order = 23)
      OR (p.sort_order = 24 AND p.user_type = public.subscription_audience_for_uid(v_uid)))
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
    AND NOT EXISTS (
      SELECT 1 FROM public.market_request_subscription_usage u
      WHERE u.subscription_id = s.id AND u.single_use_credit
    )
  ORDER BY s.created_at
  LIMIT 1
  FOR UPDATE OF s;
  IF v_credit_subscription_id IS NOT NULL THEN
    NEW.request_quota_subscription_id := v_credit_subscription_id;
  END IF;
  NEW.published_at := timezone('utc', now());
  NEW.updated_at := NEW.published_at;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_market_request_subscription_usage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND lower(coalesce(OLD.status, '')) = 'published'
     AND lower(coalesce(NEW.status, '')) = 'published' THEN
    RETURN NEW;
  END IF;
  IF lower(coalesce(NEW.status, '')) = 'published'
     AND NEW.request_quota_subscription_id IS NOT NULL THEN
    INSERT INTO public.market_request_subscription_usage (
      subscription_id, user_id, market_request_id, single_use_credit
    )
    SELECT s.id, NEW.requester_id, NEW.id, true
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.id = NEW.request_quota_subscription_id
      AND s.user_id = NEW.requester_id
      AND coalesce(s.is_topup, false)
      AND p.plan_program = 'lifetime_one_time'
      AND coalesce(p.max_listing_requests, 0) = 1
      AND ((p.user_type = 'individual' AND p.sort_order = 23)
        OR (p.sort_order = 24
            AND p.user_type = public.subscription_audience_for_uid(NEW.requester_id)));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_market_request_subscription_quota
  ON public.market_property_requests;
CREATE TRIGGER tr_market_request_subscription_quota
  BEFORE INSERT OR UPDATE ON public.market_property_requests
  FOR EACH ROW EXECUTE FUNCTION public.enforce_market_request_subscription_quota();

DROP TRIGGER IF EXISTS tr_market_request_subscription_usage
  ON public.market_property_requests;
CREATE TRIGGER tr_market_request_subscription_usage
  AFTER INSERT OR UPDATE ON public.market_property_requests
  FOR EACH ROW EXECUTE FUNCTION public.record_market_request_subscription_usage();

REVOKE ALL ON FUNCTION public.enforce_market_request_subscription_quota()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_market_request_subscription_usage()
  FROM PUBLIC;

COMMIT;
