-- =============================================================================
-- 2026-06-02 — منح اشتراك اختبار للمستخدم 100000000 (مرحلة التجربة)
-- =============================================================================
-- يمنح اشتراكاً مدفوعاً فعّالاً (365 يوم) للمستخدم الذي username='100000000'
-- أو phone يحتوي على هذه الأرقام، شخصياً + للمنشأة إن كان مالكها/عضوها.
--
-- يعتمد على الدوال:
--   • public.dev_grant_test_subscription_for_uid(uuid)
--   • public.dev_grant_test_subscription_by_match(text)
-- المعرّفة في:
--   supabase/migrations/20260517130000_dev_test_marketer_subscription_fix.sql
--   supabase/migrations/20260530130000_dev_grant_test_subscription_by_uid.sql
--
-- بالإضافة لرفع أي حجز فال (fal_compliance_hold) إن كانت الرخصة سارية أو غير محددة
-- حتى لا تُحجب بوابة paywall بسبب فال.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_uid uuid;
  v_account text;
  v_fal_expiry timestamptz;
  v_fal_hold boolean := false;
  v_grant_res jsonb;
BEGIN
  -- ابحث عن المستخدم بالاسم/الهاتف
  SELECT user_id,
         lower(trim(coalesce(account_type::text, ''))),
         fal_license_expires_at,
         coalesce(fal_compliance_hold, false)
    INTO v_uid, v_account, v_fal_expiry, v_fal_hold
  FROM public.users_profiles
  WHERE regexp_replace(coalesce(username::text, ''), '\D', '', 'g') = '100000000'
     OR regexp_replace(coalesce(phone::text,    ''), '\D', '', 'g') LIKE '%100000000%'
  ORDER BY created_at DESC NULLS LAST
  LIMIT 1;

  IF v_uid IS NULL THEN
    RAISE NOTICE '[100000000] user not found in users_profiles — لم يُسجّل بعد. لا يوجد إجراء.';
    RETURN;
  END IF;

  RAISE NOTICE '[100000000] uid=% account_type=% fal_expiry=% fal_hold=%',
    v_uid, v_account, v_fal_expiry, v_fal_hold;

  -- ارفع حجز فال إذا كانت الرخصة سارية أو غير محددة (null = مسموح في التطبيق)
  IF v_fal_hold
     AND (v_fal_expiry IS NULL OR v_fal_expiry > timezone('utc', now())) THEN
    UPDATE public.users_profiles
       SET fal_compliance_hold = false
     WHERE user_id = v_uid;
    RAISE NOTICE '[100000000] cleared fal_compliance_hold';
  END IF;

  -- امنح اشتراك اختبار سنة كاملة (شخصي + منشأة إن وُجد)
  v_grant_res := public.dev_grant_test_subscription_for_uid(v_uid);
  RAISE NOTICE '[100000000] grant result: %', v_grant_res;
END;
$$;

COMMIT;

-- =============================================================================
-- للتحقق بعد التشغيل:
--
-- SELECT id, user_id, organization_id, plan_id, status, is_trial,
--        starts_at, ends_at
--   FROM public.user_subscriptions
--  WHERE user_id IN (
--    SELECT user_id FROM public.users_profiles
--     WHERE regexp_replace(coalesce(username::text,''),'\D','','g') = '100000000'
--  )
--  ORDER BY created_at DESC;
--
-- SELECT * FROM public.dev_find_profile_like_digits('100000000');
-- =============================================================================
