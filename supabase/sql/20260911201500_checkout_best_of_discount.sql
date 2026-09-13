-- Best-of discounts: never stack auto-pay + promo, never charge 0/negative,
-- reject 100% codes that zero the invoice, floor to gateway minimum.

BEGIN;

UPDATE public.subscription_promotions
   SET stack_with_auto_pay = false
 WHERE stack_with_auto_pay IS DISTINCT FROM false;

COMMENT ON COLUMN public.subscription_promotions.stack_with_auto_pay IS
  'مُهمَل: سياسة الفاتورة «الأفضل يفوز» — لا يُجمع خصم التجديد مع الكود.';

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

COMMIT;
