-- One-time individual purchases are single-operation credits, not lifetime plans.
-- Apply after 20261019010000_deduplicate_individual_main_plans.sql.

BEGIN;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS request_quota_subscription_id uuid
    REFERENCES public.user_subscriptions (id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.market_request_subscription_usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL
    REFERENCES public.user_subscriptions (id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  market_request_id uuid REFERENCES public.market_property_requests (id)
    ON DELETE SET NULL,
  single_use_credit boolean NOT NULL DEFAULT false,
  used_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_market_request_subscription_usage_request
  ON public.market_request_subscription_usage (market_request_id)
  WHERE market_request_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_market_request_single_use_credit
  ON public.market_request_subscription_usage (subscription_id)
  WHERE single_use_credit;

ALTER TABLE public.market_request_subscription_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY market_request_subscription_usage_select_own
  ON public.market_request_subscription_usage
  FOR SELECT TO authenticated USING (user_id = auth.uid());
REVOKE ALL ON public.market_request_subscription_usage
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.market_request_subscription_usage TO authenticated;

-- Retire the former lifetime main plan and legacy multi-deal plan from new sales.
-- Existing subscription rows remain intact and continue to use their original plan.
UPDATE public.subscription_plans
SET is_active = false
WHERE user_type = 'individual'
  AND sort_order = 15
  AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans
SET is_active = true
WHERE user_type = 'individual'
  AND sort_order IN (11, 12, 14)
  AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans
SET is_active = true,
    name_ar = N'رصيد صفقة واحدة',
    name_en = 'One Deal Credit',
    price_monthly = 5,
    price_yearly = 5,
    max_members = 0,
    max_ads_per_month = 0,
    max_listing_requests = 0,
    max_market_offers = 1,
    auto_pay_discount_percent = 0,
    plan_program = 'lifetime_one_time'
WHERE user_type = 'individual'
  AND sort_order = 16
  AND coalesce(is_trial_plan, false) = false;

INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type, price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT N'رصيد صفقة واحدة', 'One Deal Credit', 'individual', 5, 5,
  0, NULL, 0, 0, 1,
  false, false, false, false, 0, 0, 0, 0,
  16, true, false, 'lifetime_one_time'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans
  WHERE user_type = 'individual' AND sort_order = 16
    AND coalesce(is_trial_plan, false) = false
);

UPDATE public.subscription_plans
SET is_active = true,
    name_ar = N'رصيد نشر طلب واحد',
    name_en = 'One Property Request Credit',
    price_monthly = 3,
    price_yearly = 3,
    max_members = 0,
    max_ads_per_month = 0,
    max_listing_requests = 1,
    max_market_offers = 0,
    auto_pay_discount_percent = 0,
    plan_program = 'lifetime_one_time'
WHERE user_type = 'individual'
  AND sort_order = 23
  AND coalesce(is_trial_plan, false) = false;

INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type, price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT N'رصيد نشر طلب واحد', 'One Property Request Credit', 'individual', 3, 3,
  0, NULL, 0, 1, 0,
  false, false, false, false, 0, 0, 0, 0,
  23, true, false, 'lifetime_one_time'
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans
  WHERE user_type = 'individual' AND sort_order = 23
    AND coalesce(is_trial_plan, false) = false
);

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
    SELECT sort_order, lower(trim(user_type)), lower(trim(plan_program))
      INTO v_target_sort, v_target_audience, v_target_program
    FROM public.subscription_plans
    WHERE id = p_target_plan_id;
    v_target_is_topup := coalesce(
      v_target_sort IN (11, 12, 13, 16, 21, 22, 23), false
    );
    v_standalone_once := v_target_audience = 'individual'
      AND v_target_sort IN (16, 23)
      AND v_target_program = 'lifetime_one_time';
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
  NEW.is_topup := coalesce(v_sort IN (11, 12, 13, 21, 22, 23), false)
    OR (v_type = 'individual' AND v_sort = 16
        AND v_program = 'lifetime_one_time');
  RETURN NEW;
END;
$$;

UPDATE public.user_subscriptions s
SET is_topup = coalesce(p.sort_order IN (11, 12, 13, 21, 22, 23), false)
  OR (lower(trim(p.user_type)) = 'individual'
      AND p.sort_order = 16
      AND lower(trim(p.plan_program)) = 'lifetime_one_time')
FROM public.subscription_plans p
WHERE p.id = s.plan_id
  AND s.is_topup IS DISTINCT FROM (
    coalesce(p.sort_order IN (11, 12, 13, 21, 22, 23), false)
    OR (lower(trim(p.user_type)) = 'individual'
        AND p.sort_order = 16
        AND lower(trim(p.plan_program)) = 'lifetime_one_time')
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
      (p.user_type IN ('marketer', 'office', 'institution', 'company', 'agency')
       AND p.sort_order IN (11, 12, 13))
      OR (p.user_type = 'individual'
          AND p.sort_order IN (11, 12, 13, 16))
    )
    AND (
      coalesce(s.is_lifetime, false)
      OR coalesce(p.plan_program, '') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC;
$$;

COMMIT;