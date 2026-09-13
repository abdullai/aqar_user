-- =============================================================================
-- 2026-09-11 — fulfill_paid_billing + إلغاء/انتهاء خادمي + RLS
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._normalize_billing_period(p_period text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_period, 'monthly')))
    WHEN 'lifetime_one_time' THEN 'one_time'
    WHEN 'one_time' THEN 'one_time'
    WHEN 'yearly' THEN 'yearly'
    ELSE 'monthly'
  END;
$$;

CREATE OR REPLACE FUNCTION public._billing_period_end(p_start timestamptz, p_period text)
RETURNS timestamptz
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text := public._normalize_billing_period(p_period);
BEGIN
  IF v = 'one_time' THEN
    RETURN NULL;
  END IF;
  IF v = 'yearly' THEN
    RETURN p_start + interval '1 year';
  END IF;
  RETURN p_start + interval '1 month';
END;
$$;

CREATE OR REPLACE FUNCTION public.fulfill_paid_billing(p_billing_transaction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  bt public.billing_transactions%ROWTYPE;
  v_purpose text;
  v_period text;
  v_plan public.subscription_plans%ROWTYPE;
  v_assert jsonb;
  v_sid uuid;
  v_start timestamptz;
  v_end timestamptz;
  v_is_topup boolean := false;
  v_is_life boolean := false;
  v_auto boolean := false;
  v_org uuid;
  v_inst jsonb;
  v_ext jsonb;
BEGIN
  IF p_billing_transaction_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_required');
  END IF;

  SELECT * INTO bt
    FROM public.billing_transactions
   WHERE id = p_billing_transaction_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;

  IF v_uid IS NOT NULL AND v_uid IS DISTINCT FROM bt.user_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  IF bt.fulfillment_applied_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'duplicate', true,
      'billing_transaction_id', bt.id,
      'subscription_id', bt.subscription_id
    );
  END IF;

  IF bt.status IS DISTINCT FROM 'success' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_success', 'status', bt.status);
  END IF;

  IF coalesce(bt.currency, 'SAR') <> 'SAR' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'currency_mismatch');
  END IF;

  v_purpose := lower(trim(coalesce(
    bt.purpose,
    bt.gateway_response->>'purpose',
    'subscribe_new'
  )));
  IF v_purpose IN ('subscribe', 'subscription_checkout') THEN
    v_purpose := 'subscribe_new';
  END IF;

  IF v_purpose IN ('save_card_only', 'save_card_verify') THEN
    UPDATE public.billing_transactions
       SET fulfillment_applied_at = timezone('utc', now()),
           paid_at = coalesce(paid_at, timezone('utc', now()))
     WHERE id = bt.id AND fulfillment_applied_at IS NULL;
    RETURN jsonb_build_object('ok', true, 'purpose', v_purpose, 'billing_transaction_id', bt.id);
  END IF;

  IF v_purpose IN ('instant_market_request') THEN
    v_inst := public.activate_instant_market_request_credit(bt.id);
    IF coalesce(v_inst->>'ok', '') IS DISTINCT FROM 'true' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'instant_activate_failed', 'detail', v_inst);
    END IF;
    INSERT INTO public.instant_credit_ledger (
      user_id, credit_id, billing_transaction_id, entry_type, units, amount_sar, note
    ) VALUES (
      bt.user_id,
      nullif(v_inst->>'credit_id', '')::uuid,
      bt.id,
      'credit',
      1,
      bt.amount,
      'instant_market_request'
    );
    UPDATE public.billing_transactions
       SET fulfillment_applied_at = timezone('utc', now()),
           paid_at = coalesce(paid_at, timezone('utc', now())),
           purpose = v_purpose
     WHERE id = bt.id AND fulfillment_applied_at IS NULL;
    RETURN jsonb_build_object(
      'ok', true,
      'purpose', v_purpose,
      'credit_id', v_inst->>'credit_id',
      'billing_transaction_id', bt.id
    );
  END IF;

  IF v_purpose = 'auto_renew' AND bt.subscription_id IS NOT NULL THEN
    v_ext := public.subscription_apply_auto_renew_extension(bt.subscription_id, bt.id);
    IF coalesce(v_ext->>'ok', '') IS DISTINCT FROM 'true' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'auto_renew_failed', 'detail', v_ext);
    END IF;
    UPDATE public.billing_transactions
       SET fulfillment_applied_at = timezone('utc', now()),
           paid_at = coalesce(paid_at, timezone('utc', now())),
           purpose = v_purpose
     WHERE id = bt.id AND fulfillment_applied_at IS NULL;
    PERFORM public._subscription_lifecycle_write(
      bt.user_id, 'subscription_renewed', bt.subscription_id, NULL,
      jsonb_build_object('billing_transaction_id', bt.id, 'auto_renew', true)
    );
    RETURN jsonb_build_object('ok', true, 'purpose', v_purpose, 'subscription_id', bt.subscription_id, 'detail', v_ext);
  END IF;

  IF bt.plan_id IS NULL THEN
    BEGIN
      bt.plan_id := nullif(bt.gateway_response->>'plan_id', '')::uuid;
    EXCEPTION WHEN OTHERS THEN
      bt.plan_id := NULL;
    END;
  END IF;

  IF bt.plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_required');
  END IF;

  v_assert := public.subscription_assert_plan_allowed(bt.user_id, bt.plan_id);
  IF (v_assert->>'ok')::boolean IS DISTINCT FROM true THEN
    PERFORM public._billing_security_event(
      bt.user_id, 'plan_account_mismatch', bt.plan_id, bt.billing_period, bt.amount, v_assert
    );
    RETURN jsonb_build_object('ok', false, 'error', 'plan_account_mismatch', 'detail', v_assert);
  END IF;

  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = bt.plan_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_invalid');
  END IF;

  v_period := public._normalize_billing_period(
    coalesce(bt.billing_period, bt.gateway_response->>'period', 'monthly')
  );
  IF coalesce(v_plan.plan_program, '') = 'lifetime_one_time' THEN
    v_period := 'one_time';
    v_is_life := true;
  END IF;
  v_is_topup := coalesce(v_plan.sort_order IN (11, 12, 13, 21, 22, 23), false);
  v_auto := (v_period = 'monthly') AND coalesce((bt.gateway_response->>'with_auto_pay')::boolean, false);

  IF v_purpose = 'upgrade' THEN
    UPDATE public.user_subscriptions
       SET plan_id = bt.plan_id,
           status = 'active',
           updated_at = timezone('utc', now())
     WHERE id = bt.subscription_id
       AND user_id = bt.user_id
       AND status = 'active'
    RETURNING id INTO v_sid;
    IF v_sid IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'upgrade_target_missing');
    END IF;
    UPDATE public.billing_transactions
       SET fulfillment_applied_at = timezone('utc', now()),
           paid_at = coalesce(paid_at, timezone('utc', now())),
           subscription_id = v_sid,
           purpose = v_purpose,
           plan_id = bt.plan_id
     WHERE id = bt.id AND fulfillment_applied_at IS NULL;
    PERFORM public._subscription_lifecycle_write(
      bt.user_id, 'subscription_upgraded', v_sid, NULL,
      jsonb_build_object('billing_transaction_id', bt.id, 'plan_id', bt.plan_id)
    );
    RETURN jsonb_build_object('ok', true, 'purpose', v_purpose, 'subscription_id', v_sid);
  END IF;

  IF v_purpose IN ('renew', 'period_switch') AND bt.subscription_id IS NOT NULL THEN
    v_start := timezone('utc', now());
    SELECT coalesce(ends_at, timezone('utc', now())) INTO v_start
      FROM public.user_subscriptions WHERE id = bt.subscription_id FOR UPDATE;
    IF v_start < timezone('utc', now()) THEN
      v_start := timezone('utc', now());
    END IF;
    IF v_purpose = 'period_switch' THEN
      v_period := 'yearly';
    END IF;
    v_end := public._billing_period_end(v_start, v_period);
    UPDATE public.user_subscriptions
       SET status = 'active',
           period = v_period,
           ends_at = v_end,
           end_date = CASE WHEN v_end IS NULL THEN NULL ELSE (v_end::date - 1) END,
           cancelled_at = NULL,
           auto_renew = CASE WHEN v_period = 'yearly' OR v_period = 'one_time' THEN false ELSE auto_renew END,
           updated_at = timezone('utc', now())
     WHERE id = bt.subscription_id AND user_id = bt.user_id
    RETURNING id INTO v_sid;
    IF v_sid IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'renew_target_missing');
    END IF;
    UPDATE public.billing_transactions
       SET fulfillment_applied_at = timezone('utc', now()),
           paid_at = coalesce(paid_at, timezone('utc', now())),
           purpose = v_purpose
     WHERE id = bt.id AND fulfillment_applied_at IS NULL;
    PERFORM public._subscription_lifecycle_write(
      bt.user_id,
      CASE WHEN v_purpose = 'period_switch' THEN 'period_switched' ELSE 'subscription_renewed' END,
      v_sid, NULL,
      jsonb_build_object('billing_transaction_id', bt.id)
    );
    RETURN jsonb_build_object('ok', true, 'purpose', v_purpose, 'subscription_id', v_sid);
  END IF;

  -- subscribe_new / topup / one_time
  v_start := timezone('utc', now());
  v_end := public._billing_period_end(v_start, v_period);
  SELECT o.id INTO v_org
    FROM public.org_units o
   WHERE o.owner_user_id = bt.user_id
   ORDER BY o.created_at DESC NULLS LAST
   LIMIT 1;

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, starts_at, ends_at,
    auto_renew, auto_pay_discount_applied, is_lifetime
  ) VALUES (
    bt.user_id,
    v_org,
    bt.plan_id,
    'active',
    v_period,
    v_start::date,
    CASE WHEN v_end IS NULL THEN NULL ELSE (v_end::date - 1) END,
    v_start,
    v_end,
    v_auto AND NOT v_is_life AND NOT v_is_topup,
    v_auto AND NOT v_is_life AND NOT v_is_topup,
    v_is_life
  )
  RETURNING id INTO v_sid;

  UPDATE public.billing_transactions
     SET fulfillment_applied_at = timezone('utc', now()),
         paid_at = coalesce(paid_at, timezone('utc', now())),
         subscription_id = v_sid,
         purpose = CASE WHEN v_is_topup THEN 'topup' WHEN v_is_life THEN 'one_time' ELSE v_purpose END,
         plan_id = bt.plan_id,
         billing_period = v_period
   WHERE id = bt.id AND fulfillment_applied_at IS NULL;

  PERFORM public._subscription_lifecycle_write(
    bt.user_id,
    CASE WHEN v_is_topup THEN 'topup_applied' ELSE 'subscription_activated' END,
    v_sid, v_org,
    jsonb_build_object('billing_transaction_id', bt.id, 'plan_id', bt.plan_id, 'period', v_period)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'purpose', v_purpose,
    'subscription_id', v_sid,
    'billing_transaction_id', bt.id,
    'period', v_period
  );
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok', false, 'error', 'already_active_subscription');
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_subscription(
  p_subscription_id uuid,
  p_churn_reason_key text DEFAULT NULL,
  p_churn_detail text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  s public.user_subscriptions%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO s
    FROM public.user_subscriptions
   WHERE id = p_subscription_id AND user_id = v_uid
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'subscription_not_found');
  END IF;

  IF s.status = 'cancelled' THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true, 'status', 'cancelled');
  END IF;

  IF s.status NOT IN ('active', 'pending') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_cancellable', 'status', s.status);
  END IF;

  UPDATE public.user_subscriptions
     SET status = 'cancelled',
         auto_renew = false,
         cancelled_at = timezone('utc', now()),
         updated_at = timezone('utc', now())
   WHERE id = s.id;

  PERFORM public._subscription_lifecycle_write(
    v_uid, 'subscription_cancel_finalized', s.id, s.organization_id,
    jsonb_build_object(
      'reason_key', coalesce(p_churn_reason_key, ''),
      'detail', coalesce(p_churn_detail, ''),
      'refund', false
    )
  );

  RETURN jsonb_build_object('ok', true, 'status', 'cancelled', 'refund', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.subscription_expire_due()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
BEGIN
  FOR r IN
    SELECT id, user_id, organization_id
      FROM public.user_subscriptions
     WHERE status = 'active'
       AND coalesce(is_lifetime, false) = false
       AND coalesce(ends_at, end_date::timestamptz) IS NOT NULL
       AND coalesce(ends_at, end_date::timestamptz) <= timezone('utc', now())
     FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.user_subscriptions
       SET status = 'expired',
           auto_renew = false,
           updated_at = timezone('utc', now())
     WHERE id = r.id AND status = 'active';
    PERFORM public._subscription_lifecycle_write(
      r.user_id, 'subscription_expired', r.id, r.organization_id, '{}'::jsonb
    );
    n := n + 1;
  END LOOP;

  UPDATE public.billing_transactions
     SET status = 'expired',
         failure_code = 'pending_expired',
         completed_at = coalesce(completed_at, timezone('utc', now()))
   WHERE status = 'pending'
     AND created_at < timezone('utc', now()) - interval '2 hours';

  RETURN jsonb_build_object('ok', true, 'expired_count', n);
END;
$$;

CREATE OR REPLACE FUNCTION public.subscription_my_entitlements()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_aud text;
  s record;
  p public.subscription_plans%ROWTYPE;
  v_active boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  v_aud := public.subscription_audience_for_uid(v_uid);

  SELECT * INTO s
    FROM public.user_subscriptions
   WHERE user_id = v_uid
     AND coalesce(is_topup, false) = false
     AND coalesce(is_trial, false) = false
     AND status = 'active'
     AND (
       coalesce(is_lifetime, false) = true
       OR coalesce(ends_at, end_date::timestamptz) > timezone('utc', now())
     )
   ORDER BY created_at DESC
   LIMIT 1;

  IF s.id IS NOT NULL THEN
    v_active := true;
    SELECT * INTO p FROM public.subscription_plans WHERE id = s.plan_id;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'audience', v_aud,
    'active', v_active,
    'subscription_id', s.id,
    'plan_id', s.plan_id,
    'status', s.status,
    'period', s.period,
    'starts_at', s.starts_at,
    'ends_at', s.ends_at,
    'is_lifetime', coalesce(s.is_lifetime, false),
    'can_add_listing', v_active,
    'can_add_market_request', v_active,
    'can_complete_market_deal', v_active,
    'can_use_marketing_workflow', v_active,
    'can_manage_team', v_active AND coalesce(p.max_members, 0) > 1,
    'can_topup', v_active,
    'can_auto_renew', v_active AND coalesce(s.period, '') = 'monthly',
    'max_members', p.max_members,
    'max_properties', p.max_properties,
    'max_ads_per_month', p.max_ads_per_month,
    'max_listing_requests', p.max_listing_requests,
    'has_analytics', coalesce(p.has_analytics, false),
    'has_api_access', coalesce(p.has_api_access, false),
    'has_priority_support', coalesce(p.has_priority_support, false)
  );
END;
$$;

-- استرجاع فوري: تجهيز فقط — لا تعلّم refunded قبل Moyasar
CREATE OR REPLACE FUNCTION public.prepare_instant_credit_refund(p_credit_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.market_request_instant_credits%ROWTYPE;
  bt public.billing_transactions%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO v_row
    FROM public.market_request_instant_credits
   WHERE id = p_credit_id AND user_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_found');
  END IF;
  IF v_row.status = 'consumed' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'partial_refund_unsupported');
  END IF;
  IF v_row.status <> 'available' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_refundable', 'status', v_row.status);
  END IF;

  SELECT * INTO bt FROM public.billing_transactions WHERE id = v_row.billing_transaction_id;
  IF NOT FOUND OR bt.status <> 'success' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_success');
  END IF;
  IF bt.gateway_transaction_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_gateway_id');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', v_row.id,
    'billing_transaction_id', bt.id,
    'gateway_transaction_id', bt.gateway_transaction_id,
    'amount_sar', v_row.amount_sar,
    'amount_halalas', round(v_row.amount_sar * 100)::int
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_instant_credit_refund(
  p_credit_id uuid,
  p_gateway_refund_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.market_request_instant_credits%ROWTYPE;
BEGIN
  SELECT * INTO v_row
    FROM public.market_request_instant_credits
   WHERE id = p_credit_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_found');
  END IF;
  IF v_uid IS NOT NULL AND v_uid IS DISTINCT FROM v_row.user_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF v_row.status = 'refunded' THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true);
  END IF;
  IF v_row.status <> 'available' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_refundable', 'status', v_row.status);
  END IF;

  UPDATE public.billing_transactions
     SET status = 'refunded',
         refunded_at = timezone('utc', now()),
         refund_amount = amount,
         gateway_response = coalesce(gateway_response, '{}'::jsonb)
           || jsonb_build_object('refunded_at', now(), 'gateway_refund_id', p_gateway_refund_id),
         completed_at = coalesce(completed_at, timezone('utc', now()))
   WHERE id = v_row.billing_transaction_id
     AND status = 'success';

  UPDATE public.market_request_instant_credits
     SET status = 'refunded',
         refunded_at = timezone('utc', now()),
         market_request_id = NULL
   WHERE id = p_credit_id AND status = 'available';

  INSERT INTO public.instant_credit_ledger (
    user_id, credit_id, billing_transaction_id, entry_type, units, amount_sar, note
  ) VALUES (
    v_row.user_id, v_row.id, v_row.billing_transaction_id, 'refunded', 1, v_row.amount_sar, p_gateway_refund_id
  );

  RETURN jsonb_build_object('ok', true, 'credit_id', p_credit_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_billing_gateway_outcome(
  p_billing_transaction_id uuid,
  p_status text,
  p_gateway_transaction_id text DEFAULT NULL,
  p_gateway_response jsonb DEFAULT NULL,
  p_failure_code text DEFAULT NULL,
  p_failure_reason text DEFAULT NULL,
  p_review_required boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bt public.billing_transactions%ROWTYPE;
  v_status text := lower(trim(coalesce(p_status, '')));
BEGIN
  SELECT * INTO bt FROM public.billing_transactions WHERE id = p_billing_transaction_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;

  IF v_status = 'success' AND bt.status = 'success'
     AND coalesce(bt.gateway_transaction_id, '') = coalesce(nullif(trim(p_gateway_transaction_id), ''), bt.gateway_transaction_id) THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true);
  END IF;

  IF v_status = 'success' AND bt.status NOT IN ('pending', 'authorized') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'illegal_status_transition', 'from', bt.status, 'to', v_status);
  END IF;

  IF v_status = 'success' AND bt.status IN ('failed', 'cancelled', 'expired', 'refunded') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'illegal_status_transition');
  END IF;

  UPDATE public.billing_transactions
     SET status = v_status,
         gateway_transaction_id = coalesce(nullif(trim(p_gateway_transaction_id), ''), gateway_transaction_id),
         gateway_response = coalesce(p_gateway_response, gateway_response),
         failure_code = p_failure_code,
         failure_reason = p_failure_reason,
         review_required = coalesce(p_review_required, false),
         paid_at = CASE WHEN v_status = 'success' THEN coalesce(paid_at, timezone('utc', now())) ELSE paid_at END,
         completed_at = CASE WHEN v_status IN ('success', 'failed', 'cancelled', 'expired', 'refunded')
           THEN coalesce(completed_at, timezone('utc', now())) ELSE completed_at END
   WHERE id = bt.id;

  RETURN jsonb_build_object('ok', true, 'status', v_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.activate_instant_market_request_credit(
  p_billing_transaction_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.market_request_instant_credits%ROWTYPE;
  v_bill public.billing_transactions%ROWTYPE;
BEGIN
  IF p_billing_transaction_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_required');
  END IF;

  SELECT * INTO v_bill FROM public.billing_transactions
   WHERE id = p_billing_transaction_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;
  IF v_bill.status <> 'success' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_success', 'status', v_bill.status);
  END IF;

  SELECT * INTO v_row FROM public.market_request_instant_credits
   WHERE billing_transaction_id = p_billing_transaction_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_found');
  END IF;

  IF abs(v_bill.amount - v_row.amount_sar) > 0.05 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'amount_mismatch');
  END IF;

  IF v_row.status = 'available' THEN
    RETURN jsonb_build_object('ok', true, 'credit_id', v_row.id, 'already_active', true);
  END IF;
  IF v_row.status = 'consumed' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_consumed');
  END IF;
  IF v_row.status = 'refunded' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_refunded');
  END IF;

  UPDATE public.market_request_instant_credits
     SET status = 'available',
         activated_at = coalesce(activated_at, now())
   WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', v_row.id,
    'billing_transaction_id', p_billing_transaction_id,
    'amount_sar', v_row.amount_sar
  );
END;
$$;

-- استبدال مسار الاسترجاع القديم الذي يعلّم DB قبل Moyasar
CREATE OR REPLACE FUNCTION public.refund_unused_instant_market_request_credit(
  p_credit_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'ok', false,
    'error', 'use_moyasar_refund',
    'message_ar', 'الاسترجاع يتم عبر بوابة الدفع بعد التحقق.',
    'message_en', 'Refunds must go through the payment gateway after verification.'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- RLS: إغلاق الكتابة من العميل
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS user_subscriptions_insert_own ON public.user_subscriptions;
DROP POLICY IF EXISTS user_subscriptions_update_own ON public.user_subscriptions;
DROP POLICY IF EXISTS billing_transactions_update_own ON public.billing_transactions;
DROP POLICY IF EXISTS billing_transactions_insert_own ON public.billing_transactions;
DROP POLICY IF EXISTS subscription_lifecycle_events_insert_own ON public.subscription_lifecycle_events;
DROP POLICY IF EXISTS subscription_promotion_redemptions_insert_own ON public.subscription_promotion_redemptions;

DROP POLICY IF EXISTS saved_cards_all_own ON public.saved_cards;
DROP POLICY IF EXISTS saved_cards_select_own ON public.saved_cards;
DROP POLICY IF EXISTS saved_cards_update_own ON public.saved_cards;
DROP POLICY IF EXISTS saved_cards_delete_own ON public.saved_cards;
DROP POLICY IF EXISTS saved_cards_insert_own ON public.saved_cards;

CREATE POLICY saved_cards_select_own ON public.saved_cards
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY saved_cards_update_own ON public.saved_cards
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY saved_cards_delete_own ON public.saved_cards
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- لا INSERT للعميل — التوكن من webhook/Edge فقط.

CREATE OR REPLACE FUNCTION public.trg_saved_cards_client_update_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_platform_staff(auth.uid()) THEN
    IF NEW.card_token IS DISTINCT FROM OLD.card_token
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.last_four IS DISTINCT FROM OLD.last_four
       OR NEW.card_scheme IS DISTINCT FROM OLD.card_scheme THEN
      RAISE EXCEPTION 'saved_card_fields_server_only';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_saved_cards_client_update_guard ON public.saved_cards;
CREATE TRIGGER tr_saved_cards_client_update_guard
  BEFORE UPDATE ON public.saved_cards
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_saved_cards_client_update_guard();

REVOKE ALL ON FUNCTION public.fulfill_paid_billing(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fulfill_paid_billing(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.cancel_subscription(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_subscription(uuid, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_expire_due() TO service_role;
REVOKE ALL ON FUNCTION public.subscription_my_entitlements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_my_entitlements() TO authenticated;
REVOKE ALL ON FUNCTION public.prepare_instant_credit_refund(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_instant_credit_refund(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.apply_instant_credit_refund(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_instant_credit_refund(uuid, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_billing_gateway_outcome(uuid, text, text, jsonb, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_billing_gateway_outcome(uuid, text, text, jsonb, text, text, boolean)
  TO service_role;

COMMIT;
