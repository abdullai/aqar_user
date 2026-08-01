-- =============================================================================
-- 2026-06-02 — منح اشتراك اختبار للمستخدم abdullai07@hotmail.com
--   user_id = 96bad4d0-8463-46b5-9525-575f477b7c88
-- =============================================================================
-- يمنح اشتراكاً مدفوعاً فعّالاً (365 يوم) — شخصياً + للمنشأة إن كان مالكها/عضوها.
--
-- يعتمد على:
--   public.dev_grant_test_subscription_for_uid(uuid)
--   (معرّفة في 20260530130000_dev_grant_test_subscription_by_uid.sql)
--
-- أيضاً يرفع حجز فال إن كانت الرخصة سارية أو غير محددة.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_uid uuid := '96bad4d0-8463-46b5-9525-575f477b7c88';
  v_account text;
  v_fal_expiry timestamptz;
  v_fal_hold boolean := false;
  v_grant_res jsonb;
BEGIN
  SELECT lower(trim(coalesce(account_type::text, ''))),
         fal_license_expires_at,
         coalesce(fal_compliance_hold, false)
    INTO v_account, v_fal_expiry, v_fal_hold
  FROM public.users_profiles
  WHERE user_id = v_uid
  LIMIT 1;

  IF v_account IS NULL THEN
    RAISE NOTICE '[abdullah] user_id=% not found in users_profiles', v_uid;
    RETURN;
  END IF;

  RAISE NOTICE '[abdullah] uid=% account_type=% fal_expiry=% fal_hold=%',
    v_uid, v_account, v_fal_expiry, v_fal_hold;

  IF v_fal_hold
     AND (v_fal_expiry IS NULL OR v_fal_expiry > timezone('utc', now())) THEN
    UPDATE public.users_profiles
       SET fal_compliance_hold = false
     WHERE user_id = v_uid;
    RAISE NOTICE '[abdullah] cleared fal_compliance_hold';
  END IF;

  v_grant_res := public.dev_grant_test_subscription_for_uid(v_uid);
  RAISE NOTICE '[abdullah] grant result: %', v_grant_res;
END;
$$;

COMMIT;

-- =============================================================================
-- للتحقق:
-- SELECT id, user_id, organization_id, plan_id, status, is_trial,
--        starts_at, ends_at
--   FROM public.user_subscriptions
--  WHERE user_id = '96bad4d0-8463-46b5-9525-575f477b7c88'
--  ORDER BY created_at DESC;
-- =============================================================================
