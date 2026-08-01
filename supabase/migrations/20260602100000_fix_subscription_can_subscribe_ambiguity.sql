-- =============================================================================
-- 2026-06-02 — إصلاح تعارض subscription_can_subscribe()
-- =============================================================================
-- المشكلة: وجود نسختين بدون معامل (v5 plpgsql + v7 sql wrapper) →
--   ERROR 42725: function is not unique
-- الحل: دالة واحدة فقط: subscription_can_subscribe(p_target_plan_id uuid DEFAULT NULL)
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.subscription_can_subscribe();
DROP FUNCTION IF EXISTS public.subscription_can_subscribe(uuid);

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
  v_target_is_topup boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_target_plan_id IS NOT NULL THEN
    SELECT sort_order INTO v_target_sort
      FROM public.subscription_plans
     WHERE id = p_target_plan_id;
    v_target_is_topup := coalesce(v_target_sort IN (11, 12, 13, 21, 22, 23), false);
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
     AND coalesce(v_member_role,'') <> 'owner' THEN
    v_is_team_member := true;
  END IF;

  IF v_is_team_member THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner
        AND coalesce(s.is_trial, false) = false
        AND coalesce(s.is_topup, false) = false
        AND s.status IN ('active','cancelled')
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
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
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

REVOKE ALL ON FUNCTION public.subscription_can_subscribe(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_can_subscribe(uuid)
  TO authenticated, service_role;

-- محاذاة validate_payment_intent ليُمرّر plan_id (يسمح بتوب-أب مع رئيسية)
CREATE OR REPLACE FUNCTION public.validate_payment_intent(
  p_plan_id uuid,
  p_period text,
  p_amount_sar numeric,
  p_with_auto_pay boolean DEFAULT false,
  p_upgrade_subscription_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_can jsonb;
  v_charge jsonb;
  v_expected numeric(10,2);
  v_diff numeric(10,2);
  v_rate jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  v_rate := public._payment_rate_limit_check(v_uid, 'subscribe', 10, 10);
  IF (v_rate->>'allowed')::boolean = false THEN
    INSERT INTO public.payment_security_audit
      (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
    VALUES
      (v_uid, 'rate_limited', p_plan_id, p_period, p_amount_sar, NULL,
       jsonb_build_object('rate', v_rate, 'idem', p_idempotency_key));
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited',
                              'retry_after_minutes', 10);
  END IF;

  IF p_upgrade_subscription_id IS NULL THEN
    v_can := public.subscription_can_subscribe(p_plan_id);
    IF (v_can->>'can_subscribe')::boolean = false THEN
      INSERT INTO public.payment_security_audit
        (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
      VALUES
        (v_uid, 'subscribe_denied', p_plan_id, p_period, p_amount_sar, NULL,
         jsonb_build_object('reason', v_can));
      RETURN jsonb_build_object('ok', false, 'error',
                                coalesce(v_can->>'reason', 'not_allowed'),
                                'detail', v_can);
    END IF;
  END IF;

  v_charge := public.compute_canonical_charge(
    p_plan_id, p_period, p_with_auto_pay, p_upgrade_subscription_id
  );
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'error',
                              coalesce(v_charge->>'error','plan_invalid'),
                              'detail', v_charge);
  END IF;
  v_expected := (v_charge->>'final_amount')::numeric(10,2);

  v_diff := abs(round(coalesce(p_amount_sar,0) - v_expected, 2));
  IF v_diff > 0.05 THEN
    INSERT INTO public.payment_security_audit
      (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
    VALUES
      (v_uid, 'amount_mismatch', p_plan_id, p_period, p_amount_sar, v_expected,
       jsonb_build_object('charge_breakdown', v_charge,
                          'idem', p_idempotency_key));
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'amount_mismatch',
      'submitted', p_amount_sar,
      'expected', v_expected,
      'breakdown', v_charge
    );
  END IF;

  INSERT INTO public.payment_security_audit
    (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
  VALUES
    (v_uid, 'subscribe_intent', p_plan_id, p_period, p_amount_sar, v_expected,
     jsonb_build_object('charge_breakdown', v_charge,
                        'idem', p_idempotency_key));

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', p_plan_id,
    'period', p_period,
    'with_auto_pay', coalesce(p_with_auto_pay, false),
    'expected_amount', v_expected,
    'submitted_amount', p_amount_sar,
    'breakdown', v_charge,
    'rate', v_rate
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_payment_intent(
  uuid, text, numeric, boolean, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_intent(
  uuid, text, numeric, boolean, uuid, text) TO authenticated, service_role;

COMMIT;
