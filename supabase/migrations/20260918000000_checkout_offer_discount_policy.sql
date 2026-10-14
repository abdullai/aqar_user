-- =============================================================================
-- 2026-09-18 — عرض دفع واحد (quote_checkout_offer) + خصم تلقائي فعلي
--              + سياسة كوبون بلا جمع مزدوج + استهلاك الكود عند نجاح الدفع.
-- لا يغيّر أسعار الكتالوج. billing_transactions تبقى مصدر الحقيقة.
-- =============================================================================

BEGIN;

ALTER TABLE public.subscription_promotions
  ADD COLUMN IF NOT EXISTS stack_with_auto_pay boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_discount_sar numeric(12,2);

COMMENT ON COLUMN public.subscription_promotions.stack_with_auto_pay IS
  'مُهمَل: سياسة الفاتورة «الأفضل يفوز» — لا يُجمع خصم التجديد مع الكود.';

-- ── السعر الكانوني: خصم تلقائي حسب فترة الفاتورة وليس plan_program ──────────
CREATE OR REPLACE FUNCTION public.compute_canonical_charge(
  p_plan_id uuid,
  p_period  text DEFAULT 'monthly',
  p_with_auto_pay boolean DEFAULT false,
  p_upgrade_subscription_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan record;
  v_base numeric(12,4);
  v_after_auto numeric(12,4);
  v_upgrade jsonb;
  v_final numeric(12,4);
  v_period text := public._normalize_billing_period(p_period);
  v_auto_pct numeric(5,2);
  v_apply_auto boolean;
  v_auto_sar numeric(12,2) := 0;
BEGIN
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_found');
  END IF;

  v_base := CASE v_period
    WHEN 'yearly' THEN v_plan.price_yearly
    WHEN 'one_time' THEN v_plan.price_monthly
    ELSE v_plan.price_monthly
  END;
  v_base := round(coalesce(v_base, 0), 2);

  v_auto_pct := COALESCE(v_plan.auto_pay_discount_percent, 0);

  -- مرة واحدة: ممنوع خصم التجديد التلقائي.
  -- شهري/سنوي: يُطبَّق فقط إذا طُلب ومع نسبة > 0 من الباقة (مصدر الخادم).
  v_apply_auto := coalesce(p_with_auto_pay, false)
    AND v_period IN ('monthly', 'yearly')
    AND v_auto_pct > 0
    AND p_upgrade_subscription_id IS NULL;

  IF v_apply_auto THEN
    v_auto_sar := round(v_base * (least(greatest(v_auto_pct, 0), 100) / 100.0), 2);
    v_after_auto := round(greatest(0, v_base - v_auto_sar), 2);
  ELSE
    v_after_auto := v_base;
    v_auto_pct := 0;
    v_auto_sar := 0;
  END IF;

  IF p_upgrade_subscription_id IS NOT NULL THEN
    v_upgrade := public.subscription_compute_upgrade_charge(
      p_plan_id, v_period
    );
    IF (v_upgrade->>'ok') = 'true' THEN
      v_final := (v_upgrade->>'amount_due')::numeric;
      v_apply_auto := false;
      v_auto_sar := 0;
      v_auto_pct := 0;
    ELSE
      v_final := v_after_auto;
    END IF;
  ELSE
    v_final := v_after_auto;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', v_plan.id,
    'period', v_period,
    'base_price', v_base,
    'auto_pay_discount_pct', v_auto_pct,
    'auto_pay_discount_sar', v_auto_sar,
    'with_auto_pay', v_apply_auto,
    'price_after_auto_pay', v_after_auto,
    'upgrade_charge', v_upgrade,
    'final_amount', v_final
  );
END;
$$;

-- ── اقتباس كوبون: إعادة فحص الاشتراك الفعّال + سقف الخصم ────────────────────
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
  v_off numeric(12,2);
  v_used int;
  v_per_user int;
  v_type text;
  v_at text;
  v_period text := lower(trim(coalesce(p_period, '')));
  v_ckey text;
  v_pct numeric(8,2) := 0;
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
  IF public._ops_has_active_paid_sub(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'has_active_subscription');
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
  IF coalesce(p.max_redemptions_per_user, p.per_user_limit, 1) > 0
     AND v_per_user >= coalesce(p.max_redemptions_per_user, p.per_user_limit, 1) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_used');
  END IF;

  v_ckey := coalesce(nullif(btrim(p.campaign_key), ''), p.code);
  IF EXISTS (
    SELECT 1
    FROM public.subscription_promotion_redemptions r
    JOIN public.subscription_promotions o ON o.id = r.promotion_id
    WHERE r.user_id = v_uid
      AND r.billing_transaction_id IS NOT NULL
      AND o.id <> p.id
      AND coalesce(nullif(btrim(o.campaign_key), ''), o.code) IS DISTINCT FROM v_ckey
      AND coalesce(o.is_active, false)
      AND (o.valid_from IS NULL OR o.valid_from <= now())
      AND (o.valid_to IS NULL OR o.valid_to > now())
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'other_campaign_active');
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
    v_pct := least(greatest(p.value, 0), 100);
    v_off := round(v_before * (v_pct / 100.0), 2);
  ELSIF p.kind IN ('fixed_off', 'first_payment_bonus') THEN
    v_off := round(coalesce(p.value, 0), 2);
    IF v_before > 0 THEN
      v_pct := round((v_off / v_before) * 100.0, 2);
    END IF;
  ELSE
    v_off := 0;
  END IF;
  IF p.max_discount_sar IS NOT NULL AND v_off > p.max_discount_sar THEN
    v_off := round(p.max_discount_sar, 2);
  END IF;
  v_after := greatest(0, round(v_before - coalesce(v_off, 0), 2));

  RETURN jsonb_build_object(
    'ok', true,
    'code', p.code,
    'kind', p.kind,
    'value', p.value,
    'percent', v_pct,
    'discount_sar', v_off,
    'trial_days', p.trial_days,
    'title_ar', p.title_ar,
    'title_en', p.title_en,
    'amount_before', v_before,
    'amount_after', v_after,
    'min_amount_sar', p.min_amount_sar,
    'max_discount_sar', p.max_discount_sar,
    'valid_to', p.valid_to,
    'stack_with_auto_pay', false
  );
END;
$$;

-- هيكل مبدئي حتى يُترجم quote_checkout_offer — يُستبدل بالدالة الكاملة أدناه.
CREATE OR REPLACE FUNCTION public.list_eligible_promo_codes(
  p_plan_id uuid,
  p_period text,
  p_sort text DEFAULT 'highest',
  p_upgrade_subscription_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object('ok', true, 'codes', '[]'::jsonb, 'can_use', false);
END;
$$;

-- ── عرض الدفع المعتمد: مصدر واحد للسعر والخصم ──────────────────────────────
CREATE OR REPLACE FUNCTION public.quote_checkout_offer(
  p_plan_id uuid,
  p_period text,
  p_with_auto_pay boolean DEFAULT false,
  p_promo_code text DEFAULT NULL,
  p_upgrade_subscription_id uuid DEFAULT NULL,
  p_purpose text DEFAULT 'subscribe_new'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_period text := public._normalize_billing_period(p_period);
  v_purpose text := lower(trim(coalesce(p_purpose, 'subscribe_new')));
  v_charge jsonb;
  v_base numeric(12,2);
  v_auto_pct numeric(8,2) := 0;
  v_auto_sar numeric(12,2) := 0;
  v_promo jsonb;
  v_promo_sar numeric(12,2) := 0;
  v_promo_pct numeric(8,2) := 0;
  v_code text := public._promo_norm_code(p_promo_code);
  v_kind text := 'none';
  v_final numeric(12,2);
  v_show_auto boolean;
  v_eligible jsonb := '[]'::jsonb;
  v_list jsonb;
  v_want_auto boolean;
  v_label_ar text := '';
  v_label_en text := '';
  v_skip text;
  v_min numeric(12,2) := 1;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF v_purpose IN ('subscribe', 'subscription_checkout') THEN
    v_purpose := 'subscribe_new';
  END IF;

  SELECT coalesce(nullif(amount_sar, 0), 1) INTO v_min
    FROM public.platform_fee_catalog
   WHERE fee_key = 'save_card_verify'
   LIMIT 1;
  IF v_min IS NULL OR v_min < 0.01 THEN
    v_min := 1;
  END IF;

  v_want_auto := coalesce(p_with_auto_pay, false)
    AND v_period IN ('monthly', 'yearly')
    AND v_purpose NOT IN ('one_time', 'instant_market_request', 'save_card_only')
    AND p_upgrade_subscription_id IS NULL;

  v_charge := public.compute_canonical_charge(
    p_plan_id, v_period, v_want_auto, p_upgrade_subscription_id
  );
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN v_charge;
  END IF;

  v_base := coalesce((v_charge->>'base_price')::numeric, 0);
  IF (v_charge->>'with_auto_pay')::boolean IS TRUE THEN
    v_auto_pct := coalesce((v_charge->>'auto_pay_discount_pct')::numeric, 0);
    v_auto_sar := coalesce((v_charge->>'auto_pay_discount_sar')::numeric, 0);
  END IF;

  v_final := coalesce((v_charge->>'final_amount')::numeric, v_base);
  v_show_auto := (v_charge->>'with_auto_pay')::boolean IS TRUE;

  v_list := public.list_eligible_promo_codes(
    p_plan_id, v_period, 'highest', p_upgrade_subscription_id
  );
  IF (v_list->>'ok')::boolean IS TRUE THEN
    v_eligible := coalesce(v_list->'codes', '[]'::jsonb);
  END IF;

  IF v_code IS NOT NULL THEN
    v_promo := public.quote_promo_code(v_code, v_base, p_plan_id, v_period);
    IF (v_promo->>'ok')::boolean IS DISTINCT FROM true THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', coalesce(v_promo->>'error', 'invalid_code'),
        'promo', v_promo,
        'base_price', v_base,
        'eligible_codes', v_eligible
      );
    END IF;
    v_promo_sar := coalesce((v_promo->>'discount_sar')::numeric, 0);
    v_promo_pct := coalesce((v_promo->>'percent')::numeric, 0);

    IF v_promo_pct >= 99.999
       OR v_promo_sar + 0.004 >= v_base
       OR round(greatest(0, v_base - v_promo_sar), 2) < 0.01 THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'promo_zeros_invoice',
        'promo', v_promo,
        'base_price', v_base,
        'eligible_codes', v_eligible
      );
    END IF;

    -- Best-of: one discount only. stack_with_auto_pay is ignored.
    IF v_show_auto AND v_promo_sar > v_auto_sar THEN
      v_kind := 'promo';
      v_auto_sar := 0;
      v_auto_pct := 0;
      v_show_auto := false;
      v_final := round(v_base - v_promo_sar, 2);
      v_label_ar := 'خصم كود: ' || (v_promo->>'code');
      v_label_en := 'Discount code: ' || (v_promo->>'code');
    ELSIF v_show_auto THEN
      v_kind := 'auto_pay';
      v_promo_sar := 0;
      v_skip := 'auto_pay_better';
      v_final := round(greatest(0, v_base - v_auto_sar), 2);
      v_label_ar := 'خصم الدفع التلقائي';
      v_label_en := 'Auto-pay discount';
    ELSE
      v_kind := 'promo';
      v_final := round(v_base - v_promo_sar, 2);
      v_label_ar := 'خصم كود: ' || (v_promo->>'code');
      v_label_en := 'Discount code: ' || (v_promo->>'code');
    END IF;
  ELSIF v_show_auto THEN
    v_kind := 'auto_pay';
    v_label_ar := 'خصم الدفع التلقائي';
    v_label_en := 'Auto-pay discount';
  END IF;

  IF v_final < v_min THEN
    v_final := v_min;
  END IF;
  IF v_final > v_base AND v_base >= v_min THEN
    v_final := v_base;
  END IF;
  v_final := round(v_final, 2);

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', p_plan_id,
    'period', v_period,
    'purpose', v_purpose,
    'base_price', v_base,
    'auto_pay_discount_pct', v_auto_pct,
    'auto_pay_discount_sar', v_auto_sar,
    'show_auto_pay', v_show_auto,
    'promo_code', CASE WHEN v_kind = 'promo' THEN v_promo->>'code' ELSE NULL END,
    'promo_discount_sar', CASE WHEN v_kind = 'promo' THEN v_promo_sar ELSE 0 END,
    'promo_percent', CASE WHEN v_kind = 'promo' THEN v_promo_pct ELSE 0 END,
    'promo_skipped', v_skip,
    'applied_discount_kind', v_kind,
    'discount_sar', round(greatest(0, v_base - v_final), 2),
    'discount_label_ar', v_label_ar,
    'discount_label_en', v_label_en,
    'final_amount', v_final,
    'vat_included', true,
    'eligible_codes', v_eligible,
    'has_eligible_promos', jsonb_array_length(v_eligible) > 0,
    'recommended_kind', CASE
      WHEN v_kind = 'promo' THEN 'promo'
      WHEN v_show_auto THEN 'auto_pay'
      WHEN jsonb_array_length(v_eligible) > 0 THEN 'promo'
      ELSE 'none'
    END,
    'gateway_minimum_sar', v_min,
    'breakdown', v_charge,
    'promo', CASE WHEN v_kind = 'promo' THEN v_promo ELSE NULL END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_eligible_promo_codes(
  p_plan_id uuid,
  p_period text,
  p_sort text DEFAULT 'highest',
  p_upgrade_subscription_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_period text := public._normalize_billing_period(p_period);
  v_charge jsonb;
  v_base numeric(12,2);
  v_out jsonb := '[]'::jsonb;
  r record;
  q jsonb;
  v_sort text := lower(trim(coalesce(p_sort, 'highest')));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required', 'codes', '[]'::jsonb);
  END IF;
  IF p_upgrade_subscription_id IS NOT NULL OR public._ops_has_active_paid_sub(v_uid) THEN
    RETURN jsonb_build_object('ok', true, 'codes', '[]'::jsonb, 'can_use', false, 'error', 'has_active_subscription');
  END IF;

  v_charge := public.compute_canonical_charge(p_plan_id, v_period, false, NULL);
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'error', coalesce(v_charge->>'error', 'plan_invalid'), 'codes', '[]'::jsonb);
  END IF;
  v_base := coalesce((v_charge->>'base_price')::numeric, 0);

  FOR r IN
    SELECT code FROM public.subscription_promotions
     WHERE coalesce(is_active, false)
       AND (valid_from IS NULL OR valid_from <= now())
       AND (valid_to IS NULL OR valid_to > now())
  LOOP
    q := public.quote_promo_code(r.code, v_base, p_plan_id, v_period);
    IF (q->>'ok')::boolean IS TRUE THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'code', q->>'code',
        'kind', q->>'kind',
        'percent', coalesce((q->>'percent')::numeric, 0),
        'value', q->'value',
        'discount_sar', coalesce((q->>'discount_sar')::numeric, 0),
        'min_amount_sar', q->'min_amount_sar',
        'max_discount_sar', q->'max_discount_sar',
        'valid_to', q->>'valid_to',
        'title_ar', q->>'title_ar',
        'title_en', q->>'title_en',
        'stack_with_auto_pay', coalesce((q->>'stack_with_auto_pay')::boolean, false)
      ));
    END IF;
  END LOOP;

  IF v_sort = 'expiring' THEN
    SELECT coalesce(jsonb_agg(x ORDER BY (x->>'valid_to') NULLS LAST), '[]'::jsonb)
      INTO v_out
      FROM jsonb_array_elements(v_out) x;
  ELSE
    SELECT coalesce(jsonb_agg(x ORDER BY (x->>'percent')::numeric DESC, (x->>'discount_sar')::numeric DESC), '[]'::jsonb)
      INTO v_out
      FROM jsonb_array_elements(v_out) x;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'can_use', jsonb_array_length(v_out) > 0,
    'codes', coalesce(v_out, '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.promo_checkout_eligibility()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'can_use', false, 'error', 'auth_required');
  END IF;
  IF public._ops_has_active_paid_sub(v_uid) THEN
    RETURN jsonb_build_object('ok', true, 'can_use', false, 'error', 'has_active_subscription');
  END IF;
  RETURN jsonb_build_object('ok', true, 'can_use', true);
END;
$$;

-- ── التحقق من النية يستخدم العرض المعتمد (لا جمع أعمى) ──────────────────────
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
  v_offer jsonb;
  v_expected numeric(10,2);
  v_diff numeric(10,2);
  v_rate jsonb;
  v_sort int := 0;
  v_addon boolean := false;
  v_hold jsonb;
  v_assert jsonb;
  v_period text := public._normalize_billing_period(p_period);
  v_pid uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
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

  v_offer := public.quote_checkout_offer(
    p_plan_id, v_period, p_with_auto_pay, p_promo_code,
    p_upgrade_subscription_id, 'subscribe_new'
  );
  IF (v_offer->>'ok')::boolean IS DISTINCT FROM true THEN
    PERFORM public._billing_security_event(
      v_uid, 'coupon_rejected', p_plan_id, v_period, p_amount_sar, v_offer
    );
    RETURN v_offer;
  END IF;
  v_expected := (v_offer->>'final_amount')::numeric(10,2);

  IF p_amount_sar IS NOT NULL THEN
    v_diff := abs(round(coalesce(p_amount_sar,0) - v_expected, 2));
    IF v_diff > 0.05 THEN
      PERFORM public._billing_security_event(
        v_uid, 'amount_mismatch', p_plan_id, v_period, p_amount_sar,
        jsonb_build_object('expected', v_expected, 'offer', v_offer)
      );
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'amount_mismatch',
        'submitted', p_amount_sar,
        'expected', v_expected,
        'offer', v_offer
      );
    END IF;
  END IF;

  IF coalesce(v_offer->>'promo_code', '') <> '' THEN
    SELECT id INTO v_pid
      FROM public.subscription_promotions
     WHERE lower(code) = lower(v_offer->>'promo_code')
     LIMIT 1;
    IF v_pid IS NOT NULL THEN
      v_hold := public._promo_hold_for_user(v_pid, v_uid);
      IF (v_hold->>'ok')::boolean IS DISTINCT FROM true THEN
        RETURN v_hold;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', p_plan_id,
    'period', v_period,
    'with_auto_pay', coalesce((v_offer->>'show_auto_pay')::boolean, false),
    'expected_amount', v_expected,
    'submitted_amount', p_amount_sar,
    'offer', v_offer,
    'breakdown', v_offer->'breakdown',
    'promo', v_offer->'promo',
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
  v_offer jsonb;
  v_amt numeric(10,2);
  v_bid uuid;
  v_period text := public._normalize_billing_period(p_period);
  v_purpose text := lower(trim(coalesce(p_purpose, 'subscribe_new')));
  v_idem text := nullif(trim(coalesce(p_idempotency_key, '')), '');
  v_exist public.billing_transactions%ROWTYPE;
  v_subtotal numeric(12,2);
  v_discount numeric(12,2) := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
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

  v_offer := v_intent->'offer';
  v_amt := coalesce((v_intent->>'expected_amount')::numeric(10,2), 0);
  v_subtotal := coalesce((v_offer->>'base_price')::numeric(12,2), v_amt);
  v_discount := coalesce((v_offer->>'discount_sar')::numeric(12,2), 0);
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
      'offer', v_offer,
      'applied_discount_kind', v_offer->>'applied_discount_kind',
      'discount_label_ar', v_offer->>'discount_label_ar',
      'discount_label_en', v_offer->>'discount_label_en',
      'auto_pay_discount_sar', v_offer->'auto_pay_discount_sar',
      'auto_pay_discount_pct', v_offer->'auto_pay_discount_pct',
      'promo_code', v_offer->>'promo_code',
      'promo_discount_sar', v_offer->'promo_discount_sar'
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
    'intent', v_intent,
    'offer', v_offer
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

-- استهلاك الكود فقط بعد نجاح العملية — ذري عبر الفهرس الفريد
CREATE OR REPLACE FUNCTION public._promo_finalize_on_paid_billing(p_billing_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bt public.billing_transactions%ROWTYPE;
  v_code text;
  v_pid uuid;
BEGIN
  IF p_billing_id IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO bt FROM public.billing_transactions WHERE id = p_billing_id;
  IF NOT FOUND OR bt.status IS DISTINCT FROM 'success' THEN
    RETURN;
  END IF;
  v_code := public._promo_norm_code(coalesce(
    bt.gateway_response->>'promo_code',
    bt.gateway_response->'offer'->>'promo_code'
  ));
  IF v_code IS NULL THEN
    RETURN;
  END IF;
  IF coalesce(bt.gateway_response->>'applied_discount_kind', '') NOT IN ('promo', 'stacked') THEN
    RETURN;
  END IF;
  SELECT id INTO v_pid
    FROM public.subscription_promotions
   WHERE lower(code) = lower(v_code)
   LIMIT 1;
  IF v_pid IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.subscription_promotion_redemptions (
    promotion_id, user_id, billing_transaction_id
  ) VALUES (
    v_pid, bt.user_id, bt.id
  )
  ON CONFLICT (promotion_id, user_id) DO UPDATE
  SET billing_transaction_id = excluded.billing_transaction_id
  WHERE public.subscription_promotion_redemptions.billing_transaction_id IS NULL
     OR public.subscription_promotion_redemptions.billing_transaction_id
        = excluded.billing_transaction_id;
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
    PERFORM public._promo_finalize_on_paid_billing(bt.id);
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
         gateway_response = (
           coalesce(bt.gateway_response, '{}'::jsonb)
           || coalesce(p_gateway_response, '{}'::jsonb)
           || jsonb_strip_nulls(jsonb_build_object(
                'offer', bt.gateway_response->'offer',
                'applied_discount_kind', bt.gateway_response->'applied_discount_kind',
                'discount_label_ar', bt.gateway_response->'discount_label_ar',
                'discount_label_en', bt.gateway_response->'discount_label_en',
                'auto_pay_discount_sar', bt.gateway_response->'auto_pay_discount_sar',
                'auto_pay_discount_pct', bt.gateway_response->'auto_pay_discount_pct',
                'promo_code', bt.gateway_response->'promo_code',
                'promo_discount_sar', bt.gateway_response->'promo_discount_sar'
              ))
         ),
         failure_code = p_failure_code,
         failure_reason = p_failure_reason,
         review_required = coalesce(p_review_required, false),
         paid_at = CASE WHEN v_status = 'success' THEN coalesce(paid_at, timezone('utc', now())) ELSE paid_at END,
         completed_at = CASE WHEN v_status IN ('success', 'failed', 'cancelled', 'expired', 'refunded')
           THEN coalesce(completed_at, timezone('utc', now())) ELSE completed_at END
   WHERE id = bt.id;

  IF v_status = 'success' THEN
    PERFORM public._promo_finalize_on_paid_billing(p_billing_transaction_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', v_status);
END;
$$;

REVOKE ALL ON FUNCTION public.quote_checkout_offer(uuid, text, boolean, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_checkout_offer(uuid, text, boolean, text, uuid, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.list_eligible_promo_codes(uuid, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_eligible_promo_codes(uuid, text, text, uuid)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.quote_promo_code(text, numeric, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_promo_code(text, numeric, uuid, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.compute_canonical_charge(uuid, text, boolean, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_canonical_charge(uuid, text, boolean, uuid)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_intent(uuid, text, numeric, boolean, uuid, text, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text, text)
  TO authenticated, service_role;

REVOKE ALL ON FUNCTION public._promo_finalize_on_paid_billing(uuid) FROM PUBLIC;

COMMIT;
