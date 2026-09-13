-- منح إداري + كتالوج رسوم الحفظ: مطابقة الجمهور الحقيقي، بدون fallback خاطئ.

BEGIN;

CREATE OR REPLACE FUNCTION public.platform_staff_grant_plan(
  p_user_id uuid,
  p_plan_id uuid,
  p_months int DEFAULT 12
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_months int := GREATEST(1, LEAST(coalesce(p_months, 12), 36));
  v_end date;
  v_ends timestamptz;
  v_plan public.subscription_plans%ROWTYPE;
  v_at text;
  v_type text;
  v_org uuid;
  v_period text;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_finance');
  END IF;
  IF p_user_id IS NULL OR p_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_args');
  END IF;
  SELECT coalesce(nullif(trim(account_type), ''), '') INTO v_at
  FROM public.users_profiles WHERE user_id = p_user_id;
  IF v_at IS NULL OR v_at = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_required');
  END IF;
  v_type := public.subscription_map_account_audience(v_at);
  IF v_type IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'account_type_unknown');
  END IF;
  IF v_type = 'individual' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'free_tier');
  END IF;
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = p_plan_id AND is_active;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_invalid');
  END IF;
  IF lower(v_plan.user_type) IS DISTINCT FROM v_type THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_mismatch');
  END IF;
  IF coalesce(v_plan.sort_order, 0) NOT IN (1, 2, 3, 4) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_main_plan');
  END IF;

  v_end := (current_date + (v_months::text || ' months')::interval)::date;
  v_ends := now() + (v_months::text || ' months')::interval;
  v_period := CASE WHEN v_months >= 12 THEN 'yearly' ELSE 'monthly' END;

  PERFORM public._ops_upsert_granted_subscription(
    p_user_id, NULL, p_plan_id, v_end, v_ends, v_period
  );

  SELECT o.id INTO v_org
  FROM public.org_units o
  WHERE o.owner_user_id = p_user_id
  ORDER BY o.created_at DESC NULLS LAST
  LIMIT 1;
  IF v_org IS NOT NULL THEN
    PERFORM public._ops_upsert_granted_subscription(
      p_user_id, v_org, p_plan_id, v_end, v_ends, v_period
    );
  END IF;

  PERFORM public._staff_audit(
    'admin_grant', 'user_subscriptions', p_user_id::text,
    jsonb_build_object('plan_id', p_plan_id, 'months', v_months, 'account_type', v_at, 'purpose', 'admin_grant')
  );
  RETURN jsonb_build_object(
    'ok', true,
    'end_date', v_end,
    'months', v_months,
    'period', v_period
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_pending_billing_catalog_fee(
  p_fee_key text,
  p_payment_method text DEFAULT 'card',
  p_card_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_amt numeric(10,2);
  v_ar text;
  v_en text;
  v_bid uuid;
  v_key text := lower(trim(coalesce(p_fee_key, '')));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF v_key NOT IN ('save_card_verify') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fee_key_not_allowed');
  END IF;

  SELECT amount_sar, title_ar, title_en INTO v_amt, v_ar, v_en
  FROM public.platform_fee_catalog WHERE fee_key = v_key;
  IF v_amt IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fee_catalog_missing');
  END IF;

  INSERT INTO public.billing_transactions (
    user_id, amount, currency, status, payment_method, card_id,
    title_ar, title_en, gateway_response, purpose, subtotal_sar, vat_included
  ) VALUES (
    v_uid, v_amt, 'SAR', 'pending',
    coalesce(nullif(trim(p_payment_method), ''), 'card'),
    p_card_id, v_ar, v_en,
    jsonb_build_object('purpose', v_key, 'fee_key', v_key, 'validated', true),
    v_key, v_amt, true
  )
  RETURNING id INTO v_bid;

  RETURN jsonb_build_object('ok', true, 'transaction_id', v_bid, 'amount', v_amt);
END;
$$;

COMMIT;
