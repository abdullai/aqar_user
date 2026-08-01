-- =============================================================================
-- نظام دفع تلقائي + إلغاء عادل + استبقاء (1 × 5%)
--   • تفعيل الدفع التلقائي → خصم 5% فوق أي خصم آخر (شهري/سنوي).
--   • الإلغاء يُسجَّل سبباً ويوقف الدفع التلقائي.
--   • تبقى الباقة فعَّالة حتى نهاية المدة المدفوعة (لا ظلم).
--   • يحقّ للمستخدم خصم استبقاء 5% لمرة واحدة فقط (إن لم يستمرّ في الإلغاء).
--   • تصحيح market_offer_unified_allowance لحالة عدم المصادقة → رد آمن.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (1) أعمدة الدفع التلقائي والاستبقاء على user_subscriptions
-- ---------------------------------------------------------------------------
ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS auto_pay_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_pay_card_id uuid
    REFERENCES public.saved_cards (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS auto_pay_discount_percent numeric(5,2)
    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS retention_discount_used_at timestamptz,
  ADD COLUMN IF NOT EXISTS retention_discount_percent numeric(5,2)
    NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cancellation_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_reason_code text,
  ADD COLUMN IF NOT EXISTS cancellation_reason_note text,
  ADD COLUMN IF NOT EXISTS cancellation_effective_at timestamptz,
  ADD COLUMN IF NOT EXISTS starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS ends_at timestamptz;

-- مؤشّرات لاستعلامات الـRPC
CREATE INDEX IF NOT EXISTS idx_user_subs_auto_pay
  ON public.user_subscriptions (user_id, auto_pay_enabled);
CREATE INDEX IF NOT EXISTS idx_user_subs_cancellation
  ON public.user_subscriptions (cancellation_requested_at);

-- ---------------------------------------------------------------------------
-- (2) جدول طلبات الإلغاء (للأرشيف ومساعدة الدعم الفني)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_cancellation_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id uuid NOT NULL
    REFERENCES public.user_subscriptions (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  reason_code text NOT NULL,
  reason_note text,
  retention_offered boolean NOT NULL DEFAULT false,
  retention_accepted boolean,
  effective_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sub_cancel_user
  ON public.subscription_cancellation_requests (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sub_cancel_subscription
  ON public.subscription_cancellation_requests (subscription_id);

ALTER TABLE public.subscription_cancellation_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sub_cancel_owner_select
  ON public.subscription_cancellation_requests;
CREATE POLICY sub_cancel_owner_select
  ON public.subscription_cancellation_requests FOR SELECT
  USING (user_id = auth.uid());

-- لا نسمح بالكتابة المباشرة إلا عبر الدوال SECURITY DEFINER

-- ---------------------------------------------------------------------------
-- (3) أسباب الإلغاء (مرجع نصيّ للواجهة)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscription_cancellation_reasons (
  code text PRIMARY KEY,
  label_ar text NOT NULL,
  label_en text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true
);

INSERT INTO public.subscription_cancellation_reasons
  (code, label_ar, label_en, sort_order)
VALUES
  ('price_too_high','الباقة تفوق احتياجي حالياً','Plan exceeds my current need',1),
  ('not_using','لا أستخدم الخدمة بشكل كافٍ','I''m not using the service enough',2),
  ('found_alternative','وجدت بديلاً مناسباً','I found a better alternative',3),
  ('technical_issue','واجهت مشاكل تقنية','I experienced technical issues',4),
  ('temporary_pause','أحتاج إيقافاً مؤقتاً','I need a temporary pause',5),
  ('change_business','تغيّر نشاطي/خطتي','My business or plans changed',6),
  ('other','سبب آخر','Other',99)
ON CONFLICT (code) DO UPDATE SET
  label_ar = EXCLUDED.label_ar,
  label_en = EXCLUDED.label_en,
  sort_order = EXCLUDED.sort_order,
  is_active = true;

ALTER TABLE public.subscription_cancellation_reasons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cancel_reasons_read
  ON public.subscription_cancellation_reasons;
CREATE POLICY cancel_reasons_read
  ON public.subscription_cancellation_reasons FOR SELECT
  USING (true);

-- ---------------------------------------------------------------------------
-- (4) قوائم: تشغيل/إيقاف الدفع التلقائي
-- ---------------------------------------------------------------------------
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

  UPDATE public.user_subscriptions
     SET auto_pay_enabled = p_enabled,
         auto_pay_card_id = CASE
           WHEN p_enabled THEN coalesce(p_payment_method_id, auto_pay_card_id)
           ELSE NULL END,
         auto_pay_discount_percent = CASE WHEN p_enabled THEN 5.00 ELSE 0 END,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'ok', true,
    'auto_pay_enabled', p_enabled,
    'discount_percent', CASE WHEN p_enabled THEN 5.00 ELSE 0 END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_subscription_auto_pay(uuid, boolean, uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_subscription_auto_pay(uuid, boolean, uuid)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- (5) عرض السعر مع الخصومات (يساعد الواجهة قبل الدفع)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.compute_plan_quote(
  p_plan_id uuid,
  p_period text DEFAULT 'monthly',
  p_with_auto_pay boolean DEFAULT false,
  p_apply_retention_discount boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan public.subscription_plans%ROWTYPE;
  v_base numeric(10,2);
  v_yearly_base numeric(10,2);
  v_period text := lower(coalesce(p_period,'monthly'));
  v_auto_pay_disc numeric(5,2) := 0;
  v_retention_disc numeric(5,2) := 0;
  v_yearly_disc numeric(5,2) := 0;
  v_subtotal numeric(10,2);
  v_total numeric(10,2);
  v_disc_total numeric(10,2);
BEGIN
  SELECT * INTO v_plan FROM public.subscription_plans
   WHERE id = p_plan_id AND is_active = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'plan_not_found';
  END IF;

  -- baseline: الشهري الافتراضي
  v_base := coalesce(v_plan.price_monthly, 0);

  IF v_period = 'yearly' THEN
    v_yearly_base := coalesce(v_plan.price_yearly, v_base * 12);
    v_subtotal := v_yearly_base;
    -- خصم سنوي ضمنيّ 20% (مدمج في price_yearly)؛ نحسبه للعرض فقط:
    IF v_base > 0 THEN
      v_yearly_disc := round(((v_base * 12 - v_yearly_base) / (v_base * 12)) * 100.0, 2);
      IF v_yearly_disc < 0 THEN v_yearly_disc := 0; END IF;
    END IF;
  ELSIF v_period = 'lifetime_one_time' THEN
    v_subtotal := v_base;
  ELSE
    v_subtotal := v_base;
  END IF;

  IF p_with_auto_pay THEN v_auto_pay_disc := 5.00; END IF;
  IF p_apply_retention_discount THEN v_retention_disc := 5.00; END IF;

  v_disc_total := v_auto_pay_disc + v_retention_disc;
  v_total := round(v_subtotal * (1 - (v_disc_total / 100.0)), 2);

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', v_plan.id,
    'period', v_period,
    'base', v_base,
    'subtotal', v_subtotal,
    'auto_pay_discount_percent', v_auto_pay_disc,
    'retention_discount_percent', v_retention_disc,
    'yearly_implicit_discount_percent', v_yearly_disc,
    'total_discount_percent', v_disc_total,
    'total_due', v_total,
    'savings', round(v_subtotal - v_total, 2)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_plan_quote(uuid, text, boolean, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_plan_quote(uuid, text, boolean, boolean)
  TO authenticated, anon;

-- ---------------------------------------------------------------------------
-- (6) طلب إلغاء الاشتراك مع الأسباب — الخطوة 1 (يَعرض استبقاء)
-- ---------------------------------------------------------------------------
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
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

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

  -- استبقاء يُعرَض مرة واحدة فقط لكل مستخدم على هذه الباقة
  v_eligible_for_retention := v_sub.retention_discount_used_at IS NULL;
  v_eff := coalesce(v_sub.ends_at, v_sub.end_date::timestamptz, now());

  INSERT INTO public.subscription_cancellation_requests
    (subscription_id, user_id, reason_code, reason_note,
     retention_offered, effective_at)
  VALUES
    (p_subscription_id, v_uid, p_reason_code, p_reason_note,
     v_eligible_for_retention, v_eff)
  RETURNING id INTO v_request_id;

  -- يبقى الاشتراك فعَّالاً — لا نُلغي قبل اتخاذ قرار الاستبقاء.
  UPDATE public.user_subscriptions
     SET cancellation_requested_at = now(),
         cancellation_reason_code = p_reason_code,
         cancellation_reason_note = p_reason_note,
         updated_at = now()
   WHERE id = p_subscription_id;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', v_request_id,
    'retention_offer', CASE WHEN v_eligible_for_retention THEN
      jsonb_build_object(
        'available', true,
        'discount_percent', 5.00,
        'message_ar', 'هل تودّ البقاء معنا بخصم 5٪ على فاتورتك القادمة؟ يُمنح هذا الخصم لمرّة واحدة فقط ومن غير شروط.',
        'message_en', 'Stay with us and get 5% off your next bill. One-time courtesy discount, no strings attached.'
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

-- ---------------------------------------------------------------------------
-- (7) تأكيد الإلغاء — الخطوة 2 (يقبل الاستبقاء أو يُكمل الإلغاء)
-- ---------------------------------------------------------------------------
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
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;

  SELECT * INTO v_req FROM public.subscription_cancellation_requests
   WHERE id = p_request_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'cancellation_request_not_found'; END IF;

  SELECT * INTO v_sub FROM public.user_subscriptions
   WHERE id = v_req.subscription_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'subscription_missing'; END IF;

  IF p_accept_retention AND v_req.retention_offered THEN
    -- استبقاء: نعطيه 5% لمرة واحدة، نعكس طلب الإلغاء
    UPDATE public.user_subscriptions
       SET cancellation_requested_at = NULL,
           cancellation_reason_code = NULL,
           cancellation_reason_note = NULL,
           cancellation_effective_at = NULL,
           retention_discount_used_at = now(),
           retention_discount_percent = 5.00,
           updated_at = now()
     WHERE id = v_sub.id;

    UPDATE public.subscription_cancellation_requests
       SET retention_accepted = true
     WHERE id = v_req.id;

    RETURN jsonb_build_object(
      'ok', true,
      'cancelled', false,
      'retention_applied', true,
      'discount_percent', 5.00,
      'message_ar', 'تم إلغاء الإلغاء وتطبيق خصم 5٪ على فاتورتك القادمة.',
      'message_en', '5% courtesy discount applied to your next bill. Cancellation reverted.'
    );
  END IF;

  -- إلغاء فعلي: نوقف الدفع التلقائي ونبقي الباقة حتى ends_at
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

-- ---------------------------------------------------------------------------
-- (8) تصحيح market_offer_unified_allowance: رد آمن لغير المصادق
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.market_offer_unified_allowance(
  p_organization_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bill_uid uuid;
  v_at text;
  v_is_marketing boolean := false;
  v_main_record record;
  v_topup record;
  v_main_max int := 0;
  v_main_used int := 0;
  v_main_period_start date;
  v_main_period_end date;
  v_main_lifetime boolean := false;
  v_main_unlimited boolean := false;
  v_topup_max int := 0;
  v_topup_used int := 0;
  v_total_max int := 0;
  v_total_used int := 0;
  v_main_program text;
  v_main_is_trial boolean := false;
  v_topup_records jsonb := '[]'::jsonb;
BEGIN
  -- رد آمن لمن استدعى الدالة بلا جلسة (مثلاً من SQL Editor) بدل خطأ.
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'authenticated', false,
      'audience', 'guest',
      'has_subscription', false,
      'has_main_plan', false,
      'main', NULL,
      'topups', '[]'::jsonb,
      'total_used', 0,
      'total_max', 0,
      'total_remaining', 0,
      'unlimited', false,
      'needs_paywall', true,
      'note', 'auth_required: يجب استدعاء الدالة من جلسة مسجَّلة'
    );
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'user')
  INTO v_at FROM public.users_profiles WHERE user_id = v_uid;

  v_is_marketing := lower(coalesce(v_at, '')) IN
    ('marketer','office','institution','company','agency');

  v_bill_uid := v_uid;
  IF v_is_marketing THEN
    IF p_organization_id IS NOT NULL THEN
      SELECT o.owner_user_id INTO v_bill_uid
        FROM public.org_units o WHERE o.id = p_organization_id LIMIT 1;
      IF v_bill_uid IS NULL THEN v_bill_uid := v_uid; END IF;
    ELSE
      SELECT o.owner_user_id INTO v_bill_uid
        FROM public.org_memberships m
        JOIN public.org_units o ON o.id = m.org_id
       WHERE m.user_id = v_uid AND m.status = 'active'
       ORDER BY m.created_at DESC LIMIT 1;
      IF v_bill_uid IS NULL THEN v_bill_uid := v_uid; END IF;
    END IF;
  END IF;

  IF v_is_marketing THEN
    SELECT * INTO v_main_record
      FROM public._marketing_active_plan_for_uid(v_bill_uid);
    IF v_main_record.plan_id IS NOT NULL THEN
      v_main_program := v_main_record.plan_program;
      v_main_is_trial := v_main_record.is_trial;
      IF v_main_record.is_trial OR v_main_record.max_count IS NULL THEN
        v_main_unlimited := true;
        v_main_max := 999999;
      ELSE
        v_main_max := coalesce(v_main_record.max_count, 0);
      END IF;
      v_main_lifetime := (v_main_record.plan_program = 'lifetime_one_time');
      SELECT pb.period_start, pb.period_end
        INTO v_main_period_start, v_main_period_end
        FROM public._offer_quota_period_bounds(
          v_main_record.starts_at, v_main_record.plan_program
        ) pb;
      IF NOT v_main_unlimited THEN
        v_main_used := public._count_offer_usage_for_user(
          v_bill_uid, v_main_record.subscription_id,
          v_main_period_start, v_main_lifetime
        );
      END IF;
    END IF;
  END IF;

  FOR v_topup IN
    SELECT * FROM public._market_offer_topup_plans_for_uid(v_uid)
  LOOP
    DECLARE
      v_t_period_start date;
      v_t_period_end date;
      v_t_used int;
      v_t_lifetime boolean := (v_topup.plan_program = 'lifetime_one_time');
    BEGIN
      SELECT pb.period_start, pb.period_end
        INTO v_t_period_start, v_t_period_end
        FROM public._offer_quota_period_bounds(
          v_topup.starts_at, v_topup.plan_program
        ) pb;
      v_t_used := public._count_offer_usage_for_user(
        v_uid, v_topup.subscription_id, v_t_period_start, v_t_lifetime
      );
      v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
      v_topup_used := v_topup_used + coalesce(v_t_used, 0);
      v_topup_records := v_topup_records || jsonb_build_object(
        'subscription_id', v_topup.subscription_id,
        'plan_id', v_topup.plan_id,
        'plan_program', v_topup.plan_program,
        'max', v_topup.max_count,
        'used', v_t_used,
        'remaining', greatest(0, v_topup.max_count - coalesce(v_t_used, 0)),
        'period_start', v_t_period_start,
        'period_end', v_t_period_end,
        'starts_at', v_topup.starts_at,
        'ends_at', v_topup.ends_at
      );
    END;
  END LOOP;

  IF v_main_unlimited THEN
    v_total_max := 999999;
  ELSE
    v_total_max := v_main_max + v_topup_max;
  END IF;
  v_total_used := v_main_used + v_topup_used;

  RETURN jsonb_build_object(
    'ok', true,
    'authenticated', true,
    'audience', CASE WHEN v_is_marketing THEN 'marketing' ELSE 'individual' END,
    'has_subscription', (v_main_record.plan_id IS NOT NULL OR v_topup_max > 0),
    'has_main_plan', v_main_record.plan_id IS NOT NULL,
    'main', CASE
      WHEN v_main_record.plan_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'subscription_id', v_main_record.subscription_id,
        'plan_id', v_main_record.plan_id,
        'plan_program', v_main_program,
        'is_trial', v_main_is_trial,
        'unlimited', v_main_unlimited,
        'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
        'used', v_main_used,
        'remaining', CASE WHEN v_main_unlimited THEN NULL
          ELSE greatest(0, v_main_max - v_main_used) END,
        'period_start', v_main_period_start,
        'period_end', v_main_period_end,
        'starts_at', v_main_record.starts_at,
        'ends_at', v_main_record.ends_at
      )
    END,
    'topups', v_topup_records,
    'total_used', v_total_used,
    'total_max', CASE WHEN v_main_unlimited THEN NULL ELSE v_total_max END,
    'total_remaining', CASE
      WHEN v_main_unlimited THEN NULL
      ELSE greatest(0, v_total_max - v_total_used) END,
    'unlimited', v_main_unlimited,
    'needs_paywall', (NOT v_main_unlimited AND v_total_used >= v_total_max),
    'billing_user_id', v_bill_uid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.market_offer_unified_allowance(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_offer_unified_allowance(uuid)
  TO authenticated, service_role, anon;

COMMIT;
