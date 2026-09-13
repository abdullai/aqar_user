-- =============================================================================
-- 2026-09-13 — كوبون حسب نوع الحساب الحقيقي + قفل الاسترجاع + برومو في الفاتورة
-- =============================================================================

BEGIN;

ALTER TABLE public.subscription_promotions
  ADD COLUMN IF NOT EXISTS max_redemptions_per_user int;

-- مصدر واحد للنوع — لا fallback إلى individual
CREATE OR REPLACE FUNCTION public._promo_account_plan_type(p_account_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.subscription_map_account_audience(p_account_type);
$$;

DROP FUNCTION IF EXISTS public.quote_promo_code(text, numeric);

CREATE OR REPLACE FUNCTION public.quote_promo_code(
  p_code text,
  p_amount_sar numeric,
  p_plan_id uuid DEFAULT NULL,
  p_period text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text := public._promo_norm_code(p_code);
  p public.subscription_promotions%ROWTYPE;
  v_before numeric := greatest(0, round(coalesce(p_amount_sar, 0), 2));
  v_after numeric;
  v_used int;
  v_per_user int;
  v_type text;
  v_at text;
  v_period text := lower(trim(coalesce(p_period, '')));
BEGIN
  PERFORM public._promo_purge_stale_holds();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF v_code IS NULL OR char_length(v_code) < 2 OR char_length(v_code) > 64 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'code_required');
  END IF;
  SELECT * INTO p
  FROM public.subscription_promotions
  WHERE lower(code) = lower(v_code)
  LIMIT 1;
  IF NOT FOUND OR NOT coalesce(p.is_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;
  IF p.valid_from IS NOT NULL AND now() < p.valid_from THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_started');
  END IF;
  IF p.valid_to IS NOT NULL AND now() > p.valid_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;
  IF p.min_amount_sar IS NOT NULL AND v_before < p.min_amount_sar THEN
    RETURN jsonb_build_object('ok', false, 'error', 'below_minimum', 'min_amount_sar', p.min_amount_sar);
  END IF;
  IF p.applies_periods IS NOT NULL AND cardinality(p.applies_periods) > 0 THEN
    IF v_period = '' OR NOT (v_period = ANY (p.applies_periods)) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'wrong_period');
    END IF;
  END IF;
  IF p.applies_plan_ids IS NOT NULL AND cardinality(p.applies_plan_ids) > 0 THEN
    IF p_plan_id IS NULL OR NOT (p_plan_id = ANY (p.applies_plan_ids)) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'wrong_plan');
    END IF;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.subscription_promotion_redemptions r
    WHERE r.promotion_id = p.id
      AND r.user_id = v_uid
      AND r.billing_transaction_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_used');
  END IF;
  SELECT count(*)::int INTO v_used
  FROM public.subscription_promotion_redemptions
  WHERE promotion_id = p.id
    AND billing_transaction_id IS NOT NULL;
  IF p.max_redemptions IS NOT NULL AND v_used >= p.max_redemptions THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sold_out');
  END IF;
  SELECT count(*)::int INTO v_per_user
  FROM public.subscription_promotion_redemptions
  WHERE promotion_id = p.id
    AND user_id = v_uid
    AND billing_transaction_id IS NOT NULL;
  IF coalesce(p.max_redemptions_per_user, 1) > 0 AND v_per_user >= coalesce(p.max_redemptions_per_user, 1) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_used');
  END IF;

  SELECT coalesce(nullif(trim(up.account_type::text), ''), '') INTO v_at
  FROM public.users_profiles up WHERE up.user_id = v_uid;
  v_type := public.subscription_map_account_audience(v_at);
  IF v_type IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'account_type_unknown');
  END IF;
  IF p.applies_user_types IS NOT NULL AND cardinality(p.applies_user_types) > 0 THEN
    IF NOT (v_type = ANY (p.applies_user_types)) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'wrong_audience');
    END IF;
  END IF;

  v_after := v_before;
  IF p.kind = 'percent_off' THEN
    v_after := round(v_before * (1 - least(greatest(p.value, 0), 100) / 100.0), 2);
  ELSIF p.kind IN ('fixed_off', 'first_payment_bonus') THEN
    v_after := greatest(0, round(v_before - coalesce(p.value, 0), 2));
  ELSIF p.kind = 'trial_days' THEN
    v_after := v_before;
  END IF;
  IF v_after < 0 THEN
    v_after := 0;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'promotion_id', p.id,
    'code', p.code,
    'kind', p.kind,
    'value', p.value,
    'trial_days', p.trial_days,
    'title_ar', p.title_ar,
    'title_en', p.title_en,
    'amount_before', v_before,
    'amount_after', v_after
  );
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
    v_promo := public.quote_promo_code(p_promo_code, v_expected, p_plan_id, v_period);
    IF (v_promo->>'ok')::boolean IS DISTINCT FROM true THEN
      PERFORM public._billing_security_event(
        v_uid, 'coupon_rejected', p_plan_id, v_period, v_expected, v_promo
      );
      RETURN v_promo;
    END IF;
    v_expected := (v_promo->>'amount_after')::numeric(10,2);
  END IF;

  IF p_amount_sar IS NOT NULL THEN
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

DROP FUNCTION IF EXISTS public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text);

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

  v_intent := public.validate_payment_intent(
    p_plan_id,
    v_period,
    NULL,
    coalesce(p_with_auto_pay, false),
    p_upgrade_subscription_id,
    v_idem,
    p_promo_code
  );

  IF coalesce(v_intent->>'ok', '') IS DISTINCT FROM 'true' THEN
    RETURN v_intent;
  END IF;

  v_amt := coalesce((v_intent->>'expected_amount')::numeric(10,2), v_amt);
  IF v_amt IS NULL OR v_amt < 0.01 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_expected_amount', 'detail', v_intent);
  END IF;
  v_discount := greatest(0, round(v_subtotal - v_amt, 2));

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
      'intent', v_intent,
      'promo_code', public._promo_norm_code(p_promo_code)
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

-- العميل لا يغيّر أعمدة مالية/باقة بعد الإنشاء
CREATE OR REPLACE FUNCTION public.trg_billing_tx_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.invoice_number IS NULL THEN
      NEW.invoice_number := public._billing_next_invoice_number();
    END IF;
    IF NEW.subtotal_sar IS NULL THEN
      NEW.subtotal_sar := NEW.amount;
    END IF;
    NEW.gateway_transaction_id := nullif(trim(coalesce(NEW.gateway_transaction_id, '')), '');
    RETURN NEW;
  END IF;

  NEW.updated_at := timezone('utc', now());
  NEW.gateway_transaction_id := nullif(trim(coalesce(NEW.gateway_transaction_id, '')), '');

  IF NEW.amount IS DISTINCT FROM OLD.amount THEN
    RAISE EXCEPTION 'amount_immutable';
  END IF;
  IF NEW.currency IS DISTINCT FROM OLD.currency THEN
    RAISE EXCEPTION 'currency_immutable';
  END IF;
  IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
    RAISE EXCEPTION 'user_immutable';
  END IF;

  IF auth.uid() IS NOT NULL
     AND NOT public.is_platform_staff(auth.uid()) THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'status_server_only';
    END IF;
    IF NEW.fulfillment_applied_at IS DISTINCT FROM OLD.fulfillment_applied_at THEN
      RAISE EXCEPTION 'fulfillment_server_only';
    END IF;
    IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
      RAISE EXCEPTION 'plan_server_only';
    END IF;
    IF NEW.purpose IS DISTINCT FROM OLD.purpose THEN
      RAISE EXCEPTION 'purpose_server_only';
    END IF;
    IF NEW.paid_at IS DISTINCT FROM OLD.paid_at
       OR NEW.refunded_at IS DISTINCT FROM OLD.refunded_at THEN
      RAISE EXCEPTION 'billing_dates_server_only';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- الاسترجاع يُطبَّق بعد Moyasar فقط (service_role / Edge)
REVOKE ALL ON FUNCTION public.apply_instant_credit_refund(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_instant_credit_refund(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_instant_credit_refund(uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.quote_promo_code(text, numeric, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_promo_code(text, numeric, uuid, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.apply_promo_to_pending_billing(
  p_billing_id uuid,
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'ok', false,
    'error', 'promo_at_intent_only',
    'message_ar', 'أدخل كود الخصم قبل بدء الدفع. لا يمكن تغيير مبلغ فاتورة قائمة.',
    'message_en', 'Enter the promo code before starting payment. An existing invoice amount cannot be changed.'
  );
END;
$$;

COMMIT;
