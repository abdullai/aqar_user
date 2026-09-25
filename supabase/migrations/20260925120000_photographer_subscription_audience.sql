-- Photographer subscriptions are an opt-in service audience and may coexist
-- with the user's primary account plan. Prices remain owned by the live catalog.
BEGIN;

ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS service_audience text;

UPDATE public.user_subscriptions s
SET service_audience = coalesce(
  nullif(lower(trim(p.user_type)), ''),
  public.subscription_audience_for_uid(s.user_id),
  'individual'
)
FROM public.subscription_plans p
WHERE s.plan_id = p.id
  AND s.service_audience IS DISTINCT FROM coalesce(
    nullif(lower(trim(p.user_type)), ''),
    public.subscription_audience_for_uid(s.user_id),
    'individual'
  );

UPDATE public.user_subscriptions s
SET service_audience = coalesce(
  public.subscription_audience_for_uid(s.user_id),
  'individual'
)
WHERE s.service_audience IS NULL;

ALTER TABLE public.user_subscriptions
  ALTER COLUMN service_audience SET DEFAULT 'individual',
  ALTER COLUMN service_audience SET NOT NULL;

CREATE OR REPLACE FUNCTION public._set_user_subscription_service_audience()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_audience text;
BEGIN
  IF NEW.plan_id IS NOT NULL THEN
    SELECT nullif(lower(trim(user_type)), '')
      INTO v_audience
    FROM public.subscription_plans
    WHERE id = NEW.plan_id;
  END IF;

  NEW.service_audience := coalesce(
    v_audience,
    public.subscription_audience_for_uid(NEW.user_id),
    'individual'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_user_subs_set_service_audience
  ON public.user_subscriptions;
CREATE TRIGGER tr_user_subs_set_service_audience
  BEFORE INSERT OR UPDATE OF plan_id, user_id
  ON public.user_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public._set_user_subscription_service_audience();

DROP INDEX IF EXISTS public.user_subscriptions_one_active_paid_per_user;
DROP INDEX IF EXISTS public.user_subscriptions_one_main_paid_per_user;
CREATE UNIQUE INDEX user_subscriptions_one_main_paid_per_audience
  ON public.user_subscriptions (user_id, service_audience)
  WHERE status = 'active'
    AND coalesce(is_trial, false) = false
    AND coalesce(is_topup, false) = false;

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
  v_target_is_topup boolean := false;
  v_assert jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_target_plan_id IS NOT NULL THEN
    v_assert := public.subscription_assert_plan_allowed(v_uid, p_target_plan_id);
    IF (v_assert->>'ok')::boolean IS DISTINCT FROM true THEN
      RETURN jsonb_build_object(
        'ok', true,
        'can_subscribe', false,
        'reason', coalesce(v_assert->>'error', 'plan_account_mismatch'),
        'detail', v_assert
      );
    END IF;
    SELECT sort_order, lower(trim(user_type))
      INTO v_target_sort, v_target_audience
    FROM public.subscription_plans
    WHERE id = p_target_plan_id;
    v_target_is_topup := coalesce(
      v_target_sort IN (11, 12, 13, 21, 22, 23),
      false
    );
  ELSE
    v_target_audience := public.subscription_audience_for_uid(v_uid);
  END IF;

  SELECT m.member_role, o.owner_user_id
    INTO v_member_role, v_owner
  FROM public.org_memberships m
  JOIN public.org_units o ON o.id = m.org_id
  WHERE m.user_id = v_uid
    AND m.status = 'active'
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
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    ) INTO v_owner_active;

    RETURN jsonb_build_object(
      'ok', true,
      'can_subscribe', false,
      'reason', 'team_member_uses_owner_subscription',
      'owner_user_id', v_owner,
      'owner_has_active_subscription', v_owner_active
    );
  END IF;

  SELECT s.id, s.plan_id, s.period, s.starts_at, s.ends_at, s.status
    INTO v_self_active
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND coalesce(s.is_trial, false) = false
    AND coalesce(s.is_topup, false) = false
    AND s.status = 'active'
    AND (
      coalesce(s.is_lifetime, false) = true
      OR coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    )
    AND (v_target_audience IS NULL OR s.service_audience = v_target_audience)
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_target_is_topup THEN
    IF v_self_active.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok', true,
        'can_subscribe', false,
        'reason', 'topup_requires_main_subscription'
      );
    END IF;
    RETURN jsonb_build_object(
      'ok', true,
      'can_subscribe', true,
      'topup_purchase', true,
      'main_subscription_id', v_self_active.id
    );
  END IF;

  IF v_self_active.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'can_subscribe', false,
      'reason', 'already_active_subscription',
      'subscription_id', v_self_active.id,
      'plan_id', v_self_active.plan_id,
      'period', v_self_active.period,
      'starts_at', v_self_active.starts_at,
      'ends_at', v_self_active.ends_at,
      'upgrade_only', true
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'can_subscribe', true);
END;
$$;

COMMIT;