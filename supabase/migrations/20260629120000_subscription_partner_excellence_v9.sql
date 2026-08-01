-- =============================================================================
-- 2026-06-29 — v9: باقة الشريك / الأساسي / الاحترافية / التميز
--   • أسعار: شريك 49 | أساسي 99 | احترافي 149 | تميز 449
--   • إتمام الصفقة/شهر: 3 | 6 | 12 | 24
--   • خصم تجديد تلقائي 10% — شهري فقط
--   • سنوي 20% — بدون تجديد تلقائي
--   • لا مقاعد ولا خصم 50%
--   • الشامل (sort 4/14) للترقية
--   • توب-أب صفقات (11/12/13) لجميع الأدوار
-- =============================================================================

BEGIN;

-- ── (1) تثبيت الباقات الرئيسية ─────────────────────────────────────────────

UPDATE public.subscription_plans SET
  name_ar = N'باقة الشريك',
  name_en = 'Partner Plan',
  price_monthly = 49,
  price_yearly = round((49 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 3,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  cancellation_retention_offer_pct = 20.0,
  is_active = true
WHERE user_type = 'individual' AND sort_order = 1 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'الأساسي',
  name_en = 'Basic',
  price_monthly = 99,
  price_yearly = round((99 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 6,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  cancellation_retention_offer_pct = 20.0,
  is_active = true
WHERE user_type = 'marketer' AND sort_order = 1 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'الاحترافية',
  name_en = 'Professional',
  price_monthly = 149,
  price_yearly = round((149 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 12,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  cancellation_retention_offer_pct = 20.0,
  is_active = true
WHERE user_type IN ('office', 'institution', 'agency')
  AND sort_order = 2 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'باقة التميز',
  name_en = 'Excellence Plan',
  price_monthly = 449,
  price_yearly = round((449 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 24,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  cancellation_retention_offer_pct = 20.0,
  is_active = true
WHERE user_type = 'company' AND sort_order = 3 AND coalesce(is_trial_plan, false) = false;

-- ── (2) باقة الشامل — ترقية (sort 4 / 14) ─────────────────────────────────

UPDATE public.subscription_plans SET
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 89,
  price_yearly = round((89 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 10,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  is_active = true
WHERE user_type = 'individual' AND sort_order = 14 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 149,
  price_yearly = round((149 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 15,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  is_active = true
WHERE user_type = 'marketer' AND sort_order = 4 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 199,
  price_yearly = round((199 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 30,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  is_active = true
WHERE user_type IN ('office', 'institution', 'agency')
  AND sort_order = 4 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'الشامل',
  name_en = 'Comprehensive',
  price_monthly = 549,
  price_yearly = round((549 * 12 * 0.80)::numeric, 2),
  max_members = 0,
  max_market_offers = 48,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  is_active = true
WHERE user_type = 'company' AND sort_order = 4 AND coalesce(is_trial_plan, false) = false;

-- ── (3) توب-أب إتمام صفقات (11/12/13) — لكل الأدوار ────────────────────────

DO $$
DECLARE
  v_role text;
  v_roles text[] := ARRAY['individual','marketer','office','institution','agency','company'];
BEGIN
  FOREACH v_role IN ARRAY v_roles LOOP
    INSERT INTO public.subscription_plans (
      name_ar, name_en, user_type,
      price_monthly, price_yearly,
      max_members, max_market_offers,
      team_member_discount_percent, seat_unit_price_sar,
      auto_pay_discount_percent, cancellation_retention_offer_pct,
      sort_order, is_active, is_trial_plan, plan_program
    )
    SELECT
      N'إضافة صفقات — شهري', 'Deal top-up — monthly', v_role,
      29::numeric, round((29 * 12 * 0.80)::numeric, 2),
      0, 10,
      0, 0, 10.0, 20.0,
      11, true, false, 'monthly'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.subscription_plans sp
      WHERE sp.user_type = v_role AND sp.sort_order = 11
        AND coalesce(sp.is_trial_plan, false) = false
    );

    INSERT INTO public.subscription_plans (
      name_ar, name_en, user_type,
      price_monthly, price_yearly,
      max_members, max_market_offers,
      team_member_discount_percent, seat_unit_price_sar,
      auto_pay_discount_percent, cancellation_retention_offer_pct,
      sort_order, is_active, is_trial_plan, plan_program
    )
    SELECT
      N'إضافة صفقات — سنوي', 'Deal top-up — yearly', v_role,
      29::numeric, round((29 * 12 * 0.80)::numeric, 2),
      0, 10,
      0, 0, 0, 20.0,
      12, true, false, 'yearly'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.subscription_plans sp
      WHERE sp.user_type = v_role AND sp.sort_order = 12
        AND coalesce(sp.is_trial_plan, false) = false
    );

    INSERT INTO public.subscription_plans (
      name_ar, name_en, user_type,
      price_monthly, price_yearly,
      max_members, max_market_offers,
      team_member_discount_percent, seat_unit_price_sar,
      auto_pay_discount_percent, cancellation_retention_offer_pct,
      sort_order, is_active, is_trial_plan, plan_program
    )
    SELECT
      N'إضافة صفقات — مرة واحدة', 'Deal top-up — one-time', v_role,
      25::numeric, 25::numeric,
      0, 5,
      0, 0, 0, 20.0,
      13, true, false, 'lifetime_one_time'
    WHERE NOT EXISTS (
      SELECT 1 FROM public.subscription_plans sp
      WHERE sp.user_type = v_role AND sp.sort_order = 13
        AND coalesce(sp.is_trial_plan, false) = false
    );
  END LOOP;
END $$;

UPDATE public.subscription_plans SET
  name_ar = N'إضافة صفقات — شهري',
  name_en = 'Deal top-up — monthly',
  price_monthly = 29,
  price_yearly = round((29 * 12 * 0.80)::numeric, 2),
  max_market_offers = 10,
  max_members = 0,
  team_member_discount_percent = 0,
  seat_unit_price_sar = 0,
  auto_pay_discount_percent = 10.0,
  is_active = true,
  plan_program = 'monthly'
WHERE sort_order = 11 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'إضافة صفقات — سنوي',
  name_en = 'Deal top-up — yearly',
  price_monthly = 29,
  price_yearly = round((29 * 12 * 0.80)::numeric, 2),
  max_market_offers = 10,
  max_members = 0,
  auto_pay_discount_percent = 0,
  is_active = true,
  plan_program = 'yearly'
WHERE sort_order = 12 AND coalesce(is_trial_plan, false) = false;

UPDATE public.subscription_plans SET
  name_ar = N'إضافة صفقات — مرة واحدة',
  name_en = 'Deal top-up — one-time',
  price_monthly = 25,
  price_yearly = 25,
  max_market_offers = 5,
  max_members = 0,
  auto_pay_discount_percent = 0,
  is_active = true,
  plan_program = 'lifetime_one_time'
WHERE sort_order = 13 AND coalesce(is_trial_plan, false) = false;

-- ── (4) compute_canonical_charge — 10% شهري فقط ─────────────────────────────

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
  v_period text := lower(coalesce(p_period, 'monthly'));
  v_auto_pct numeric(5,2);
  v_apply_auto boolean;
BEGIN
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_found');
  END IF;

  v_base := CASE v_period
    WHEN 'yearly' THEN v_plan.price_yearly
    WHEN 'lifetime_one_time' THEN v_plan.price_monthly
    WHEN 'one_time' THEN v_plan.price_monthly
    ELSE v_plan.price_monthly
  END;

  v_auto_pct := COALESCE(v_plan.auto_pay_discount_percent, 10.0);

  v_apply_auto := coalesce(p_with_auto_pay, false)
    AND v_period = 'monthly'
    AND coalesce(v_plan.plan_program, 'monthly') NOT IN ('lifetime_one_time', 'yearly');

  IF v_apply_auto THEN
    v_after_auto := round(v_base * (1 - v_auto_pct / 100.0)::numeric, 2);
  ELSE
    v_after_auto := round(v_base, 2);
  END IF;

  IF p_upgrade_subscription_id IS NOT NULL THEN
    v_upgrade := public.subscription_compute_upgrade_charge(
      p_plan_id, v_period
    );
    IF (v_upgrade->>'ok') = 'true' THEN
      v_final := (v_upgrade->>'amount_due')::numeric;
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
    'with_auto_pay', v_apply_auto,
    'price_after_auto_pay', v_after_auto,
    'upgrade_charge', v_upgrade,
    'final_amount', v_final
  );
END;
$$;

-- ── (5) set_subscription_auto_pay — رسوم إيقاف الخصم (معامل رابع اختياري) ───

DROP FUNCTION IF EXISTS public.set_subscription_auto_pay(uuid, boolean, uuid);

CREATE OR REPLACE FUNCTION public.set_subscription_auto_pay(
  p_subscription_id uuid,
  p_enabled boolean,
  p_payment_method_id uuid DEFAULT NULL,
  p_penalty_billing_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sub public.user_subscriptions%ROWTYPE;
  v_plan public.subscription_plans%ROWTYPE;
  v_pct numeric(5,2);
  v_penalty numeric(10,2);
  v_period text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_sub FROM public.user_subscriptions
   WHERE id = p_subscription_id AND user_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'subscription_not_found_or_not_owner';
  END IF;

  IF coalesce(v_sub.status,'') NOT IN ('active','pending','cancelled') THEN
    RAISE EXCEPTION 'subscription_not_modifiable';
  END IF;

  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_sub.plan_id;
  v_pct := coalesce(v_plan.auto_pay_discount_percent, 10.0);
  v_period := lower(coalesce(v_sub.period, 'monthly'));

  IF NOT p_enabled
     AND coalesce(v_sub.auto_pay_discount_applied, false) = true
     AND v_period = 'monthly'
     AND coalesce(v_sub.ends_at, v_sub.end_date::timestamptz) > now() THEN
    v_penalty := round(coalesce(v_plan.price_monthly, 0) * v_pct / 100.0, 2);
    IF v_penalty > 0 AND p_penalty_billing_id IS NULL THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'penalty_required',
        'penalty_sar', v_penalty,
        'message_ar', format(
          'لإيقاف التجديد التلقائي قبل نهاية الفترة يلزم دفع رسوم تكميلية %s ر.س (فرق خصم %s%%).',
          v_penalty, v_pct
        ),
        'message_en', format(
          'Disabling auto-renew before period end requires a %s SAR penalty (the %s%% discount difference).',
          v_penalty, v_pct
        )
      );
    END IF;
    IF v_penalty > 0 AND p_penalty_billing_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.billing_transactions bt
        WHERE bt.id = p_penalty_billing_id
          AND bt.user_id = v_uid
          AND bt.status = 'success'
          AND abs(bt.amount - v_penalty) <= 0.05
      ) THEN
        RETURN jsonb_build_object('ok', false, 'error', 'penalty_not_paid');
      END IF;
    END IF;
    UPDATE public.user_subscriptions
       SET auto_pay_discount_applied = false,
           auto_renew = false,
           auto_pay_enabled = false,
           auto_pay_card_id = NULL,
           updated_at = now()
     WHERE id = p_subscription_id;
    RETURN jsonb_build_object('ok', true, 'auto_pay_enabled', false, 'penalty_paid', v_penalty);
  END IF;

  IF p_enabled AND p_payment_method_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.saved_cards
       WHERE id = p_payment_method_id AND user_id = v_uid
    ) THEN
      RAISE EXCEPTION 'card_not_found_or_not_owner';
    END IF;
  END IF;

  UPDATE public.user_subscriptions
     SET auto_pay_enabled = p_enabled,
         auto_renew = CASE WHEN v_period = 'yearly' THEN false ELSE p_enabled END,
         auto_pay_card_id = CASE
           WHEN p_enabled THEN coalesce(p_payment_method_id, auto_pay_card_id)
           ELSE NULL END,
         auto_pay_discount_percent = CASE WHEN p_enabled AND v_period = 'monthly' THEN v_pct ELSE 0 END,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'ok', true,
    'auto_pay_enabled', p_enabled,
    'discount_percent', CASE WHEN p_enabled AND v_period = 'monthly' THEN v_pct ELSE 0 END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_subscription_auto_pay(uuid, boolean, uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_subscription_auto_pay(uuid, boolean, uuid, uuid)
  TO authenticated;

-- ── (6) تعطيل شراء المقاعد (نفس توقيع الدالة الأصلي) ───────────────────────

CREATE OR REPLACE FUNCTION public.org_purchase_extra_seats_priced(
  p_extra int,
  p_billing_transaction_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'ok', false,
    'error', 'seats_disabled',
    'message_ar', 'إضافة أعضاء/مقاعد غير متاحة — كل باقة لحساب واحد.',
    'message_en', 'Extra seats are disabled — one account per subscription.'
  );
END;
$$;

-- ── (7) توب-أب صفقات لجميع الأدوار ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public._market_offer_topup_plans_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  starts_at timestamptz,
  ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    p.id,
    coalesce(p.plan_program, 'monthly'),
    coalesce(p.max_market_offers, 0),
    coalesce(s.starts_at, s.start_date::timestamptz),
    coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active','cancelled')
    AND p.sort_order IN (11, 12, 13)
    AND coalesce(p.max_market_offers, 0) > 0
    AND (
      coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC;
$$;

-- ── (8) كتالوج RPC — تحديث الفلتر (بدون تغيير التوقيع) ─────────────────────

CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans()
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

  SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
  INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;

  v_allowed := CASE v_plan_type
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    ELSE ARRAY[1, 11, 12, 13, 14]
  END;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
  INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND sp.user_type = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  IF v_rows IS NULL OR jsonb_array_length(v_rows) = 0 THEN
    SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
    INTO v_rows
    FROM public.subscription_plans sp
    WHERE sp.is_active = true
      AND coalesce(sp.is_trial_plan, false) = false
      AND sp.user_type = v_plan_type;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans()
  TO authenticated, service_role;

COMMIT;
