-- =============================================================================
-- 2026-05-30 — إصلاح أعمدة فال (لا يوجد fal_status في users_profiles)
-- =============================================================================
-- الأعمدة الفعلية:
--   users_profiles.fal_license_expires_at
--   users_profiles.fal_compliance_hold
-- (نفس منطق resolve_subscription_billing_context و ProfileComplianceService)
--
-- يصلح:
--   1) debug_user_subscription_state — كان يشير إلى fal_status غير موجود
--   2) إصلاح المستخدم 1000000000 (بديل للهجرة 20260530290000 الفاشلة)
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (1) debug_user_subscription_state — منطق فال صحيح
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.debug_user_subscription_state(
  p_username text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_account text;
  v_fal_expiry timestamptz;
  v_fal_hold boolean := false;
  v_fal_status text := 'ok';
  v_active jsonb;
  v_trial  jsonb;
  v_trial_active boolean := false;
  v_reasons jsonb := '[]'::jsonb;
  v_can_publish boolean := false;
BEGIN
  SELECT user_id,
         lower(trim(coalesce(account_type::text, ''))),
         fal_license_expires_at,
         coalesce(fal_compliance_hold, false)
    INTO v_uid, v_account, v_fal_expiry, v_fal_hold
  FROM public.users_profiles
  WHERE username = trim(p_username)
  LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'user_not_found',
      'username', p_username
    );
  END IF;

  IF v_account IN ('marketer','office','institution','company','agency') THEN
    IF v_fal_hold THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expiry IS NOT NULL AND v_fal_expiry <= timezone('utc', now()) THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expiry IS NOT NULL
      AND v_fal_expiry <= timezone('utc', now()) + interval '7 days' THEN
      v_fal_status := 'warn';
    END IF;
  END IF;

  SELECT to_jsonb(s.*) INTO v_active
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_trial, false) = false
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ORDER BY s.created_at DESC
  LIMIT 1;

  SELECT to_jsonb(s.*) INTO v_trial
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND coalesce(s.is_trial, false) = true
  ORDER BY s.created_at DESC
  LIMIT 1;

  v_trial_active := v_trial IS NOT NULL
    AND coalesce(
          (v_trial->>'ends_at')::timestamptz,
          (v_trial->>'end_date')::timestamptz,
          'epoch'::timestamptz
        ) > timezone('utc', now());

  IF v_account IN ('marketer','office','institution','company','agency') THEN
    IF v_active IS NULL AND NOT v_trial_active THEN
      v_reasons := v_reasons || to_jsonb('no_active_subscription_or_trial'::text);
    END IF;

    IF v_fal_status = 'blocked' THEN
      IF v_fal_hold THEN
        v_reasons := v_reasons || to_jsonb('fal_compliance_hold'::text);
      ELSIF v_fal_expiry IS NOT NULL AND v_fal_expiry <= timezone('utc', now()) THEN
        v_reasons := v_reasons || to_jsonb('fal_expired'::text);
      ELSE
        v_reasons := v_reasons || to_jsonb('fal_blocked'::text);
      END IF;
    END IF;

    v_can_publish := jsonb_array_length(v_reasons) = 0;
  ELSE
    v_reasons := v_reasons || to_jsonb('account_type_not_marketing'::text);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'username', p_username,
    'user_id', v_uid,
    'account_type', v_account,
    'fal_status', v_fal_status,
    'fal_compliance_hold', v_fal_hold,
    'fal_license_expires_at', v_fal_expiry,
    'active_subscription', v_active,
    'trial_subscription', v_trial,
    'trial_active', v_trial_active,
    'can_publish_listing_marketer', v_can_publish,
    'block_reasons', v_reasons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.debug_user_subscription_state(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.debug_user_subscription_state(text)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (2) إصلاح المستخدم 1000000000
-- ---------------------------------------------------------------------------
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
    RAISE NOTICE '[1000000000] user not found — لا يوجد إجراء.';
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

  RAISE NOTICE '[1000000000] uid=% type=% fal_expiry=% fal_hold=% trial_used=% paid_active=%',
    v_uid, v_account, v_fal_expiry, v_fal_hold, v_trial_used, v_paid_count;

  -- إزالة حجز فال إذا كانت الرخصة ما زالت سارية
  IF v_fal_hold
     AND (v_fal_expiry IS NULL OR v_fal_expiry > timezone('utc', now())) THEN
    UPDATE public.users_profiles
       SET fal_compliance_hold = false
     WHERE user_id = v_uid;
    RAISE NOTICE '[1000000000] cleared fal_compliance_hold (license still valid or unset)';
  END IF;

  -- تجربة 3 أيام إن لم يُستخدم التجريب ولا اشتراك مدفوع
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

      RAISE NOTICE '[1000000000] activated 3-day trial sub_id=% plan_id=%',
        v_sub_id, v_plan_id;
    ELSE
      RAISE NOTICE '[1000000000] no plan found for type=%', v_plan_type;
    END IF;
  END IF;
END;
$$;

COMMIT;

-- تأكيد:
-- SELECT debug_user_subscription_state('1000000000');
