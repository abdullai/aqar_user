-- =============================================================================
-- ميزات «المعلن الفرد / المستخدم العادي»: حصة عروض على طلبات السوق + سحب عرضي
-- =============================================================================
-- (1) إدراج باقتَين إضافيتين للحساب 'individual':
--       * شهري  : 49 ر — حتى 49 عرضاً على طلبات السوق خلال 30 يوماً (شهري).
--       * سنوي  : 49 × 12 × 0.80 = 470.40 ر — يجدّد العدّاد كل شهر تلقائياً.
--       * مرة واحدة : 40 ر — 3 عروض إجمالاً مدى الحياة بلا تجديد.
--     (الأساسي القديم 49 ريال يبقى في حدّ 40 إعلان/شهر؛ هذه الباقات جديدة.)
-- (2) عمود نوع البرنامج: `plan_program` ∈ {'monthly','yearly','lifetime_one_time'}
--     لتمييز «مرة واحدة» التي لا تُجدَّد.
-- (3) جدول حصص: market_request_offer_quotas(user_id, period_start, used_count).
-- (4) سجل سحب العروض: market_request_offer_user_withdrawals(user_id, request_id,
--     count) — بعد سحبين على نفس الطلب نمنع الإعادة.
-- (5) دوال:
--       * public.individual_market_request_offer_allowance() jsonb
--       * public.record_market_request_offer_usage(p_request_id uuid) jsonb
--       * public.withdraw_my_market_request_offer(p_request_id uuid) jsonb
-- =============================================================================

BEGIN;

-- ----------------------------------------------------------------------
-- (1) plan_program على subscription_plans (شهري/سنوي/مرة واحدة)
-- ----------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'subscription_plans'
      AND column_name = 'plan_program'
  ) THEN
    EXECUTE 'ALTER TABLE public.subscription_plans
             ADD COLUMN plan_program text NOT NULL DEFAULT ''monthly''';
    EXECUTE $chk$
      ALTER TABLE public.subscription_plans
      ADD CONSTRAINT chk_subscription_plans_program
      CHECK (plan_program IN ('monthly','yearly','lifetime_one_time'))
    $chk$;
  END IF;
END $$;

COMMENT ON COLUMN public.subscription_plans.plan_program IS
  'monthly: دفع شهري مع تجديد · yearly: سنوي مع خصم وعدّاد شهري · '
  'lifetime_one_time: دفع لمرة واحدة برصيد إجمالي ولا يُجدَّد.';

-- ----------------------------------------------------------------------
-- (2) سياسة باقات المعلن الفرد (individual) — الاحتفاظ بالقديمة وإضافة الجديدة
--     الحدّ max_listing_requests يُستخدم كحصة شهرية للعروض على طلبات السوق
--     عند الباقات الشهرية/السنوية، ولرصيد إجمالي عند «مرة واحدة».
--     ملاحظة: price_yearly NOT NULL في المخطط — نملأه دائماً (حتى للشهري/مرة واحدة).
-- ----------------------------------------------------------------------

INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type, plan_program,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent,
  sort_order, is_active
)
SELECT * FROM (VALUES
  -- شهري — 49 ريال — 49 عرضاً/شهر على طلبات السوق
  (N'عروض السوق — شهري', 'Market offers — monthly', 'individual', 'monthly',
   49::numeric, (49 * 12 * 0.80)::numeric,
   1, NULL::int, 0, 49::int,
   false, false, false, false, 0::numeric(5,2),
   11, true),

  -- سنوي — (49×12×0.80) = 470.40 — 49 عرضاً/شهر مع تجديد عدّاد شهري لمدة سنة
  (N'عروض السوق — سنوي (خصم 20%)', 'Market offers — yearly (20% off)',
   'individual', 'yearly',
   49::numeric, (49 * 12 * 0.80)::numeric,
   1, NULL::int, 0, 49::int,
   false, false, false, false, 0::numeric(5,2),
   12, true),

  -- مرة واحدة — 40 ريال — 3 عروض إجمالاً مدى الحياة (لا يوجد تجديد سنوي)
  (N'عروض السوق — مرة واحدة', 'Market offers — one-time',
   'individual', 'lifetime_one_time',
   40::numeric, 40::numeric,
   1, NULL::int, 0, 3::int,
   false, false, false, false, 0::numeric(5,2),
   13, true)
) AS v (
  name_ar, name_en, user_type, plan_program,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent,
  sort_order, is_active
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans p
  WHERE p.user_type = 'individual'
    AND p.plan_program = v.plan_program
    AND p.sort_order  = v.sort_order
);

-- ----------------------------------------------------------------------
-- (3) عدّاد الاستخدام (للشهري/السنوي) + الرصيد الإجمالي (لـ lifetime_one_time)
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.market_request_offer_quotas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL,
  plan_program  text NOT NULL CHECK (plan_program IN ('monthly','yearly','lifetime_one_time')),
  period_start  date NOT NULL,
  period_end    date NOT NULL,
  used_count    integer NOT NULL DEFAULT 0,
  max_count     integer NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, subscription_id, period_start)
);

ALTER TABLE public.market_request_offer_quotas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mr_offer_quotas_select_own ON public.market_request_offer_quotas;
CREATE POLICY mr_offer_quotas_select_own ON public.market_request_offer_quotas
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_mr_offer_quotas_user_period
  ON public.market_request_offer_quotas (user_id, period_start DESC);

COMMENT ON TABLE public.market_request_offer_quotas IS
  'حصة كل مستخدم لتقديم عروض على طلبات السوق (شهري/سنوي بتجديد شهري، '
  'أو رصيد إجمالي لـ lifetime_one_time).';

-- ----------------------------------------------------------------------
-- (4) سجل سحب عروضي + شرط «بعد سحبين لا يُسمح بإعادة»
-- ----------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.market_request_offer_user_withdrawals (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  market_request_id uuid NOT NULL
    REFERENCES public.market_property_requests (id) ON DELETE CASCADE,
  withdrawn_count integer NOT NULL DEFAULT 1,
  last_withdrawn_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, market_request_id)
);

ALTER TABLE public.market_request_offer_user_withdrawals
  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mrouw_select_own
  ON public.market_request_offer_user_withdrawals;
CREATE POLICY mrouw_select_own
  ON public.market_request_offer_user_withdrawals
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

COMMENT ON TABLE public.market_request_offer_user_withdrawals IS
  'سجل سحب المستخدم لعرضه على نفس الطلب — بعد سحبين نمنع إعادة التقديم.';

-- ----------------------------------------------------------------------
-- (5) دوال مساعدة
-- ----------------------------------------------------------------------

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
    coalesce(p.max_listing_requests, 0),
    coalesce(s.is_trial, false),
    coalesce(s.starts_at, s.start_date::timestamptz),
    coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active','cancelled')
    AND p.user_type = 'individual'
    AND (
      coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public._individual_active_plan_for_uid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._individual_active_plan_for_uid(uuid)
  TO authenticated, service_role;

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
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO v_plan
  FROM public._individual_active_plan_for_uid(v_uid);

  IF v_plan.plan_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'has_subscription', false,
      'remaining', 0,
      'used', 0,
      'max', 0,
      'plan_program', NULL
    );
  END IF;

  v_max := v_plan.max_count;

  IF v_plan.plan_program = 'lifetime_one_time' THEN
    v_period_start := (v_plan.starts_at AT TIME ZONE 'UTC')::date;
    v_period_end   := DATE '2999-12-31';
  ELSE
    v_period_start := ((v_plan.starts_at AT TIME ZONE 'UTC')::date
      + ((floor(extract(epoch FROM (now() - v_plan.starts_at)) / (30 * 86400))::int) * 30));
    v_period_end := v_period_start + 30;
  END IF;

  SELECT coalesce(used_count, 0) INTO v_used
  FROM public.market_request_offer_quotas
  WHERE user_id = v_uid
    AND subscription_id = v_plan.subscription_id
    AND period_start = v_period_start
  LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'has_subscription', true,
    'subscription_id', v_plan.subscription_id,
    'plan_id', v_plan.plan_id,
    'plan_program', v_plan.plan_program,
    'is_trial', v_plan.is_trial,
    'period_start', v_period_start,
    'period_end', v_period_end,
    'used', coalesce(v_used, 0),
    'max', v_max,
    'remaining', greatest(0, v_max - coalesce(v_used, 0))
  );
END;
$$;

REVOKE ALL ON FUNCTION public.individual_market_request_offer_allowance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.individual_market_request_offer_allowance()
  TO authenticated, service_role;

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
  v_plan record;
  v_period_start date;
  v_period_end date;
  v_max int := 0;
  v_used int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO v_plan
  FROM public._individual_active_plan_for_uid(v_uid);

  IF v_plan.plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_subscription');
  END IF;

  v_max := v_plan.max_count;

  IF v_plan.plan_program = 'lifetime_one_time' THEN
    v_period_start := (v_plan.starts_at AT TIME ZONE 'UTC')::date;
    v_period_end   := DATE '2999-12-31';
  ELSE
    v_period_start := ((v_plan.starts_at AT TIME ZONE 'UTC')::date
      + ((floor(extract(epoch FROM (now() - v_plan.starts_at)) / (30 * 86400))::int) * 30));
    v_period_end := v_period_start + 30;
  END IF;

  INSERT INTO public.market_request_offer_quotas (
    user_id, subscription_id, plan_program,
    period_start, period_end, used_count, max_count
  )
  VALUES (
    v_uid, v_plan.subscription_id, v_plan.plan_program,
    v_period_start, v_period_end, 1, v_max
  )
  ON CONFLICT (user_id, subscription_id, period_start)
  DO UPDATE SET
    used_count = market_request_offer_quotas.used_count + 1,
    updated_at = now()
  RETURNING used_count INTO v_used;

  RETURN jsonb_build_object(
    'ok', true,
    'used', v_used,
    'max', v_max,
    'remaining', greatest(0, v_max - v_used)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_market_request_offer_usage(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_market_request_offer_usage(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.withdraw_my_market_request_offer(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req record;
  v_offer record;
  v_count int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT id, requester_id, status, selected_offer_id
  INTO v_req
  FROM public.market_property_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_req.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;

  SELECT *
  INTO v_offer
  FROM public.market_request_offers
  WHERE market_request_id = p_request_id
    AND offerer_id = v_uid
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_offer.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'offer_not_found');
  END IF;

  IF v_req.selected_offer_id = v_offer.id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'selected_for_deal');
  END IF;
  IF lower(coalesce(v_offer.status,'')) = 'accepted' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'offer_accepted');
  END IF;

  SELECT coalesce(withdrawn_count, 0) INTO v_count
  FROM public.market_request_offer_user_withdrawals
  WHERE user_id = v_uid AND market_request_id = p_request_id;

  IF coalesce(v_count, 0) >= 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'withdraw_limit_reached');
  END IF;

  UPDATE public.market_request_offers
  SET status = 'withdrawn',
      updated_at = now()
  WHERE id = v_offer.id;

  INSERT INTO public.market_request_offer_user_withdrawals (
    user_id, market_request_id, withdrawn_count, last_withdrawn_at
  )
  VALUES (v_uid, p_request_id, 1, now())
  ON CONFLICT (user_id, market_request_id)
  DO UPDATE SET
    withdrawn_count = market_request_offer_user_withdrawals.withdrawn_count + 1,
    last_withdrawn_at = now()
  RETURNING withdrawn_count INTO v_count;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'withdrawn_count', v_count,
    'final', (v_count >= 2)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.withdraw_my_market_request_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.withdraw_my_market_request_offer(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.market_requests_hidden_for_user_after_two_withdrawals()
RETURNS TABLE (market_request_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT market_request_id
  FROM public.market_request_offer_user_withdrawals
  WHERE user_id = auth.uid()
    AND withdrawn_count >= 2;
$$;

REVOKE ALL ON FUNCTION public.market_requests_hidden_for_user_after_two_withdrawals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_requests_hidden_for_user_after_two_withdrawals()
  TO authenticated, service_role;

COMMIT;
