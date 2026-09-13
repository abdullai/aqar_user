-- أكواد خصم (عربي/إنجليزي/أرقام/رموز) مرة واحدة لكل مستخدم + منح باقة.
-- نفّذ بعد نجاح 20260829260000.

BEGIN;

DELETE FROM public.subscription_promotion_redemptions d
WHERE d.id IN (
  SELECT id FROM (
    SELECT id,
           row_number() OVER (
             PARTITION BY promotion_id, user_id
             ORDER BY (billing_transaction_id IS NOT NULL) DESC, created_at DESC
           ) AS rn
    FROM public.subscription_promotion_redemptions
  ) x
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_promo_redemption_user_once
  ON public.subscription_promotion_redemptions (promotion_id, user_id);

CREATE OR REPLACE FUNCTION public._promo_norm_code(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')), '');
$$;

CREATE OR REPLACE FUNCTION public._promo_account_plan_type(p_account_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_account_type, '')))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;
$$;

CREATE OR REPLACE FUNCTION public._promo_purge_stale_holds()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.subscription_promotion_redemptions
  WHERE billing_transaction_id IS NULL
    AND created_at < now() - interval '2 hours';
END;
$$;

CREATE OR REPLACE FUNCTION public.quote_promo_code(
  p_code text,
  p_amount_sar numeric
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
  v_type text;
  v_at text;
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

  SELECT coalesce(nullif(trim(account_type), ''), 'user') INTO v_at
  FROM public.users_profiles WHERE user_id = v_uid;
  v_type := public._promo_account_plan_type(v_at);
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

CREATE OR REPLACE FUNCTION public._promo_hold_for_user(p_promotion_id uuid, p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.subscription_promotion_redemptions (promotion_id, user_id)
  VALUES (p_promotion_id, p_uid);
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN unique_violation THEN
  IF EXISTS (
    SELECT 1 FROM public.subscription_promotion_redemptions r
    WHERE r.promotion_id = p_promotion_id
      AND r.user_id = p_uid
      AND r.billing_transaction_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_used');
  END IF;
  RETURN jsonb_build_object('ok', true, 'held', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.redeem_promo_code(
  p_code text,
  p_billing_transaction_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_q jsonb;
  v_pid uuid;
  v_tx public.billing_transactions%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_billing_transaction_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_required');
  END IF;
  SELECT * INTO v_tx
  FROM public.billing_transactions
  WHERE id = p_billing_transaction_id AND user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;
  IF v_tx.status NOT IN ('success', 'pending') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_payable');
  END IF;

  v_q := public.quote_promo_code(p_code, coalesce(v_tx.amount, 1));
  IF (v_q->>'ok')::boolean IS DISTINCT FROM true
     AND coalesce(v_q->>'error', '') <> 'already_used' THEN
    RETURN v_q;
  END IF;
  v_pid := coalesce(
    (v_q->>'promotion_id')::uuid,
    (
      SELECT id FROM public.subscription_promotions
      WHERE lower(code) = lower(public._promo_norm_code(p_code))
      LIMIT 1
    )
  );
  IF v_pid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;

  INSERT INTO public.subscription_promotion_redemptions (
    promotion_id, user_id, billing_transaction_id
  ) VALUES (
    v_pid, v_uid, p_billing_transaction_id
  )
  ON CONFLICT (promotion_id, user_id) DO UPDATE
  SET billing_transaction_id = excluded.billing_transaction_id
  WHERE public.subscription_promotion_redemptions.billing_transaction_id IS NULL
     OR public.subscription_promotion_redemptions.billing_transaction_id
        = excluded.billing_transaction_id;

  RETURN jsonb_build_object('ok', true, 'promotion_id', v_pid);
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_promo_to_pending_billing(
  p_billing_id uuid,
  p_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tx public.billing_transactions%ROWTYPE;
  v_q jsonb;
  v_after numeric;
  v_hold jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO v_tx
  FROM public.billing_transactions
  WHERE id = p_billing_id AND user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;
  IF v_tx.status <> 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_pending');
  END IF;
  v_q := public.quote_promo_code(p_code, v_tx.amount);
  IF (v_q->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN v_q;
  END IF;
  v_after := (v_q->>'amount_after')::numeric(10,2);
  v_hold := public._promo_hold_for_user((v_q->>'promotion_id')::uuid, v_uid);
  IF (v_hold->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN v_hold;
  END IF;
  UPDATE public.billing_transactions
  SET
    amount = v_after,
    gateway_response = coalesce(gateway_response, '{}'::jsonb) || jsonb_build_object(
      'promo_code', v_q->>'code',
      'promo_id', v_q->>'promotion_id',
      'amount_before', v_q->>'amount_before'
    )
  WHERE id = p_billing_id;
  RETURN v_q || jsonb_build_object('billing_id', p_billing_id);
END;
$$;

DROP FUNCTION IF EXISTS public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean);

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_promo(
  p_code text,
  p_kind text DEFAULT 'percent_off',
  p_value numeric DEFAULT 0,
  p_title_ar text DEFAULT '',
  p_title_en text DEFAULT '',
  p_active boolean DEFAULT true,
  p_valid_from timestamptz DEFAULT NULL,
  p_valid_to timestamptz DEFAULT NULL,
  p_max_redemptions int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text := public._promo_norm_code(p_code);
  v_kind text := lower(trim(coalesce(p_kind, 'percent_off')));
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_promo FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_promo');
  END IF;
  IF v_code IS NULL OR char_length(v_code) < 2 OR char_length(v_code) > 64 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'code_required');
  END IF;
  IF v_kind NOT IN ('percent_off', 'fixed_off', 'trial_days', 'first_payment_bonus') THEN
    v_kind := 'percent_off';
  END IF;
  SELECT id INTO v_id FROM public.subscription_promotions WHERE lower(code) = lower(v_code);
  IF v_id IS NOT NULL THEN
    UPDATE public.subscription_promotions SET
      kind = v_kind,
      value = coalesce(p_value, 0),
      title_ar = p_title_ar,
      title_en = p_title_en,
      is_active = coalesce(p_active, true),
      per_user_limit = 1,
      valid_from = p_valid_from,
      valid_to = p_valid_to,
      max_redemptions = p_max_redemptions
    WHERE id = v_id;
  ELSE
    INSERT INTO public.subscription_promotions (
      code, kind, value, title_ar, title_en, is_active, per_user_limit,
      valid_from, valid_to, max_redemptions
    ) VALUES (
      v_code, v_kind, coalesce(p_value, 0), p_title_ar, p_title_en,
      coalesce(p_active, true), 1, p_valid_from, p_valid_to, p_max_redemptions
    ) RETURNING id INTO v_id;
  END IF;
  PERFORM public._staff_audit(
    'upsert_promo', 'subscription_promotions', v_id::text,
    jsonb_build_object('code', v_code, 'kind', v_kind)
  );
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'code', v_code);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_promos()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'code', p.code,
        'kind', p.kind,
        'value', p.value,
        'title_ar', p.title_ar,
        'title_en', p.title_en,
        'is_active', p.is_active,
        'valid_from', p.valid_from,
        'valid_to', p.valid_to,
        'max_redemptions', p.max_redemptions,
        'used', (
          SELECT count(*)::int FROM public.subscription_promotion_redemptions r
          WHERE r.promotion_id = p.id AND r.billing_transaction_id IS NOT NULL
        )
      ) ORDER BY p.created_at DESC)
      FROM public.subscription_promotions p
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_promo_redemptions(
  p_id uuid,
  p_q text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q text := public._promo_norm_code(p_q);
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', r.user_id,
        'username', up.username,
        'name', coalesce(nullif(trim(up.full_name_ar), ''), nullif(trim(up.full_name), ''), ''),
        'account_type', coalesce(up.account_type, ''),
        'created_at', r.created_at,
        'billing_transaction_id', r.billing_transaction_id,
        'amount', bt.amount
      ) ORDER BY r.created_at DESC)
      FROM public.subscription_promotion_redemptions r
      LEFT JOIN public.users_profiles up ON up.user_id = r.user_id
      LEFT JOIN public.billing_transactions bt ON bt.id = r.billing_transaction_id
      WHERE r.promotion_id = p_id
        AND r.billing_transaction_id IS NOT NULL
        AND (
          v_q IS NULL
          OR up.username ILIKE '%' || v_q || '%'
          OR coalesce(up.full_name_ar, '') ILIKE '%' || v_q || '%'
          OR coalesce(up.full_name, '') ILIKE '%' || v_q || '%'
          OR coalesce(up.account_type, '') ILIKE '%' || v_q || '%'
        )
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_suggested_plans(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_at text;
  v_type text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT coalesce(nullif(trim(account_type), ''), 'user') INTO v_at
  FROM public.users_profiles WHERE user_id = p_user_id;
  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_required');
  END IF;
  v_type := public._promo_account_plan_type(v_at);
  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_type,
    'free_tier', v_type = 'individual',
    'rows', CASE WHEN v_type = 'individual' THEN '[]'::jsonb ELSE coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pl.id,
        'name_ar', pl.name_ar,
        'name_en', pl.name_en,
        'user_type', pl.user_type,
        'price_monthly', pl.price_monthly,
        'price_yearly', pl.price_yearly,
        'sort_order', pl.sort_order
      ) ORDER BY pl.sort_order)
      FROM public.subscription_plans pl
      WHERE pl.is_active
        AND lower(pl.user_type) = v_type
        AND coalesce(pl.sort_order, 0) IN (1, 2, 3, 4)
    ), '[]'::jsonb) END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._ops_upsert_granted_subscription(
  p_uid uuid,
  p_org_id uuid,
  p_plan_id uuid,
  p_end date,
  p_ends timestamptz,
  p_period text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_id uuid;
  v_period text := CASE
    WHEN lower(coalesce(p_period, 'yearly')) = 'monthly' THEN 'monthly'
    ELSE 'yearly'
  END;
BEGIN
  SELECT s.id INTO v_sub_id
  FROM public.user_subscriptions s
  WHERE s.user_id = p_uid
    AND (
      (p_org_id IS NULL AND s.organization_id IS NULL)
      OR s.organization_id = p_org_id
    )
  ORDER BY s.end_date DESC NULLS LAST, s.created_at DESC
  LIMIT 1;

  IF v_sub_id IS NOT NULL THEN
    UPDATE public.user_subscriptions
    SET
      plan_id = p_plan_id,
      status = 'active',
      period = v_period,
      start_date = current_date,
      end_date = p_end,
      starts_at = coalesce(starts_at, now()),
      ends_at = p_ends,
      auto_renew = false,
      updated_at = now()
    WHERE id = v_sub_id;
  ELSE
    INSERT INTO public.user_subscriptions (
      user_id, organization_id, plan_id, status, period,
      start_date, end_date, auto_renew, starts_at, ends_at
    )
    VALUES (
      p_uid, p_org_id, p_plan_id, 'active', v_period,
      current_date, p_end, false, now(), p_ends
    );
  END IF;
END;
$$;

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
  SELECT coalesce(nullif(trim(account_type), ''), 'user') INTO v_at
  FROM public.users_profiles WHERE user_id = p_user_id;
  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'user_required');
  END IF;
  v_type := public._promo_account_plan_type(v_at);
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
    'grant_plan', 'user_subscriptions', p_user_id::text,
    jsonb_build_object('plan_id', p_plan_id, 'months', v_months, 'account_type', v_at)
  );
  RETURN jsonb_build_object(
    'ok', true,
    'end_date', v_end,
    'months', v_months,
    'period', v_period
  );
END;
$$;

DROP FUNCTION IF EXISTS public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text);

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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
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
    p_plan_id, p_period, p_with_auto_pay, p_upgrade_subscription_id
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
      RETURN v_promo;
    END IF;
    v_expected := (v_promo->>'amount_after')::numeric(10,2);
  END IF;

  v_diff := abs(round(coalesce(p_amount_sar,0) - v_expected, 2));
  IF v_diff > 0.05 THEN
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
    'period', p_period,
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

REVOKE ALL ON FUNCTION public._promo_norm_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._promo_account_plan_type(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._promo_purge_stale_holds() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._promo_hold_for_user(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_upsert_granted_subscription(uuid, uuid, uuid, date, timestamptz, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.quote_promo_code(text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_promo_code(text, numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.redeem_promo_code(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_promo_code(text, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.apply_promo_to_pending_billing(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.apply_promo_to_pending_billing(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean, timestamptz, timestamptz, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean, timestamptz, timestamptz, int) TO authenticated;

REVOKE ALL ON FUNCTION public.platform_staff_promo_redemptions(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_promo_redemptions(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_suggested_plans(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_suggested_plans(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_grant_plan(uuid, uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_grant_plan(uuid, uuid, int) TO authenticated;
REVOKE ALL ON FUNCTION public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text, text) TO authenticated, service_role;

COMMIT;
