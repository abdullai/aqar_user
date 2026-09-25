-- The live photographer catalog uses sort orders 31-33 and a sort-0 trial.
-- Keep these plans and trial separate from the user's primary account audience.
BEGIN;

UPDATE public.subscription_plans
SET is_trial_plan = true
WHERE lower(trim(user_type)) = 'photographer'
  AND sort_order = 0
  AND is_active = true;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(
  p_audience text
)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_audience
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    WHEN 'photographer' THEN ARRAY[31, 32, 33]
    ELSE ARRAY[]::int[]
  END;
$$;

CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans(
  p_account_type text DEFAULT NULL
)
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

  v_at := nullif(lower(trim(coalesce(p_account_type, ''))), '');
  IF v_at IS NULL THEN
    SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
      INTO v_at
    FROM public.users_profiles up
    WHERE up.user_id = v_uid;
  END IF;
  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'photographer' THEN 'photographer'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;

  v_allowed := public.subscription_allowed_sorts_for_audience(v_plan_type);
  IF coalesce(array_length(v_allowed, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'account_type', v_at,
      'plan_user_type', v_plan_type,
      'plans', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
    INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND lower(trim(sp.user_type)) = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans(text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.subscription_assert_plan_allowed(
  p_uid uuid,
  p_plan_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_audience text;
  v_plan public.subscription_plans%ROWTYPE;
  v_sorts int[];
BEGIN
  IF p_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_required');
  END IF;

  SELECT * INTO v_plan
  FROM public.subscription_plans
  WHERE id = p_plan_id;
  IF NOT FOUND OR coalesce(v_plan.is_active, false) = false THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_invalid');
  END IF;

  v_audience := public.subscription_audience_for_uid(p_uid);
  IF lower(trim(v_plan.user_type)) = 'photographer' THEN
    v_audience := 'photographer';
    IF NOT EXISTS (
      SELECT 1 FROM public.photographer_profiles
      WHERE user_id = p_uid AND status = 'verified'
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'photographer_profile_not_verified'
      );
    END IF;
  END IF;
  IF v_audience IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'account_type_unknown');
  END IF;

  v_sorts := public.subscription_allowed_sorts_for_audience(v_audience);
  IF coalesce(array_length(v_sorts, 1), 0) = 0
     OR lower(trim(v_plan.user_type)) IS DISTINCT FROM v_audience
     OR NOT (coalesce(v_plan.sort_order, -1) = ANY (v_sorts)) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'plan_account_mismatch',
      'audience', v_audience,
      'plan_user_type', v_plan.user_type,
      'sort_order', v_plan.sort_order
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'audience', v_audience,
    'plan_id', v_plan.id,
    'sort_order', v_plan.sort_order
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.user_has_active_photographer_subscription(
  p_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.user_id = p_user_id
      AND s.service_audience = 'photographer'
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.starts_at, now()) <= now()
      AND (
        coalesce(s.is_lifetime, false)
        OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
      )
      AND lower(trim(p.user_type)) = 'photographer'
  );
$$;

CREATE TABLE IF NOT EXISTS public.photographer_trial_subscriptions_used (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  used_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.photographer_trial_subscriptions_used ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.photographer_trial_already_used()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.photographer_trial_subscriptions_used
    WHERE user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.photographer_trial_already_used() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_trial_already_used() TO authenticated;

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
  v_ends_at timestamptz := now() + interval '3 days';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('photographer-trial:' || v_uid::text, 0)
  );

  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles
    WHERE user_id = v_uid AND status = 'verified'
  ) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'photographer_profile_not_verified'
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.photographer_trial_subscriptions_used
    WHERE user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
  END IF;

  IF public.user_has_active_photographer_subscription(v_uid) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'photographer_subscription_active'
    );
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
      'ok', false,
      'error', 'photographer_trial_plan_missing'
    );
  END IF;

  INSERT INTO public.photographer_trial_subscriptions_used(user_id)
  VALUES (v_uid);

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, starts_at, ends_at, auto_renew, is_trial
  ) VALUES (
    v_uid, NULL, v_plan_id, 'active', 'monthly',
    current_date, (now() + interval '3 days')::date,
    now(), v_ends_at, false, true
  )
  RETURNING id INTO v_subscription_id;

  UPDATE public.photographer_trial_subscriptions_used
  SET subscription_id = v_subscription_id
  WHERE user_id = v_uid;

  RETURN jsonb_build_object(
    'ok', true,
    'subscription_id', v_subscription_id,
    'plan_id', v_plan_id,
    'plan_type', 'photographer',
    'is_trial', true,
    'ends_at', v_ends_at,
    'days', 3
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
END;
$$;

REVOKE ALL ON FUNCTION public.activate_photographer_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_photographer_trial_subscription()
  TO authenticated;

COMMIT;-- Align photographer plan sort orders with the live catalog (31-33) and
-- activate its dedicated 3-day trial without consuming the primary-role trial.
BEGIN;

UPDATE public.subscription_plans
SET is_trial_plan = true
WHERE user_type = 'photographer'
  AND sort_order = 0
  AND is_active = true;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(
  p_audience text
)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_audience
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    WHEN 'photographer' THEN ARRAY[31, 32, 33]
    ELSE ARRAY[]::int[]
  END;
$$;

CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans(
  p_account_type text DEFAULT NULL
)
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

  v_at := nullif(lower(trim(coalesce(p_account_type, ''))), '');
  IF v_at IS NULL THEN
    SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
      INTO v_at
    FROM public.users_profiles up
    WHERE up.user_id = v_uid;
  END IF;
  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'photographer' THEN 'photographer'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;

  v_allowed := public.subscription_allowed_sorts_for_audience(v_plan_type);
  IF coalesce(array_length(v_allowed, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'account_type', v_at,
      'plan_user_type', v_plan_type,
      'plans', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
    INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND lower(trim(sp.user_type)) = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans(text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.subscription_assert_plan_allowed(
  p_uid uuid,
  p_plan_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_audience text;
  v_plan public.subscription_plans%ROWTYPE;
  v_sorts int[];
BEGIN
  IF p_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_required');
  END IF;

  SELECT * INTO v_plan
  FROM public.subscription_plans
  WHERE id = p_plan_id;
  IF NOT FOUND OR coalesce(v_plan.is_active, false) = false THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_invalid');
  END IF;

  v_audience := public.subscription_audience_for_uid(p_uid);
  IF lower(trim(v_plan.user_type)) = 'photographer' THEN
    v_audience := 'photographer';
    IF NOT EXISTS (
      SELECT 1 FROM public.photographer_profiles
      WHERE user_id = p_uid AND status = 'verified'
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'photographer_profile_not_verified'
      );
    END IF;
  END IF;
  IF v_audience IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'account_type_unknown');
  END IF;

  v_sorts := public.subscription_allowed_sorts_for_audience(v_audience);
  IF coalesce(array_length(v_sorts, 1), 0) = 0
     OR lower(trim(v_plan.user_type)) IS DISTINCT FROM v_audience
     OR NOT (coalesce(v_plan.sort_order, -1) = ANY (v_sorts)) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'plan_account_mismatch',
      'audience', v_audience,
      'plan_user_type', v_plan.user_type,
      'sort_order', v_plan.sort_order
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'audience', v_audience,
    'plan_id', v_plan.id,
    'sort_order', v_plan.sort_order
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.user_has_active_photographer_subscription(
  p_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.user_id = p_user_id
      AND s.service_audience = 'photographer'
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.starts_at, now()) <= now()
      AND (
        coalesce(s.is_lifetime, false)
        OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
      )
      AND lower(trim(p.user_type)) = 'photographer'
  );
$$;

CREATE TABLE IF NOT EXISTS public.photographer_trial_subscriptions_used (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  used_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.photographer_trial_subscriptions_used ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.photographer_trial_already_used()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.photographer_trial_subscriptions_used
    WHERE user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.photographer_trial_already_used() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_trial_already_used() TO authenticated;

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
  v_ends_at timestamptz := now() + interval '3 days';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('photographer-trial:' || v_uid::text, 0));

  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles
    WHERE user_id = v_uid AND status = 'verified'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'photographer_profile_not_verified');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.photographer_trial_subscriptions_used
    WHERE user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
  END IF;

  IF public.user_has_active_photographer_subscription(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'photographer_subscription_active');
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
    RETURN jsonb_build_object('ok', false, 'error', 'photographer_trial_plan_missing');
  END IF;

  INSERT INTO public.photographer_trial_subscriptions_used(user_id)
  VALUES (v_uid);

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, starts_at, ends_at, auto_renew, is_trial
  ) VALUES (
    v_uid, NULL, v_plan_id, 'active', 'monthly',
    current_date, (now() + interval '3 days')::date,
    now(), v_ends_at, false, true
  )
  RETURNING id INTO v_subscription_id;

  UPDATE public.photographer_trial_subscriptions_used
  SET subscription_id = v_subscription_id
  WHERE user_id = v_uid;

  RETURN jsonb_build_object(
    'ok', true,
    'subscription_id', v_subscription_id,
    'plan_id', v_plan_id,
    'plan_type', 'photographer',
    'is_trial', true,
    'ends_at', v_ends_at,
    'days', 3
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
END;
$$;

REVOKE ALL ON FUNCTION public.activate_photographer_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_photographer_trial_subscription()
  TO authenticated;

COMMIT;