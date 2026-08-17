-- =============================================================================
-- Top-up حصة العروض: المسوقون والمنشآت يستفيدون من باقات «عروض السوق» (11/12/13)
-- بعد استنفاد حصة باقتهم الأساسية. (طلب المستخدم 2026-05-30)
-- =============================================================================
-- المنطق:
--   • لكل مستخدم: نحسب الحصة من الباقة الأساسية (إن وُجدت).
--   • نضيف فوقها أي رصيد من باقات «عروض السوق» النشطة (11/12/13).
--   • العداد يحسب كل أحداث market_request_offer_usage_events للمستخدم.
--   • إجمالي السماح = main_quota + sum(topup_quotas).
--   • إذا انتهى الإجمالي → needs_paywall = true.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (1) جلب جميع باقات عروض السوق النشطة لمستخدم (11/12/13)
-- ---------------------------------------------------------------------------
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
    AND p.user_type = 'individual'
    AND p.sort_order IN (11, 12, 13)
    AND coalesce(p.max_market_offers, 0) > 0
    AND (
      coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public._market_offer_topup_plans_for_uid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._market_offer_topup_plans_for_uid(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (2) حصة موحَّدة: يحسب main + topups بأمانة لكل مستخدم
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
  v_period_start_use date;
  v_lifetime_use boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'user')
  INTO v_at
  FROM public.users_profiles WHERE user_id = v_uid;

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

  -- (أ) الباقة الأساسية للمسوّق (إن كان مسوّقاً)
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

  -- (ب) باقات عروض السوق Top-up (لأي مستخدم — فردي أو تسويقي)
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
        'remaining', CASE WHEN v_main_unlimited THEN NULL ELSE greatest(0, v_main_max - v_main_used) END,
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
      ELSE greatest(0, v_total_max - v_total_used)
    END,
    'unlimited', v_main_unlimited,
    'needs_paywall', (NOT v_main_unlimited AND v_total_used >= v_total_max),
    'billing_user_id', v_bill_uid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.market_offer_unified_allowance(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_offer_unified_allowance(uuid)
  TO authenticated, service_role;

COMMIT;
