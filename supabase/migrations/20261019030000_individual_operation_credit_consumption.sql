-- Consume individual one-time deal/request credits exactly once.
-- Apply after 20261019020000_individual_one_time_operation_credits.sql.

BEGIN;

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
DROP POLICY IF EXISTS market_request_subscription_usage_select_own
  ON public.market_request_subscription_usage;
CREATE POLICY market_request_subscription_usage_select_own
  ON public.market_request_subscription_usage
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());
REVOKE ALL ON public.market_request_subscription_usage
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.market_request_subscription_usage TO authenticated;

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
       AND p.sort_order IN (21, 22, 23))
      OR (p.user_type = 'individual' AND p.sort_order = 23
          AND coalesce(p.plan_program, '') = 'lifetime_one_time')
    )
    AND (
      coalesce(s.is_lifetime, false)
      OR coalesce(p.plan_program, '') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public._listing_requests_topup_plans_for_uid(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._listing_requests_topup_plans_for_uid(uuid)
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
  v_marketing boolean := false;
  v_main record;
  v_topup record;
  v_main_max int := 0;
  v_main_used int := 0;
  v_main_start date;
  v_main_end date;
  v_main_lifetime boolean := false;
  v_unlimited boolean := false;
  v_topup_max int := 0;
  v_topup_used int := 0;
  v_topups jsonb := '[]'::jsonb;
  v_total_max int := 0;
  v_total_used int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT coalesce(nullif(lower(trim(account_type::text)), ''), 'user')
    INTO v_at
  FROM public.users_profiles WHERE user_id = v_uid;
  v_marketing := v_at IN ('marketer', 'office', 'institution', 'company', 'agency');
  v_bill_uid := v_uid;

  IF v_marketing THEN
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
    SELECT * INTO v_main FROM public._marketing_active_plan_for_uid(v_bill_uid);
  ELSE
    SELECT * INTO v_main FROM public._individual_main_plan_for_uid(v_uid);
  END IF;

  IF v_main.plan_id IS NOT NULL THEN
    v_unlimited := v_main.max_count IS NULL;
    v_main_max := CASE WHEN v_unlimited THEN 999999
      ELSE coalesce(v_main.max_count, 0) END;
    v_main_lifetime := coalesce(v_main.plan_program, '') = 'lifetime_one_time';
    SELECT period_start, period_end INTO v_main_start, v_main_end
    FROM public._offer_quota_period_bounds(v_main.starts_at, v_main.plan_program);
    IF NOT v_unlimited THEN
      v_main_used := public._count_offer_usage_for_user(
        v_bill_uid, v_main.subscription_id, v_main_start, v_main_lifetime
      );
    END IF;
  END IF;

  FOR v_topup IN
    SELECT t.*
    FROM public._market_offer_topup_plans_for_uid(v_uid) t
    JOIN public.subscription_plans p ON p.id = t.plan_id
    WHERE v_main.plan_id IS NOT NULL
       OR (NOT v_marketing AND t.plan_program = 'lifetime_one_time'
           AND p.sort_order IN (13, 16))
  LOOP
    DECLARE
      v_start date;
      v_end date;
      v_used int;
      v_life boolean := v_topup.plan_program = 'lifetime_one_time';
    BEGIN
      SELECT period_start, period_end INTO v_start, v_end
      FROM public._offer_quota_period_bounds(v_topup.starts_at, v_topup.plan_program);
      v_used := public._count_offer_usage_for_user(
        v_uid, v_topup.subscription_id, v_start, v_life
      );
      v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
      v_topup_used := v_topup_used + coalesce(v_used, 0);
      v_topups := v_topups || jsonb_build_array(jsonb_build_object(
        'subscription_id', v_topup.subscription_id,
        'plan_id', v_topup.plan_id,
        'plan_program', v_topup.plan_program,
        'max', v_topup.max_count,
        'used', v_used,
        'remaining', greatest(0, v_topup.max_count - v_used),
        'starts_at', v_topup.starts_at,
        'ends_at', v_topup.ends_at
      ));
    END;
  END LOOP;

  v_total_max := CASE WHEN v_unlimited THEN 999999
    ELSE v_main_max + v_topup_max END;
  v_total_used := v_main_used + v_topup_used;

  RETURN jsonb_build_object(
    'ok', true,
    'authenticated', true,
    'audience', CASE WHEN v_marketing THEN 'marketing' ELSE 'individual' END,
    'has_subscription', v_main.plan_id IS NOT NULL OR v_topup_max > 0,
    'has_main_plan', v_main.plan_id IS NOT NULL,
    'main', CASE WHEN v_main.plan_id IS NULL THEN NULL ELSE jsonb_build_object(
      'subscription_id', v_main.subscription_id,
      'plan_id', v_main.plan_id,
      'plan_program', v_main.plan_program,
      'is_trial', v_main.is_trial,
      'unlimited', v_unlimited,
      'max', CASE WHEN v_unlimited THEN NULL ELSE v_main_max END,
      'used', v_main_used,
      'remaining', CASE WHEN v_unlimited THEN NULL
        ELSE greatest(0, v_main_max - v_main_used) END,
      'period_start', v_main_start,
      'period_end', v_main_end,
      'starts_at', v_main.starts_at,
      'ends_at', v_main.ends_at
    ) END,
    'topups', v_topups,
    'total_used', v_total_used,
    'total_max', CASE WHEN v_unlimited THEN NULL ELSE v_total_max END,
    'total_remaining', CASE WHEN v_unlimited THEN NULL
      ELSE greatest(0, v_total_max - v_total_used) END,
    'unlimited', v_unlimited,
    'needs_paywall', NOT v_unlimited AND v_total_used >= v_total_max,
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
  v_marketing boolean := false;
  v_main record;
  v_plan record;
  v_start date;
  v_end date;
  v_used int := 0;
  v_max int := 0;
  v_lifetime boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_request');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));

  SELECT coalesce(nullif(lower(trim(account_type::text)), ''), 'user')
    INTO v_at FROM public.users_profiles WHERE user_id = v_uid;
  v_marketing := v_at IN ('marketer', 'office', 'institution', 'company', 'agency');

  IF v_marketing THEN
    SELECT * INTO v_main FROM public._marketing_active_plan_for_uid(v_uid);
  ELSE
    SELECT * INTO v_main FROM public._individual_main_plan_for_uid(v_uid);
  END IF;

  IF v_main.plan_id IS NOT NULL THEN
    SELECT period_start, period_end INTO v_start, v_end
    FROM public._offer_quota_period_bounds(v_main.starts_at, v_main.plan_program);
    v_lifetime := v_main.plan_program = 'lifetime_one_time';
    v_max := coalesce(v_main.max_count, 999999);
    v_used := public._count_offer_usage_for_user(
      v_uid, v_main.subscription_id, v_start, v_lifetime
    );
    IF v_used < v_max THEN
      v_plan := v_main;
    END IF;
  END IF;

  IF v_plan.plan_id IS NULL THEN
    FOR v_plan IN
      SELECT t.*
      FROM public._market_offer_topup_plans_for_uid(v_uid) t
      JOIN public.subscription_plans p ON p.id = t.plan_id
      WHERE (v_main.plan_id IS NOT NULL)
         OR (NOT v_marketing AND t.plan_program = 'lifetime_one_time'
             AND p.sort_order IN (13, 16))
    LOOP
      SELECT period_start, period_end INTO v_start, v_end
      FROM public._offer_quota_period_bounds(v_plan.starts_at, v_plan.plan_program);
      v_lifetime := v_plan.plan_program = 'lifetime_one_time';
      v_max := coalesce(v_plan.max_count, 0);
      v_used := public._count_offer_usage_for_user(
        v_uid, v_plan.subscription_id, v_start, v_lifetime
      );
      EXIT WHEN v_used < v_max;
    END LOOP;
  END IF;

  IF v_plan.plan_id IS NULL OR v_used >= v_max THEN
    RETURN jsonb_build_object('ok', false,
      'error', CASE WHEN v_main.plan_id IS NULL AND v_plan.plan_id IS NULL
        THEN 'main_subscription_or_one_time_credit_required'
        ELSE 'quota_exhausted' END,
      'used', v_used, 'max', v_max, 'remaining', 0);
  END IF;

  INSERT INTO public.market_request_offer_usage_events (
    user_id, market_request_id, subscription_id, plan_program, period_start
  ) VALUES (
    v_uid, p_request_id, v_plan.subscription_id,
    coalesce(v_plan.plan_program, 'monthly'), v_start
  );
  INSERT INTO public.market_request_offer_quotas (
    user_id, subscription_id, plan_program, period_start, period_end,
    used_count, max_count
  ) VALUES (
    v_uid, v_plan.subscription_id, coalesce(v_plan.plan_program, 'monthly'),
    v_start, v_end, 1, v_max
  ) ON CONFLICT (user_id, subscription_id, period_start)
  DO UPDATE SET used_count = market_request_offer_quotas.used_count + 1,
                updated_at = now();

  v_used := public._count_offer_usage_for_user(
    v_uid, v_plan.subscription_id, v_start, v_lifetime
  );
  RETURN jsonb_build_object('ok', true, 'used', v_used, 'max', v_max,
    'remaining', greatest(0, v_max - v_used),
    'audience', CASE WHEN v_marketing THEN 'marketing' ELSE 'individual' END,
    'subscription_id', v_plan.subscription_id);
END;
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
    AND (
      (p.user_type IN ('marketer', 'office', 'institution', 'company', 'agency')
       AND p.sort_order IN (21, 22, 23))
      OR (p.user_type = 'individual' AND p.sort_order = 23
          AND coalesce(p.plan_program, '') = 'lifetime_one_time')
    )
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(p.plan_program, '') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
  ORDER BY s.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public._listing_requests_topup_plans_for_uid(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._listing_requests_topup_plans_for_uid(uuid)
  TO authenticated, service_role;

CREATE INDEX IF NOT EXISTS idx_market_property_requests_quota_subscription
  ON public.market_property_requests (request_quota_subscription_id)
  WHERE request_quota_subscription_id IS NOT NULL;

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
    INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;
  v_is_marketing := v_at IN
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
    AND (coalesce(s.is_lifetime, false)
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now())
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

    SELECT count(*) INTO v_main_used
    FROM public.market_property_requests r
    WHERE r.requester_id = v_bill_uid
      AND lower(coalesce(r.status, '')) = 'published'
      AND r.instant_credit_id IS NULL
      AND r.request_quota_subscription_id IS NULL
      AND (v_is_marketing OR coalesce(r.published_at, r.created_at)
        >= v_main_usage_start);
  END IF;

  FOR v_topup IN
    SELECT t.*
    FROM public._listing_requests_topup_plans_for_uid(v_uid) t
    JOIN public.subscription_plans p ON p.id = t.plan_id
    WHERE v_main.subscription_id IS NOT NULL
       OR (NOT v_is_marketing AND p.user_type = 'individual'
           AND p.sort_order = 23
           AND t.plan_program = 'lifetime_one_time')
  LOOP
    v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
    IF NOT v_is_marketing
       AND v_topup.plan_program = 'lifetime_one_time' THEN
      SELECT count(*) INTO v_topup_used
      FROM public.market_request_subscription_usage u
      WHERE u.subscription_id = v_topup.subscription_id
        AND u.single_use_credit;
    ELSE
      v_topup_used := 0;
    END IF;
    v_topup_records := v_topup_records || jsonb_build_array(
      jsonb_build_object(
        'subscription_id', v_topup.subscription_id,
        'plan_id', v_topup.plan_id,
        'plan_program', v_topup.plan_program,
        'max', v_topup.max_count,
        'used', v_topup_used,
        'remaining', greatest(0, v_topup.max_count - v_topup_used),
        'starts_at', v_topup.starts_at,
        'ends_at', v_topup.ends_at
      )
    );
    v_total_used := v_total_used + v_topup_used;
  END LOOP;

  v_total_used := v_total_used + v_main_used;
  v_total_max := CASE WHEN v_main_unlimited THEN 999999
    ELSE v_main_max + v_topup_max END;

  RETURN jsonb_build_object(
    'ok', true,
    'authenticated', true,
    'audience', CASE WHEN v_is_marketing THEN 'marketing' ELSE 'individual' END,
    'has_subscription', v_main.subscription_id IS NOT NULL OR v_topup_max > 0,
    'has_main_plan', v_main.subscription_id IS NOT NULL,
    'main', CASE WHEN v_main.subscription_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'subscription_id', v_main.subscription_id,
        'plan_id', v_main.plan_id,
        'is_trial', v_main.is_trial,
        'is_lifetime', v_main_is_lifetime,
        'unlimited', v_main_unlimited,
        'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
        'used', v_main_used,
        'remaining', CASE WHEN v_main_unlimited THEN NULL
          ELSE greatest(0, v_main_max - v_main_used) END,
        'starts_at', v_main.starts_at,
        'ends_at', v_main.ends_at
      ) END,
    'topups', v_topup_records,
    'total_used', v_total_used,
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

REVOKE ALL ON FUNCTION public.listing_requests_unified_allowance(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listing_requests_unified_allowance(uuid)
  TO authenticated, service_role;

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
  v_main_remaining int := 0;
  v_main_unlimited boolean := false;
  v_has_main boolean := false;
  v_credit_subscription_id uuid;
BEGIN
  IF lower(coalesce(NEW.status, '')) <> 'published' OR v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND lower(coalesce(OLD.status, '')) = 'published' THEN
    NEW.request_quota_subscription_id := OLD.request_quota_subscription_id;
    RETURN NEW;
  END IF;

  NEW.updated_at := timezone('utc', now());
  NEW.request_quota_subscription_id := NULL;
  IF NEW.requester_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'requester_not_authenticated_user';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_uid::text));

    IF coalesce(NEW.request_priority, 'standard') = 'immediate'
      AND NEW.instant_credit_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.market_request_instant_credits c
    WHERE c.id = NEW.instant_credit_id
      AND c.user_id = v_uid
      AND c.status = 'consumed'
      AND c.market_request_id = NEW.id
  ) THEN
    NEW.published_at := timezone('utc', now());
    NEW.updated_at := NEW.published_at;
    RETURN NEW;
  END IF;

  v_allowance := public.listing_requests_unified_allowance(NULL);
  v_remaining := coalesce((v_allowance->>'total_max')::int, 0)
    - coalesce((v_allowance->>'total_used')::int, 0);
  IF coalesce((v_allowance->>'ok')::boolean, false) IS DISTINCT FROM true
     OR coalesce((v_allowance->>'has_subscription')::boolean, false)
       IS DISTINCT FROM true
     OR (coalesce((v_allowance->>'unlimited')::boolean, false) IS DISTINCT FROM true
         AND v_remaining <= 0) THEN
    RAISE EXCEPTION 'subscription_required_to_publish_market_request';
  END IF;

  v_has_main := coalesce((v_allowance->>'has_main_plan')::boolean, false);
  v_main_unlimited := coalesce((v_allowance->'main'->>'unlimited')::boolean, false);
  v_main_remaining := coalesce((v_allowance->'main'->>'remaining')::int, 0);

  IF NOT v_has_main OR (NOT v_main_unlimited AND v_main_remaining <= 0) THEN
    SELECT s.id INTO v_credit_subscription_id
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.user_id = v_uid
      AND s.status IN ('active', 'cancelled')
      AND p.user_type = 'individual'
      AND p.sort_order = 23
      AND p.plan_program = 'lifetime_one_time'
      AND coalesce(p.max_listing_requests, 0) = 1
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
  IF TG_OP = 'UPDATE'
     AND lower(coalesce(OLD.status, '')) = 'published'
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
      AND p.user_type = 'individual'
      AND p.sort_order = 23
      AND p.plan_program = 'lifetime_one_time'
      AND coalesce(p.max_listing_requests, 0) = 1
      AND NOT EXISTS (
        SELECT 1 FROM public.market_request_subscription_usage u
        WHERE u.market_request_id = NEW.id
      );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_market_request_subscription_quota
  ON public.market_property_requests;
CREATE TRIGGER tr_market_request_subscription_quota
  BEFORE INSERT OR UPDATE ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_market_request_subscription_quota();

DROP TRIGGER IF EXISTS tr_market_request_subscription_usage
  ON public.market_property_requests;
CREATE TRIGGER tr_market_request_subscription_usage
  AFTER INSERT OR UPDATE ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.record_market_request_subscription_usage();

REVOKE ALL ON FUNCTION public.enforce_market_request_subscription_quota()
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_market_request_subscription_usage()
  FROM PUBLIC;

COMMIT;