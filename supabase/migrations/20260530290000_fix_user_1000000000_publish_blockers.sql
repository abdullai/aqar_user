-- =============================================================================
-- 2026-05-30 — تشخيص وإصلاح حالة المستخدم 1000000000 لتمكين النشر بعد التصاريح
-- =============================================================================
-- ملاحظة: users_profiles لا يحتوي على عمود fal_status.
-- الأعمدة الفعلية: fal_license_expires_at, fal_compliance_hold
--
-- إن فشلت هذه الهجرة سابقاً (42703 fal_status)، نفّذ بدلاً منها:
--   20260530300000_fix_fal_columns_debug_and_user_1000000000.sql
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_uid uuid;
  v_account text;
  v_fal_expiry timestamptz;
  v_fal_hold boolean := false;
  v_trial_used boolean := false;
  v_paid_count int := 0;
  v_plan_id uuid;
  v_sub_id uuid;
  v_plan_type text;
  v_end date := current_date + 3;
  v_ends timestamptz := timezone('utc', now()) + interval '3 days';
BEGIN
  SELECT user_id,
         lower(trim(coalesce(account_type::text, ''))),
         fal_license_expires_at,
         coalesce(fal_compliance_hold, false)
    INTO v_uid, v_account, v_fal_expiry, v_fal_hold
  FROM public.users_profiles
  WHERE username = '1000000000'
  LIMIT 1;

  IF v_uid IS NULL THEN
    RAISE NOTICE '[1000000000] user not found in users_profiles — لم يُسجّل بعد. لا يوجد إجراء.';
    RETURN;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_uid
  ) INTO v_trial_used;

  SELECT count(*) INTO v_paid_count
  FROM public.user_subscriptions
  WHERE user_id = v_uid
    AND coalesce(is_trial, false) = false
    AND status IN ('active', 'cancelled')
    AND coalesce(ends_at, end_date::timestamptz) > timezone('utc', now());

  RAISE NOTICE '[1000000000] uid=% account_type=% fal_expiry=% fal_hold=% trial_used=% paid_active_rows=%',
    v_uid, v_account, v_fal_expiry, v_fal_hold, v_trial_used, v_paid_count;

  -- إزالة حجز فال إذا كانت الرخصة سارية أو غير محددة (null = مسموح في التطبيق)
  IF v_fal_hold
     AND (v_fal_expiry IS NULL OR v_fal_expiry > timezone('utc', now())) THEN
    UPDATE public.users_profiles
       SET fal_compliance_hold = false
     WHERE user_id = v_uid;
    RAISE NOTICE '[1000000000] cleared fal_compliance_hold';
  END IF;

  IF v_account IN ('marketer','office','institution','company','agency')
     AND NOT v_trial_used
     AND v_paid_count = 0
     AND NOT EXISTS (
       SELECT 1 FROM public.user_subscriptions
       WHERE user_id = v_uid
         AND coalesce(is_trial, false) = true
         AND coalesce(ends_at, end_date::timestamptz) > timezone('utc', now())
     ) THEN

    v_plan_type := CASE trim(lower(v_account))
      WHEN 'marketer' THEN 'marketer'
      WHEN 'office' THEN 'office'
      WHEN 'company' THEN 'company'
      WHEN 'institution' THEN 'institution'
      WHEN 'agency' THEN 'office'
      ELSE 'marketer'
    END;

    SELECT id INTO v_plan_id
    FROM public.subscription_plans
    WHERE is_active = true
      AND coalesce(is_trial_plan, false) = true
      AND user_type = v_plan_type
    ORDER BY sort_order ASC
    LIMIT 1;

    IF v_plan_id IS NULL THEN
      SELECT id INTO v_plan_id
      FROM public.subscription_plans
      WHERE is_active = true
        AND coalesce(is_trial_plan, false) = false
        AND user_type = v_plan_type
        AND sort_order = 1
      LIMIT 1;
    END IF;

    IF v_plan_id IS NOT NULL THEN
      INSERT INTO public.user_subscriptions (
        user_id, organization_id, plan_id, status, period,
        start_date, end_date, auto_renew, starts_at, ends_at, is_trial
      )
      VALUES (
        v_uid, NULL, v_plan_id, 'active', 'monthly',
        current_date, v_end, false, timezone('utc', now()), v_ends, true
      )
      RETURNING id INTO v_sub_id;

      INSERT INTO public.user_trial_subscriptions_used (user_id, subscription_id)
      VALUES (v_uid, v_sub_id)
      ON CONFLICT (user_id) DO NOTHING;

      RAISE NOTICE '[1000000000] activated 3-day trial subscription on plan_id=%', v_plan_id;
    ELSE
      RAISE NOTICE '[1000000000] no plan available to activate trial — verify subscription_plans';
    END IF;
  END IF;
END;
$$;

COMMIT;

-- بعد التشغيل:
-- SELECT debug_user_subscription_state('1000000000');
