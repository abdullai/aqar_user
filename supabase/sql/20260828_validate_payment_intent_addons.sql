-- السماح بشراء إضافات (توب-أب عروض/طلبات) رغم وجود اشتراك رئيسي فعّال.
-- validate_payment_intent كان يستدعي subscription_can_subscribe بدون تمييز الإضافة
-- عندما تكون نسخة RPC قديمة أو عندما يُفتح الدفع من زر «اشترك» بدل الترقية.

BEGIN;

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
  v_sort int := 0;
  v_addon boolean := false;
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

  SELECT coalesce(sort_order, 0) INTO v_sort
    FROM public.subscription_plans
   WHERE id = p_plan_id;
  v_addon := coalesce(v_sort IN (11, 12, 13, 21, 22, 23), false);

  IF p_upgrade_subscription_id IS NULL THEN
    v_can := public.subscription_can_subscribe(p_plan_id);
    IF (v_can->>'can_subscribe')::boolean = false THEN
      IF v_addon AND coalesce(v_can->>'reason','') IN (
           'already_active_subscription', 'upgrade_only'
         ) THEN
        NULL;
      ELSE
        INSERT INTO public.payment_security_audit
          (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
        VALUES
          (v_uid, 'subscribe_denied', p_plan_id, p_period, p_amount_sar, NULL,
           jsonb_build_object('reason', v_can));
        RETURN jsonb_build_object(
          'ok', false,
          'error', coalesce(v_can->>'reason', 'not_allowed'),
          'detail', v_can
        );
      END IF;
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
                        'idem', p_idempotency_key,
                        'addon', v_addon));

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', p_plan_id,
    'period', p_period,
    'with_auto_pay', coalesce(p_with_auto_pay, false),
    'expected_amount', v_expected,
    'submitted_amount', p_amount_sar,
    'breakdown', v_charge,
    'rate', v_rate,
    'addon', v_addon
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_payment_intent(
  uuid, text, numeric, boolean, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_intent(
  uuid, text, numeric, boolean, uuid, text) TO authenticated, service_role;

COMMIT;
