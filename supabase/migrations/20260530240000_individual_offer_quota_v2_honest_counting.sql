-- =============================================================================
-- حصص عروض السوق للمعلن/المالك/المستخدم العادي — v2 (عدالة + دقة)
-- =============================================================================
-- (1) مرة واحدة: 10 عروض (كان 3) — كل محاولة تقديم تُحسب حتى لو سُحب العرض.
-- (2) شهري: 49 عرض/شهر — السعر 49 ريال (بدون تغيير).
-- (3) جدول market_request_offer_usage_events: سجل كل تقديم (لا يُحذف عند السحب).
-- (4) RPC للمسوّقين/المكاتب/المؤسسات/الشركات: marketing_market_request_offer_allowance
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (أ) تحديث باقات individual
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans SET
  max_market_offers    = 49,
  max_listing_requests = 0,
  max_ads_per_month    = 0,
  has_fal_license      = false,
  price_monthly        = 49::numeric,
  price_yearly         = round((49 * 12 * 0.80)::numeric, 2),
  name_ar              = N'عروض السوق — شهري (49 عرض/شهر)',
  name_en              = 'Market offers — monthly (49 offers/month)'
WHERE is_active = true
  AND user_type = 'individual'
  AND sort_order = 11;

UPDATE public.subscription_plans SET
  max_market_offers    = 49,
  max_listing_requests = 0,
  max_ads_per_month    = 0,
  has_fal_license      = false,
  name_ar              = N'عروض السوق — سنوي (49 عرض/شهر · خصم 20%)',
  name_en              = 'Market offers — yearly (49 offers/month · 20% off)'
WHERE is_active = true
  AND user_type = 'individual'
  AND sort_order = 12;

UPDATE public.subscription_plans SET
  max_market_offers    = 10,
  max_listing_requests = 0,
  max_ads_per_month    = 0,
  has_fal_license      = false,
  price_monthly        = 40::numeric,
  price_yearly         = 40::numeric,
  name_ar              = N'عروض السوق — مرة واحدة (10 عروض)',
  name_en              = 'Market offers — one-time (10 offers)'
WHERE is_active = true
  AND user_type = 'individual'
  AND sort_order = 13;

-- ---------------------------------------------------------------------------
-- (ب) سجل كل محاولة تقديم عرض (لا يُحذف عند السحب — للعدالة)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.market_request_offer_usage_events (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  market_request_id   uuid NOT NULL
    REFERENCES public.market_property_requests (id) ON DELETE CASCADE,
  subscription_id     uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  plan_program        text NOT NULL DEFAULT 'monthly'
    CHECK (plan_program IN ('monthly','yearly','lifetime_one_time')),
  period_start        date NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mroue_user_period
  ON public.market_request_offer_usage_events (user_id, period_start DESC);

CREATE INDEX IF NOT EXISTS idx_mroue_user_request
  ON public.market_request_offer_usage_events (user_id, market_request_id);

ALTER TABLE public.market_request_offer_usage_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mroue_select_own ON public.market_request_offer_usage_events;
CREATE POLICY mroue_select_own ON public.market_request_offer_usage_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

COMMENT ON TABLE public.market_request_offer_usage_events IS
  'كل محاولة تقديم عرض على طلب سوق — تُحسب في الحصة حتى لو سُحب العرض لاحقاً.';

-- ---------------------------------------------------------------------------
-- (ج) دالة مساعدة: فترة العدّاد الشهري من تاريخ بداية الاشتراك
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._offer_quota_period_bounds(
  p_starts_at timestamptz,
  p_plan_program text
)
RETURNS TABLE (period_start date, period_end date)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_start date;
  v_end date;
  v_elapsed_days int;
BEGIN
  IF coalesce(p_plan_program, 'monthly') = 'lifetime_one_time' THEN
    period_start := (p_starts_at AT TIME ZONE 'UTC')::date;
    period_end   := DATE '2999-12-31';
    RETURN NEXT;
    RETURN;
  END IF;
  v_elapsed_days := floor(
    extract(epoch FROM (now() - p_starts_at)) / 86400
  )::int;
  period_start := ((p_starts_at AT TIME ZONE 'UTC')::date
    + ((v_elapsed_days / 30) * 30));
  period_end := period_start + 30;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- (د) عدّاد الاستخدام الصادق (من الأحداث وليس من العداد القابل للتلاعب)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._count_offer_usage_for_user(
  p_uid uuid,
  p_subscription_id uuid,
  p_period_start date,
  p_lifetime boolean
)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::int
  FROM public.market_request_offer_usage_events e
  WHERE e.user_id = p_uid
    AND (
      p_lifetime
      OR (
        e.subscription_id = p_subscription_id
        AND e.period_start = p_period_start
      )
    );
$$;

REVOKE ALL ON FUNCTION public._count_offer_usage_for_user(uuid, uuid, date, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._count_offer_usage_for_user(uuid, uuid, date, boolean)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (هـ) خطة individual النشطة (عروض السوق فقط — sort 11/12/13)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._individual_active_plan_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  is_trial boolean,
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
    coalesce(s.is_trial, false),
    coalesce(s.starts_at, s.start_date::timestamptz),
    coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active','cancelled')
    AND p.user_type = 'individual'
    AND coalesce(p.max_market_offers, 0) > 0
    AND p.sort_order IN (11, 12, 13)
    AND (
      coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- (و) خطة تسويق نشطة (مسوّق/مكتب/مؤسسة/شركة) — اشتراك مدفوع أو تجربة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marketing_active_plan_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  is_trial boolean,
  starts_at timestamptz,
  ends_at timestamptz,
  user_type text
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
    p.max_market_offers,
    coalesce(s.is_trial, false),
    coalesce(s.starts_at, s.start_date::timestamptz),
    coalesce(s.ends_at, s.end_date::timestamptz),
    p.user_type
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active','cancelled')
    AND p.user_type IN ('marketer','office','institution','company')
    AND (
      coalesce(s.is_trial, false) = true
      OR coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY
    CASE WHEN coalesce(s.is_trial, false) THEN 0 ELSE 1 END,
    s.created_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public._marketing_active_plan_for_uid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._marketing_active_plan_for_uid(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (ز) حصة المستخدم العادي / المعلن / المالك
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.individual_market_request_offer_allowance()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_plan record;
  v_period_start date;
  v_period_end date;
  v_used int := 0;
  v_max int := 0;
  v_lifetime boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO v_plan FROM public._individual_active_plan_for_uid(v_uid);

  IF v_plan.plan_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'has_subscription', false,
      'remaining', 0,
      'used', 0,
      'max', 0,
      'plan_program', NULL,
      'needs_paywall', true
    );
  END IF;

  v_max := v_plan.max_count;
  v_lifetime := (v_plan.plan_program = 'lifetime_one_time');

  SELECT pb.period_start, pb.period_end
  INTO v_period_start, v_period_end
  FROM public._offer_quota_period_bounds(v_plan.starts_at, v_plan.plan_program) pb;

  v_used := public._count_offer_usage_for_user(
    v_uid, v_plan.subscription_id, v_period_start, v_lifetime
  );

  RETURN jsonb_build_object(
    'ok', true,
    'has_subscription', true,
    'subscription_id', v_plan.subscription_id,
    'plan_id', v_plan.plan_id,
    'plan_program', v_plan.plan_program,
    'is_trial', v_plan.is_trial,
    'period_start', v_period_start,
    'period_end', v_period_end,
    'starts_at', v_plan.starts_at,
    'ends_at', v_plan.ends_at,
    'used', v_used,
    'max', v_max,
    'remaining', greatest(0, v_max - v_used),
    'needs_paywall', (v_used >= v_max),
    'audience', 'individual'
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- (ح) حصة المسوّق / المكتب / المؤسسة / الشركة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketing_market_request_offer_allowance(
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
  v_plan record;
  v_period_start date;
  v_period_end date;
  v_used int := 0;
  v_max int;
  v_unlimited boolean := false;
  v_lifetime boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  v_bill_uid := v_uid;
  IF p_organization_id IS NOT NULL THEN
    SELECT o.owner_user_id INTO v_bill_uid
    FROM public.org_units o
    WHERE o.id = p_organization_id
    LIMIT 1;
    IF v_bill_uid IS NULL THEN
      v_bill_uid := v_uid;
    END IF;
  ELSE
    SELECT o.owner_user_id INTO v_bill_uid
    FROM public.org_memberships m
    JOIN public.org_units o ON o.id = m.org_id
    WHERE m.user_id = v_uid AND m.status = 'active'
    ORDER BY m.created_at DESC
    LIMIT 1;
    IF v_bill_uid IS NULL THEN
      v_bill_uid := v_uid;
    END IF;
  END IF;

  SELECT * INTO v_plan FROM public._marketing_active_plan_for_uid(v_bill_uid);

  IF v_plan.plan_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'has_subscription', false,
      'remaining', 0,
      'used', 0,
      'max', 0,
      'plan_program', NULL,
      'needs_paywall', true,
      'audience', 'marketing'
    );
  END IF;

  IF v_plan.is_trial OR v_plan.max_count IS NULL THEN
    v_unlimited := true;
    v_max := 999999;
  ELSE
    v_max := coalesce(v_plan.max_count, 0);
  END IF;

  v_lifetime := (v_plan.plan_program = 'lifetime_one_time');

  SELECT pb.period_start, pb.period_end
  INTO v_period_start, v_period_end
  FROM public._offer_quota_period_bounds(v_plan.starts_at, v_plan.plan_program) pb;

  IF NOT v_unlimited THEN
    v_used := public._count_offer_usage_for_user(
      v_bill_uid, v_plan.subscription_id, v_period_start, v_lifetime
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'has_subscription', true,
    'subscription_id', v_plan.subscription_id,
    'plan_id', v_plan.plan_id,
    'plan_program', v_plan.plan_program,
    'is_trial', v_plan.is_trial,
    'period_start', v_period_start,
    'period_end', v_period_end,
    'starts_at', v_plan.starts_at,
    'ends_at', v_plan.ends_at,
    'used', v_used,
    'max', CASE WHEN v_unlimited THEN NULL ELSE v_max END,
    'remaining', CASE WHEN v_unlimited THEN NULL ELSE greatest(0, v_max - v_used) END,
    'needs_paywall', (NOT v_unlimited AND v_used >= v_max),
    'audience', 'marketing',
    'billing_user_id', v_bill_uid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.marketing_market_request_offer_allowance(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketing_market_request_offer_allowance(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (ط) تسجيل استخدام عرض — يُنشئ حدثاً دائماً (حتى إعادة التقديم بعد السحب)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_market_request_offer_usage(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ind record;
  v_mkt record;
  v_plan record;
  v_period_start date;
  v_period_end date;
  v_max int := 0;
  v_used int := 0;
  v_lifetime boolean := false;
  v_unlimited boolean := false;
  v_audience text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF p_request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_request');
  END IF;

  SELECT * INTO v_ind FROM public._individual_active_plan_for_uid(v_uid);

  IF v_ind.plan_id IS NOT NULL THEN
    v_plan := v_ind;
    v_audience := 'individual';
  ELSE
    SELECT * INTO v_mkt FROM public._marketing_active_plan_for_uid(v_uid);
    IF v_mkt.plan_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'no_subscription');
    END IF;
    v_plan := v_mkt;
    v_audience := 'marketing';
  END IF;

  IF v_plan.is_trial OR (v_audience = 'marketing' AND v_plan.max_count IS NULL) THEN
    v_unlimited := true;
    v_max := 999999;
  ELSE
    v_max := coalesce(v_plan.max_count, 0);
  END IF;

  v_lifetime := (v_plan.plan_program = 'lifetime_one_time');

  SELECT pb.period_start, pb.period_end
  INTO v_period_start, v_period_end
  FROM public._offer_quota_period_bounds(v_plan.starts_at, v_plan.plan_program) pb;

  IF NOT v_unlimited THEN
    v_used := public._count_offer_usage_for_user(
      v_uid, v_plan.subscription_id, v_period_start, v_lifetime
    );
    IF v_used >= v_max THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'quota_exhausted',
        'used', v_used,
        'max', v_max,
        'remaining', 0
      );
    END IF;
  END IF;

  INSERT INTO public.market_request_offer_usage_events (
    user_id, market_request_id, subscription_id, plan_program, period_start
  )
  VALUES (
    v_uid, p_request_id, v_plan.subscription_id,
    coalesce(v_plan.plan_program, 'monthly'), v_period_start
  );

  -- مزامنة العداد القديم (للتوافق)
  INSERT INTO public.market_request_offer_quotas (
    user_id, subscription_id, plan_program,
    period_start, period_end, used_count, max_count
  )
  VALUES (
    v_uid, v_plan.subscription_id, coalesce(v_plan.plan_program, 'monthly'),
    v_period_start, v_period_end, 1, v_max
  )
  ON CONFLICT (user_id, subscription_id, period_start)
  DO UPDATE SET
    used_count = market_request_offer_quotas.used_count + 1,
    updated_at = now();

  v_used := public._count_offer_usage_for_user(
    v_uid, v_plan.subscription_id, v_period_start, v_lifetime
  );

  RETURN jsonb_build_object(
    'ok', true,
    'used', v_used,
    'max', CASE WHEN v_unlimited THEN NULL ELSE v_max END,
    'remaining', CASE WHEN v_unlimited THEN NULL ELSE greatest(0, v_max - v_used) END,
    'audience', v_audience
  );
END;
$$;

-- سحب العرض: لا يُرجع الحصة (الأحداث تبقى)
-- (دالة withdraw_my_market_request_offer تبقى كما في 20260530200000)

COMMIT;
