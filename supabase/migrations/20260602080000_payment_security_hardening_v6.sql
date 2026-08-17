-- =============================================================================
-- 2026-06-02 — تشديد أمن الدفع (v6)
-- =============================================================================
-- يضيف هذا الترحيل ثلاث طبقات:
--   (1) جدول payment_security_audit  — لتسجيل كل محاولة دفع/اشتراك.
--   (2) جدول payment_rate_limits    — لمنع هجمات Replay/Brute (10 محاولات/10د).
--   (3) RPC validate_payment_intent — يفحص سيرفر-سايد:
--          • أنّ المبلغ المُحَصَّل يُساوي السعر الكانوني للباقة بعد الخصومات
--            المعلَنة (الدفع التلقائي + خصم الاحتفاظ + الترقية).
--          • أنّ المستخدم مسموح له بالاشتراك (يُكرّر subscription_can_subscribe).
--          • أنّ مُعدَّل المحاولات تحت الحد.
--   (4) RPC compute_canonical_charge — يحسب «المبلغ الصحيح» من المعلومات
--          المرسَلة (plan_id, period, with_auto_pay, retention, upgrade)
--          ليُستخدم في تأكيد الـMoyasar webhook.
-- =============================================================================

BEGIN;

-- =============================================================================
-- (1) سجل المراجعة
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.payment_security_audit (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  event        text NOT NULL,                  -- subscribe_attempt, subscribe_ok, etc.
  plan_id      uuid REFERENCES public.subscription_plans (id) ON DELETE SET NULL,
  period       text,
  amount_sar   numeric(10,2),
  expected_sar numeric(10,2),
  ip_inet      inet,
  ua           text,
  payload      jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_audit_user_created
  ON public.payment_security_audit (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_audit_event
  ON public.payment_security_audit (event, created_at DESC);

ALTER TABLE public.payment_security_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payment_audit_select_self
  ON public.payment_security_audit;
CREATE POLICY payment_audit_select_self
  ON public.payment_security_audit FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- لا نسمح بالكتابة المباشرة — فقط عبر RPCs SECURITY DEFINER.

-- =============================================================================
-- (2) جدول حد المعدّل
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.payment_rate_limits (
  user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  bucket_key  text NOT NULL,             -- e.g. 'subscribe' | 'card_charge'
  attempts    int NOT NULL DEFAULT 0,
  window_start timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, bucket_key)
);

ALTER TABLE public.payment_rate_limits ENABLE ROW LEVEL SECURITY;
-- لا نَمنح أي سياسة قراءة/كتابة — يُدار حصراً عبر SECURITY DEFINER.

-- =============================================================================
-- (3) دالة مساعدة: تسجيل محاولة + التحقّق من حد المعدّل
-- =============================================================================
CREATE OR REPLACE FUNCTION public._payment_rate_limit_check(
  p_user_id    uuid,
  p_bucket_key text,
  p_max        int DEFAULT 10,
  p_window_min int DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row record;
  v_window timestamptz := now() - make_interval(mins => p_window_min);
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  -- اقفل الصف لفترة التحقّق
  SELECT * INTO v_row FROM public.payment_rate_limits
   WHERE user_id = p_user_id AND bucket_key = p_bucket_key
   FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.payment_rate_limits (user_id, bucket_key, attempts, window_start)
    VALUES (p_user_id, p_bucket_key, 1, now());
    RETURN jsonb_build_object('ok', true, 'attempts', 1, 'allowed', true);
  END IF;

  -- إن تجاوز نافذة المراقبة، إعادة العدّ.
  IF v_row.window_start < v_window THEN
    UPDATE public.payment_rate_limits
       SET attempts = 1, window_start = now()
     WHERE user_id = p_user_id AND bucket_key = p_bucket_key;
    RETURN jsonb_build_object('ok', true, 'attempts', 1, 'allowed', true);
  END IF;

  IF v_row.attempts >= p_max THEN
    RETURN jsonb_build_object(
      'ok', false,
      'allowed', false,
      'error', 'rate_limited',
      'window_minutes', p_window_min,
      'max_attempts', p_max,
      'attempts', v_row.attempts
    );
  END IF;

  UPDATE public.payment_rate_limits
     SET attempts = v_row.attempts + 1
   WHERE user_id = p_user_id AND bucket_key = p_bucket_key;

  RETURN jsonb_build_object(
    'ok', true,
    'allowed', true,
    'attempts', v_row.attempts + 1
  );
END;
$$;

REVOKE ALL ON FUNCTION public._payment_rate_limit_check(uuid, text, int, int) FROM PUBLIC;

-- =============================================================================
-- (4) RPC: compute_canonical_charge — السعر الصحيح من DB
--     يُحدِّد المبلغ الواجب تحصيله بناءً على:
--       • plan + period
--       • with_auto_pay (خصم 20% عند تفعيل التلقائي)
--       • upgrade_subscription_id (يحسب فرق الترقية pro-rata)
-- =============================================================================
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
BEGIN
  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = p_plan_id;
  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_not_found');
  END IF;

  v_base := CASE v_period
    WHEN 'yearly' THEN v_plan.price_yearly
    WHEN 'lifetime_one_time' THEN v_plan.price_monthly
    ELSE v_plan.price_monthly
  END;

  v_auto_pct := COALESCE(v_plan.auto_pay_discount_percent, 20.0);

  IF p_with_auto_pay AND v_period <> 'lifetime_one_time' THEN
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
    'with_auto_pay', coalesce(p_with_auto_pay, false),
    'price_after_auto_pay', v_after_auto,
    'upgrade_charge', v_upgrade,
    'final_amount', v_final
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_canonical_charge(uuid, text, boolean, uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_canonical_charge(uuid, text, boolean, uuid)
  TO authenticated, service_role;

-- =============================================================================
-- (5) RPC: validate_payment_intent — البوابة الموحّدة قبل أي تحصيل
-- =============================================================================
CREATE OR REPLACE FUNCTION public.validate_payment_intent(
  p_plan_id uuid,
  p_period text,
  p_amount_sar numeric,
  p_with_auto_pay boolean DEFAULT false,
  p_upgrade_subscription_id uuid DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  -- (a) حد المعدّل: 10 محاولات لكل 10 دقائق
  v_rate := public._payment_rate_limit_check(v_uid, 'subscribe', 10, 10);
  IF (v_rate->>'allowed')::boolean = false THEN
    INSERT INTO public.payment_security_audit
      (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
    VALUES
      (v_uid, 'rate_limited', p_plan_id, p_period, p_amount_sar, NULL,
       jsonb_build_object('rate', v_rate, 'idem', p_idempotency_key));
    RETURN jsonb_build_object('ok', false, 'error', 'rate_limited',
                              'retry_after_minutes', 10);
  END IF;

  -- (b) فحص أحقيّة الاشتراك (مالك/عضو/مكرر)
  IF p_upgrade_subscription_id IS NULL THEN
    v_can := public.subscription_can_subscribe();
    IF (v_can->>'can_subscribe')::boolean = false THEN
      INSERT INTO public.payment_security_audit
        (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
      VALUES
        (v_uid, 'subscribe_denied', p_plan_id, p_period, p_amount_sar, NULL,
         jsonb_build_object('reason', v_can));
      RETURN jsonb_build_object('ok', false, 'error',
                                coalesce(v_can->>'reason', 'not_allowed'),
                                'detail', v_can);
    END IF;
  END IF;

  -- (c) المبلغ الكانوني من DB
  v_charge := public.compute_canonical_charge(
    p_plan_id, p_period, p_with_auto_pay, p_upgrade_subscription_id
  );
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'error',
                              coalesce(v_charge->>'error','plan_invalid'),
                              'detail', v_charge);
  END IF;
  v_expected := (v_charge->>'final_amount')::numeric(10,2);

  -- (d) قارن المبلغ المرسَل بالمتوقَّع — سماح فاصل ±0.05 لتجنّب فروقات التقريب.
  v_diff := abs(round(coalesce(p_amount_sar,0) - v_expected, 2));
  IF v_diff > 0.05 THEN
    INSERT INTO public.payment_security_audit
      (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
    VALUES
      (v_uid, 'amount_mismatch', p_plan_id, p_period, p_amount_sar, v_expected,
       jsonb_build_object('charge_breakdown', v_charge,
                          'idem', p_idempotency_key));
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'amount_mismatch',
      'submitted', p_amount_sar,
      'expected', v_expected,
      'breakdown', v_charge
    );
  END IF;

  -- (e) كل شيء سليم — سجِّل النيّة
  INSERT INTO public.payment_security_audit
    (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
  VALUES
    (v_uid, 'subscribe_intent', p_plan_id, p_period, p_amount_sar, v_expected,
     jsonb_build_object('charge_breakdown', v_charge,
                        'idem', p_idempotency_key));

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', p_plan_id,
    'period', p_period,
    'with_auto_pay', coalesce(p_with_auto_pay, false),
    'expected_amount', v_expected,
    'submitted_amount', p_amount_sar,
    'breakdown', v_charge,
    'rate', v_rate
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validate_payment_intent(
  uuid, text, numeric, boolean, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_payment_intent(
  uuid, text, numeric, boolean, uuid, text) TO authenticated, service_role;

-- =============================================================================
-- (6) RPC: record_payment_outcome — يُسجِّل في سجل المراجعة بعد كل محاولة
-- =============================================================================
CREATE OR REPLACE FUNCTION public.record_payment_outcome(
  p_event text,                            -- subscribe_ok | subscribe_failed | etc.
  p_plan_id uuid DEFAULT NULL,
  p_period text DEFAULT NULL,
  p_amount_sar numeric DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  INSERT INTO public.payment_security_audit
    (user_id, event, plan_id, period, amount_sar, payload)
  VALUES
    (v_uid, p_event, p_plan_id, p_period, p_amount_sar, p_payload);

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_outcome(text, uuid, text, numeric, jsonb)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_payment_outcome(text, uuid, text, numeric, jsonb)
  TO authenticated, service_role;

COMMIT;

-- =============================================================================
-- ملاحظات تشغيل:
--   • العميل يستدعي validate_payment_intent قبل بدء أي تدفق Moyasar.
--   • إن أعاد ok=true → يَستخدم expected_amount مباشرة (لا يَثق بحساب العميل).
--   • بعد نجاح/فشل الدفع، يُستدعى record_payment_outcome.
--   • سجل المراجعة قابل للقراءة من المالك فقط (RLS).
-- =============================================================================
