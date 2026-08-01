-- =============================================================================
-- 2026-06-02 — حراس دورة حياة الاشتراك (v5)
-- =============================================================================
-- الأهداف:
--   1) منع اشتراك جديد عند وجود اشتراك مدفوع فعّال للمستخدم نفسه
--      (الترقية فقط مسموحة عبر RPC `subscription_can_upgrade`).
--   2) عضو الفريق لا يستطيع الاشتراك بنفسه — يستفيد من اشتراك المالك.
--   3) RPC `subscription_quote_for_role`: يعطي العميل
--      ملخّص الباقة الواحدة لدوره + خصم الدفع التلقائي.
--   4) RPC `subscription_offer_cancellation_retention`: يمنح خصم 20% مرّة
--      واحدة لكل مستخدم رئيسي عند ضغطه «إلغاء».
--   5) فهرس فريد جزئي يضمن وجود اشتراك مدفوع نشط واحد فقط لكل user_id.
-- =============================================================================

BEGIN;

-- =============================================================================
-- (A) فهرس فريد جزئي: اشتراك مدفوع نشط واحد لكل (user_id) (التجريبي مستقل)
-- =============================================================================
DROP INDEX IF EXISTS public.user_subscriptions_one_active_paid_per_user;
CREATE UNIQUE INDEX user_subscriptions_one_active_paid_per_user
  ON public.user_subscriptions (user_id)
  WHERE status = 'active'
    AND coalesce(is_trial, false) = false;

-- =============================================================================
-- (B) RPC: subscription_quote_for_role — معلومات الباقة المرئية لدور المستخدم
-- =============================================================================
CREATE OR REPLACE FUNCTION public.subscription_quote_for_role(
  p_period text DEFAULT 'monthly',           -- 'monthly' | 'yearly'
  p_with_auto_pay boolean DEFAULT false      -- يطبق خصم الدفع التلقائي
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at  text;
  v_role_kind text;
  v_target_sort int;
  v_plan record;
  v_base numeric(10,2);
  v_auto_disc numeric(5,2);
  v_after numeric(10,2);
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT lower(trim(coalesce(account_type::text, '')))
    INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;

  IF v_at IS NULL OR v_at = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  v_role_kind := CASE v_at
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office'   THEN 'office'
    WHEN 'agency'   THEN 'office'
    WHEN 'institution' THEN 'institution'
    WHEN 'company'  THEN 'company'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    ELSE v_at
  END;

  v_target_sort := CASE v_role_kind
    WHEN 'marketer' THEN 1
    WHEN 'office' THEN 2
    WHEN 'institution' THEN 2
    WHEN 'company' THEN 3
    WHEN 'individual' THEN 1
    ELSE 1
  END;

  SELECT *
    INTO v_plan
  FROM public.subscription_plans
  WHERE is_active = true
    AND coalesce(is_trial_plan, false) = false
    AND user_type = v_role_kind
    AND sort_order = v_target_sort
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_available_for_role',
                              'role', v_role_kind);
  END IF;

  v_base := CASE lower(coalesce(p_period,'monthly'))
    WHEN 'yearly' THEN v_plan.price_yearly
    ELSE v_plan.price_monthly
  END;

  v_auto_disc := COALESCE(v_plan.auto_pay_discount_percent, 20);

  v_after := CASE WHEN coalesce(p_with_auto_pay, false)
                  THEN round(v_base * (1 - v_auto_disc / 100.0)::numeric, 2)
                  ELSE v_base
             END;

  RETURN jsonb_build_object(
    'ok', true,
    'role', v_role_kind,
    'plan_id', v_plan.id,
    'plan_name_ar', v_plan.name_ar,
    'plan_name_en', v_plan.name_en,
    'period', lower(coalesce(p_period,'monthly')),
    'price_base', v_base,
    'auto_pay_discount_percent', v_auto_disc,
    'with_auto_pay', coalesce(p_with_auto_pay, false),
    'price_after_auto_pay', v_after,
    'max_members', v_plan.max_members,
    'team_member_discount_percent', v_plan.team_member_discount_percent,
    'seat_unit_price_sar', v_plan.seat_unit_price_sar,
    'cancellation_retention_offer_pct', v_plan.cancellation_retention_offer_pct
  );
END;
$$;

REVOKE ALL ON FUNCTION public.subscription_quote_for_role(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_quote_for_role(text, boolean)
  TO authenticated, service_role;

-- =============================================================================
-- (C) RPC: subscription_can_subscribe — قرار «هل يستطيع الاشتراك الآن؟»
--      • false إن كان عضو فريق (يجب أن يكون اشتراك المالك فعّال)
--      • false إن كان لديه اشتراك مدفوع فعّال (يلزم الترقية فقط)
--      • true غير ذلك
-- =============================================================================
CREATE OR REPLACE FUNCTION public.subscription_can_subscribe()
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  -- هل هو عضو ضمن منشأة (ليس مالكاً)؟
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

  -- اشتراك مدفوع فعّال على اسمه
  SELECT s.id, s.plan_id, s.period, s.starts_at, s.ends_at, s.status
    INTO v_self_active
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND coalesce(s.is_trial, false) = false
    AND s.status = 'active'
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ORDER BY s.created_at DESC
  LIMIT 1;

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

REVOKE ALL ON FUNCTION public.subscription_can_subscribe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_can_subscribe()
  TO authenticated, service_role;

-- =============================================================================
-- (D) RPC: subscription_compute_upgrade_charge — لحساب فرق الترقية
--     (يطبّق نفس منطق العميل في subscription_service.computePlanChangeCharge)
--     يعتمد على المتبقي من قيمة الاشتراك الحالي (per-day proration)
--     مقسوم على الفترة، ويعطي الفرق المستحق.
-- =============================================================================
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT *
    INTO v_cur
  FROM public.user_subscriptions
  WHERE user_id = v_uid
    AND status = 'active'
    AND coalesce(is_trial, false) = false
    AND coalesce(ends_at, end_date::timestamptz) > timezone('utc', now())
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

  IF v_new_plan.sort_order <= v_old_plan.sort_order
     AND coalesce(v_new_plan.user_type,'') = coalesce(v_old_plan.user_type,'') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_an_upgrade');
  END IF;

  v_full_old := CASE coalesce(v_cur.period, 'monthly')
                  WHEN 'yearly' THEN v_old_plan.price_yearly
                  ELSE v_old_plan.price_monthly END;
  v_full_new := CASE lower(coalesce(p_target_period,'monthly'))
                  WHEN 'yearly' THEN v_new_plan.price_yearly
                  ELSE v_new_plan.price_monthly END;

  v_total_days := greatest(1, (v_cur.end_date - v_cur.start_date));
  v_used_days  := greatest(0, (current_date - v_cur.start_date));
  v_remaining_days := greatest(0, v_total_days - v_used_days);
  v_credit := round((v_full_old * v_remaining_days::numeric) / v_total_days::numeric, 2);
  v_due    := greatest(0, round(v_full_new - v_credit, 2));

  RETURN jsonb_build_object(
    'ok', true,
    'old_plan_id', v_old_plan.id,
    'new_plan_id', v_new_plan.id,
    'period', lower(coalesce(p_target_period,'monthly')),
    'full_old_price', v_full_old,
    'full_new_price', v_full_new,
    'total_days', v_total_days,
    'remaining_days', v_remaining_days,
    'credit_from_remaining', v_credit,
    'amount_due', v_due
  );
END;
$$;

REVOKE ALL ON FUNCTION public.subscription_compute_upgrade_charge(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_compute_upgrade_charge(uuid, text)
  TO authenticated, service_role;

-- =============================================================================
-- (E) RPC: subscription_offer_cancellation_retention
--     عرض «استبقاء» مرّة واحدة لكل مالك اشتراك (لا يظهر للأعضاء).
--     • إذا لم يستهلكه من قبل → يُرجع pct + يحجزه (consumed_at).
--     • إن سبق له الاستفادة → يُرجع already_used.
--     • إن كان عضو فريق → يُرجع team_member_not_eligible.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.subscription_offer_cancellation_retention(
  p_subscription_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sub record;
  v_plan record;
  v_member_count int;
  v_used record;
  v_pct numeric(5,2);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- منع أعضاء الفريق
  SELECT count(*)
    INTO v_member_count
  FROM public.org_memberships m
  JOIN public.org_units o ON o.id = m.org_id
  WHERE m.user_id = v_uid
    AND m.status = 'active'
    AND coalesce(m.member_role,'') <> 'owner'
    AND o.owner_user_id <> v_uid;

  IF v_member_count > 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'team_member_not_eligible');
  END IF;

  SELECT *
    INTO v_sub
  FROM public.user_subscriptions
  WHERE id = p_subscription_id
    AND user_id = v_uid
  FOR UPDATE;

  IF v_sub.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'subscription_not_found');
  END IF;

  IF coalesce(v_sub.is_trial, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_not_eligible');
  END IF;

  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = v_sub.plan_id;
  v_pct := COALESCE(v_plan.cancellation_retention_offer_pct, 20.0);

  -- هل سبق وقدّمنا له العرض؟
  SELECT * INTO v_used
  FROM public.user_retention_offers_consumed
  WHERE user_id = v_uid;

  IF v_used.user_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'available', false,
      'reason', 'already_used',
      'used_at', v_used.consumed_at,
      'pct_applied_previously', v_used.pct_applied
    );
  END IF;

  -- نسجّل العرض (يُحجز فور العرض ليمنع التكرار من نوافذ متعددة).
  INSERT INTO public.user_retention_offers_consumed (
    user_id, subscription_id, pct_applied
  )
  VALUES (v_uid, p_subscription_id, v_pct);

  RETURN jsonb_build_object(
    'ok', true,
    'available', true,
    'discount_percent', v_pct,
    'subscription_id', p_subscription_id,
    'one_time_offer', true,
    'note', 'يُطبّق على فاتورة التجديد التالية إن قبِله المستخدم.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.subscription_offer_cancellation_retention(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_offer_cancellation_retention(uuid)
  TO authenticated, service_role;

-- =============================================================================
-- (F) RPC: team_member_paid_feature_gate — للأمام يقرأها العميل/RPCs.
--     يُرجع: { ok, allow, reason, owner_subscription_active }
-- =============================================================================
CREATE OR REPLACE FUNCTION public.team_member_paid_feature_gate()
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
  v_self_active boolean := false;
  v_is_team_member boolean := false;
  v_member_role text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
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

  SELECT EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND s.status IN ('active','cancelled')
      AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ) INTO v_self_active;

  IF v_is_team_member AND v_owner IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner
        AND s.status IN ('active','cancelled')
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    ) INTO v_owner_active;
  END IF;

  IF v_is_team_member THEN
    RETURN jsonb_build_object(
      'ok', true,
      'is_team_member', true,
      'allow', v_owner_active,
      'owner_user_id', v_owner,
      'owner_subscription_active', v_owner_active,
      'reason', CASE WHEN v_owner_active THEN 'owner_active' ELSE 'owner_inactive' END
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'is_team_member', false,
    'allow', v_self_active,
    'reason', CASE WHEN v_self_active THEN 'self_active' ELSE 'self_inactive' END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.team_member_paid_feature_gate() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.team_member_paid_feature_gate()
  TO authenticated, service_role;

-- =============================================================================
-- (G) محاذاة الـRPCs القديمة مع نسبة 20% الجديدة + منع أعضاء الفريق
-- =============================================================================

-- (G.1) set_subscription_auto_pay: استخدم نسبة الخطة بدل 5% الثابتة.
CREATE OR REPLACE FUNCTION public.set_subscription_auto_pay(
  p_subscription_id uuid,
  p_enabled boolean,
  p_payment_method_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sub public.user_subscriptions%ROWTYPE;
  v_pct numeric(5,2);
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

  IF p_enabled AND p_payment_method_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.saved_cards
       WHERE id = p_payment_method_id AND user_id = v_uid
    ) THEN
      RAISE EXCEPTION 'card_not_found_or_not_owner';
    END IF;
  END IF;

  SELECT coalesce(auto_pay_discount_percent, 20.0)
    INTO v_pct
  FROM public.subscription_plans
  WHERE id = v_sub.plan_id;
  IF v_pct IS NULL THEN v_pct := 20.0; END IF;

  UPDATE public.user_subscriptions
     SET auto_pay_enabled = p_enabled,
         auto_pay_card_id = CASE
           WHEN p_enabled THEN coalesce(p_payment_method_id, auto_pay_card_id)
           ELSE NULL END,
         auto_pay_discount_percent = CASE WHEN p_enabled THEN v_pct ELSE 0 END,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'ok', true,
    'auto_pay_enabled', p_enabled,
    'discount_percent', CASE WHEN p_enabled THEN v_pct ELSE 0 END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_subscription_auto_pay(uuid, boolean, uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_subscription_auto_pay(uuid, boolean, uuid)
  TO authenticated;

-- (G.2) request_subscription_cancellation: امنع أعضاء الفريق + استخدم 20%.
CREATE OR REPLACE FUNCTION public.request_subscription_cancellation(
  p_subscription_id uuid,
  p_reason_code text,
  p_reason_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sub public.user_subscriptions%ROWTYPE;
  v_request_id uuid;
  v_eligible_for_retention boolean;
  v_eff timestamptz;
  v_pct numeric(5,2);
  v_team_member_count int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT count(*) INTO v_team_member_count
    FROM public.org_memberships m
    JOIN public.org_units o ON o.id = m.org_id
   WHERE m.user_id = v_uid
     AND m.status = 'active'
     AND coalesce(m.member_role,'') <> 'owner'
     AND o.owner_user_id <> v_uid;

  SELECT * INTO v_sub FROM public.user_subscriptions
   WHERE id = p_subscription_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'subscription_not_found_or_not_owner'; END IF;

  IF coalesce(v_sub.status,'') NOT IN ('active','pending') THEN
    RAISE EXCEPTION 'subscription_not_cancellable';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.subscription_cancellation_reasons
     WHERE code = p_reason_code AND is_active = true
  ) THEN
    RAISE EXCEPTION 'invalid_reason_code: %', p_reason_code;
  END IF;

  SELECT coalesce(cancellation_retention_offer_pct, 20.0)
    INTO v_pct
  FROM public.subscription_plans
  WHERE id = v_sub.plan_id;
  IF v_pct IS NULL THEN v_pct := 20.0; END IF;

  -- استبقاء يُعرَض مرة واحدة فقط لكل مالك (وليس لعضو فريق).
  v_eligible_for_retention := (
    v_team_member_count = 0
    AND v_sub.retention_discount_used_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.user_retention_offers_consumed
       WHERE user_id = v_uid
    )
  );
  v_eff := coalesce(v_sub.ends_at, v_sub.end_date::timestamptz, now());

  INSERT INTO public.subscription_cancellation_requests
    (subscription_id, user_id, reason_code, reason_note,
     retention_offered, effective_at)
  VALUES
    (p_subscription_id, v_uid, p_reason_code, p_reason_note,
     v_eligible_for_retention, v_eff)
  RETURNING id INTO v_request_id;

  UPDATE public.user_subscriptions
     SET cancellation_requested_at = now(),
         cancellation_reason_code = p_reason_code,
         cancellation_reason_note = p_reason_note,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', v_request_id,
    'is_team_member', v_team_member_count > 0,
    'retention_offer', CASE WHEN v_eligible_for_retention THEN
      jsonb_build_object(
        'available', true,
        'discount_percent', v_pct,
        'message_ar', 'هل تودّ البقاء معنا بخصم ' || v_pct::text ||
                       '٪ على فاتورتك القادمة؟ يُمنح هذا الخصم لمرّة واحدة فقط.',
        'message_en', 'Stay with us and get ' || v_pct::text ||
                       '% off your next bill. One-time courtesy discount.'
      )
      ELSE jsonb_build_object('available', false)
    END,
    'effective_at', v_eff,
    'note_ar', 'بعد التأكيد سيوقف التجديد التلقائي، وستبقى باقتك فعَّالة حتى انتهاء المدة المدفوعة.',
    'note_en', 'On confirmation, auto-renewal stops; your plan remains active until the paid period ends.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_subscription_cancellation(uuid, text, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_subscription_cancellation(uuid, text, text)
  TO authenticated;

-- (G.3) confirm_subscription_cancellation: استخدم 20% من الخطة + سجّل في
--       user_retention_offers_consumed عند قبول الاستبقاء.
CREATE OR REPLACE FUNCTION public.confirm_subscription_cancellation(
  p_request_id uuid,
  p_accept_retention boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.subscription_cancellation_requests%ROWTYPE;
  v_sub public.user_subscriptions%ROWTYPE;
  v_pct numeric(5,2);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT * INTO v_req FROM public.subscription_cancellation_requests
   WHERE id = p_request_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'cancellation_request_not_found'; END IF;

  SELECT * INTO v_sub FROM public.user_subscriptions
   WHERE id = v_req.subscription_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'subscription_missing'; END IF;

  SELECT coalesce(cancellation_retention_offer_pct, 20.0)
    INTO v_pct
  FROM public.subscription_plans
  WHERE id = v_sub.plan_id;
  IF v_pct IS NULL THEN v_pct := 20.0; END IF;

  IF p_accept_retention AND v_req.retention_offered THEN
    UPDATE public.user_subscriptions
       SET cancellation_requested_at = NULL,
           cancellation_reason_code = NULL,
           cancellation_reason_note = NULL,
           cancellation_effective_at = NULL,
           retention_discount_used_at = now(),
           retention_discount_percent = v_pct,
           updated_at = now()
     WHERE id = v_sub.id;

    INSERT INTO public.user_retention_offers_consumed (
      user_id, subscription_id, pct_applied
    )
    VALUES (v_uid, v_sub.id, v_pct)
    ON CONFLICT (user_id) DO NOTHING;

    UPDATE public.subscription_cancellation_requests
       SET retention_accepted = true
     WHERE id = v_req.id;

    RETURN jsonb_build_object(
      'ok', true,
      'cancelled', false,
      'retention_applied', true,
      'discount_percent', v_pct,
      'message_ar', 'تم إلغاء الإلغاء وتطبيق خصم ' || v_pct::text ||
                     '٪ على فاتورتك القادمة.',
      'message_en', v_pct::text || '% courtesy discount applied to your next bill. Cancellation reverted.'
    );
  END IF;

  UPDATE public.user_subscriptions
     SET status = 'cancelled',
         auto_pay_enabled = false,
         auto_pay_card_id = NULL,
         auto_pay_discount_percent = 0,
         cancellation_effective_at = coalesce(ends_at, end_date::timestamptz),
         cancelled_at = now(),
         updated_at = now()
   WHERE id = v_sub.id;

  UPDATE public.subscription_cancellation_requests
     SET retention_accepted = false
   WHERE id = v_req.id;

  RETURN jsonb_build_object(
    'ok', true,
    'cancelled', true,
    'effective_at', coalesce(v_sub.ends_at, v_sub.end_date::timestamptz),
    'message_ar', 'تم إيقاف التجديد التلقائي. ستبقى الباقة فعَّالة حتى نهاية المدة المدفوعة.',
    'message_en', 'Auto-renewal stopped. Your plan stays active until the paid period ends.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_subscription_cancellation(uuid, boolean)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_subscription_cancellation(uuid, boolean)
  TO authenticated;

COMMIT;

-- =============================================================================
-- ملاحظات تشغيل:
--   • تأكد من أن subscription_can_subscribe + team_member_paid_feature_gate
--     يُستدعيان من العميل قبل بدء أي عمليّة دفع/ميزة مدفوعة.
--   • الفهرس الفريد user_subscriptions_one_active_paid_per_user يضمن طبقة DB
--     ضد الاشتراك المكرّر، حتى لو فشل العميل في الفحص.
-- =============================================================================
