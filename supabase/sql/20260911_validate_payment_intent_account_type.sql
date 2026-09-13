-- =============================================================================
-- 2026-09-11 — كتالوج حسب الحساب الحقيقي + validate + إنشاء فاتورة كانونية
-- =============================================================================

BEGIN;

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

  -- تجاهل p_account_type القادم من العميل دائماً.
  SELECT coalesce(nullif(trim(up.account_type::text), ''), '')
    INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL OR v_at = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := public.subscription_map_account_audience(v_at);
  IF v_plan_type IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'account_type_unknown',
      'account_type', v_at,
      'plans', '[]'::jsonb
    );
  END IF;

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
    AND (
      coalesce(s.is_lifetime, false) = true
      OR coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    )
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

CREATE OR REPLACE FUNCTION public.validate_payment_intent(
  p_plan_id uuid,
  p_period text,
  p_amount_sar numeric,
  p_with_auto_pay boolean DEFAULT false,
  p_upgrade_subscription_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL,
  p_promo_code text DEFAULT NULL
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
  v_promo jsonb;
  v_hold jsonb;
  v_assert jsonb;
  v_period text := lower(trim(coalesce(p_period, 'monthly')));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF v_period IN ('lifetime_one_time') THEN
    v_period := 'one_time';
  END IF;

  v_assert := public.subscription_assert_plan_allowed(v_uid, p_plan_id);
  IF (v_assert->>'ok')::boolean IS DISTINCT FROM true THEN
    PERFORM public._billing_security_event(
      v_uid, 'plan_account_mismatch', p_plan_id, v_period, p_amount_sar, v_assert
    );
    RETURN jsonb_build_object(
      'ok', false,
      'error', coalesce(v_assert->>'error', 'plan_account_mismatch'),
      'detail', v_assert
    );
  END IF;

  v_rate := public._payment_rate_limit_check(v_uid, 'subscribe', 10, 10);
  IF (v_rate->>'allowed')::boolean = false THEN
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited', 'retry_after_minutes', 10);
  END IF;

  SELECT coalesce(sort_order, 0) INTO v_sort
    FROM public.subscription_plans WHERE id = p_plan_id;
  v_addon := coalesce(v_sort IN (11, 12, 13, 21, 22, 23), false);

  IF p_upgrade_subscription_id IS NULL THEN
    v_can := public.subscription_can_subscribe(p_plan_id);
    IF (v_can->>'can_subscribe')::boolean = false THEN
      IF v_addon AND coalesce(v_can->>'reason','') IN (
           'already_active_subscription', 'upgrade_only'
         ) THEN
        NULL;
      ELSE
        RETURN jsonb_build_object(
          'ok', false,
          'error', coalesce(v_can->>'reason', 'not_allowed'),
          'detail', v_can
        );
      END IF;
    END IF;
  END IF;

  v_charge := public.compute_canonical_charge(
    p_plan_id, v_period, p_with_auto_pay, p_upgrade_subscription_id
  );
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'error',
                              coalesce(v_charge->>'error','plan_invalid'),
                              'detail', v_charge);
  END IF;
  v_expected := (v_charge->>'final_amount')::numeric(10,2);

  IF public._promo_norm_code(p_promo_code) IS NOT NULL THEN
    v_promo := public.quote_promo_code(p_promo_code, v_expected);
    IF (v_promo->>'ok')::boolean IS DISTINCT FROM true THEN
      PERFORM public._billing_security_event(
        v_uid, 'coupon_rejected', p_plan_id, v_period, v_expected, v_promo
      );
      RETURN v_promo;
    END IF;
    v_expected := (v_promo->>'amount_after')::numeric(10,2);
  END IF;

  v_diff := abs(round(coalesce(p_amount_sar,0) - v_expected, 2));
  IF v_diff > 0.05 THEN
    PERFORM public._billing_security_event(
      v_uid, 'amount_mismatch', p_plan_id, v_period, p_amount_sar,
      jsonb_build_object('expected', v_expected, 'breakdown', v_charge)
    );
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'amount_mismatch',
      'submitted', p_amount_sar,
      'expected', v_expected,
      'breakdown', v_charge,
      'promo', v_promo
    );
  END IF;

  IF v_promo IS NOT NULL AND (v_promo->>'ok')::boolean IS TRUE THEN
    v_hold := public._promo_hold_for_user((v_promo->>'promotion_id')::uuid, v_uid);
    IF (v_hold->>'ok')::boolean IS DISTINCT FROM true THEN
      RETURN v_hold;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', p_plan_id,
    'period', v_period,
    'with_auto_pay', coalesce(p_with_auto_pay, false),
    'expected_amount', v_expected,
    'submitted_amount', p_amount_sar,
    'breakdown', v_charge,
    'promo', v_promo,
    'rate', v_rate,
    'addon', v_addon
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pending_billing_from_intent(
  p_plan_id uuid,
  p_period text,
  p_with_auto_pay boolean DEFAULT false,
  p_upgrade_subscription_id uuid DEFAULT NULL,
  p_subscription_id uuid DEFAULT NULL,
  p_payment_method text DEFAULT 'card',
  p_card_id uuid DEFAULT NULL,
  p_purpose text DEFAULT 'subscribe',
  p_title_ar text DEFAULT NULL,
  p_title_en text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_intent jsonb;
  v_charge jsonb;
  v_amt numeric(10,2);
  v_bid uuid;
  v_period text := lower(trim(coalesce(p_period, 'monthly')));
  v_purpose text := lower(trim(coalesce(p_purpose, 'subscribe_new')));
  v_idem text := nullif(trim(coalesce(p_idempotency_key, '')), '');
  v_exist public.billing_transactions%ROWTYPE;
  v_subtotal numeric(12,2);
  v_discount numeric(12,2) := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF v_period IN ('lifetime_one_time') THEN
    v_period := 'one_time';
  END IF;
  IF v_purpose IN ('subscribe', 'subscription_checkout') THEN
    v_purpose := 'subscribe_new';
  END IF;

  IF v_idem IS NOT NULL THEN
    SELECT * INTO v_exist
      FROM public.billing_transactions
     WHERE user_id = v_uid AND idempotency_key = v_idem
     ORDER BY created_at DESC
     LIMIT 1;
    IF FOUND AND v_exist.status IN ('pending', 'success') THEN
      RETURN jsonb_build_object(
        'ok', true,
        'transaction_id', v_exist.id,
        'amount', v_exist.amount,
        'expected_amount', v_exist.amount,
        'duplicate', true,
        'status', v_exist.status
      );
    END IF;
  END IF;

  v_charge := public.compute_canonical_charge(
    p_plan_id, v_period, coalesce(p_with_auto_pay, false), p_upgrade_subscription_id
  );
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'error',
      coalesce(v_charge->>'error', 'plan_invalid'), 'detail', v_charge);
  END IF;
  v_amt := (v_charge->>'final_amount')::numeric(10,2);
  v_subtotal := coalesce((v_charge->>'base_price')::numeric(12,2), v_amt);
  v_discount := greatest(0, round(v_subtotal - v_amt, 2));

  v_intent := public.validate_payment_intent(
    p_plan_id,
    v_period,
    v_amt,
    coalesce(p_with_auto_pay, false),
    p_upgrade_subscription_id,
    v_idem
  );

  IF coalesce(v_intent->>'ok', '') IS DISTINCT FROM 'true' THEN
    RETURN v_intent;
  END IF;

  v_amt := coalesce((v_intent->>'expected_amount')::numeric(10,2), v_amt);
  IF v_amt IS NULL OR v_amt < 0.01 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_expected_amount', 'detail', v_intent);
  END IF;

  INSERT INTO public.billing_transactions (
    user_id, subscription_id, amount, currency, status, payment_method, card_id,
    title_ar, title_en, gateway_response,
    purpose, plan_id, billing_period, idempotency_key,
    subtotal_sar, discount_sar, vat_sar, fees_sar, vat_included
  ) VALUES (
    v_uid,
    p_subscription_id,
    v_amt,
    'SAR',
    'pending',
    coalesce(nullif(trim(p_payment_method), ''), 'card'),
    p_card_id,
    p_title_ar,
    p_title_en,
    jsonb_build_object(
      'pending_gateway', 'moyasar',
      'purpose', v_purpose,
      'plan_id', p_plan_id,
      'period', v_period,
      'validated', true,
      'expected_amount', v_amt,
      'breakdown', v_charge,
      'intent', v_intent
    ),
    v_purpose,
    p_plan_id,
    v_period,
    v_idem,
    v_subtotal,
    v_discount,
    0,
    0,
    true
  )
  RETURNING id INTO v_bid;

  PERFORM public._billing_security_event(
    v_uid, 'payment_pending', p_plan_id, v_period, v_amt,
    jsonb_build_object('billing_transaction_id', v_bid, 'purpose', v_purpose)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'transaction_id', v_bid,
    'amount', v_amt,
    'expected_amount', v_amt,
    'currency', 'SAR',
    'purpose', v_purpose,
    'period', v_period,
    'intent', v_intent
  );
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_exist
    FROM public.billing_transactions
   WHERE user_id = v_uid AND idempotency_key = v_idem
   ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', true,
      'transaction_id', v_exist.id,
      'amount', v_exist.amount,
      'expected_amount', v_exist.amount,
      'duplicate', true,
      'status', v_exist.status
    );
  END IF;
  RAISE;
END;
$$;

-- ترقية: نفس نوع الباقة + sort أعلى فقط
CREATE OR REPLACE FUNCTION public.subscription_compute_upgrade_charge(
  p_target_plan_id uuid,
  p_target_period  text DEFAULT 'monthly'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cur record;
  v_old_plan record;
  v_new_plan record;
  v_full_old numeric(12,4);
  v_full_new numeric(12,4);
  v_total_days int;
  v_used_days int;
  v_remaining_days int;
  v_credit numeric(12,4);
  v_due numeric(12,4);
  v_assert jsonb;
  v_period text := lower(trim(coalesce(p_target_period, 'monthly')));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF v_period IN ('lifetime_one_time') THEN
    v_period := 'one_time';
  END IF;

  v_assert := public.subscription_assert_plan_allowed(v_uid, p_target_plan_id);
  IF (v_assert->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN v_assert;
  END IF;

  SELECT *
    INTO v_cur
  FROM public.user_subscriptions
  WHERE user_id = v_uid
    AND status = 'active'
    AND coalesce(is_trial, false) = false
    AND coalesce(is_topup, false) = false
    AND (
      coalesce(is_lifetime, false) = true
      OR coalesce(ends_at, end_date::timestamptz) > timezone('utc', now())
    )
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_cur.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_active_subscription');
  END IF;

  SELECT * INTO v_old_plan FROM public.subscription_plans WHERE id = v_cur.plan_id;
  SELECT * INTO v_new_plan FROM public.subscription_plans WHERE id = p_target_plan_id;

  IF v_old_plan.id IS NULL OR v_new_plan.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_found');
  END IF;

  IF lower(trim(coalesce(v_new_plan.user_type,''))) IS DISTINCT FROM lower(trim(coalesce(v_old_plan.user_type,''))) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_account_mismatch');
  END IF;

  IF v_new_plan.sort_order <= v_old_plan.sort_order THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_an_upgrade');
  END IF;

  v_full_old := CASE coalesce(v_cur.period, 'monthly')
                  WHEN 'yearly' THEN v_old_plan.price_yearly
                  ELSE v_old_plan.price_monthly END;
  v_full_new := CASE v_period
                  WHEN 'yearly' THEN v_new_plan.price_yearly
                  ELSE v_new_plan.price_monthly END;

  v_total_days := greatest(1, (coalesce(v_cur.end_date, current_date) - v_cur.start_date));
  v_used_days  := greatest(0, (current_date - v_cur.start_date));
  v_remaining_days := greatest(0, v_total_days - v_used_days);
  v_credit := round((v_full_old * v_remaining_days::numeric) / v_total_days::numeric, 2);
  v_due    := greatest(0, round(v_full_new - v_credit, 2));

  RETURN jsonb_build_object(
    'ok', true,
    'old_plan_id', v_old_plan.id,
    'new_plan_id', v_new_plan.id,
    'period', v_period,
    'full_old_price', v_full_old,
    'full_new_price', v_full_new,
    'total_days', v_total_days,
    'remaining_days', v_remaining_days,
    'credit_from_remaining', v_credit,
    'amount_due', v_due
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans(text)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.subscription_can_subscribe(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_can_subscribe(uuid)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text, text)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.subscription_compute_upgrade_charge(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_compute_upgrade_charge(uuid, text)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.subscription_assert_plan_allowed(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_assert_plan_allowed(uuid, uuid)
  TO authenticated, service_role;

COMMIT;
