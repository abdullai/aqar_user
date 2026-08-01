-- بيئة تطوير: حذف كل صفوف user_subscriptions ثم منح اشتراك واحد لحساب الاختبار.
-- المستخدم: username 1000000000 / 100000000 → user_id 96bad4d0-8463-46b5-9525-575f477b7c88
-- التشغيل اليدوي: SELECT public.dev_reset_subscriptions_grant_test_user();

CREATE OR REPLACE FUNCTION public.dev_reset_subscriptions_grant_test_user()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted int;
  v_grant jsonb;
BEGIN
  DELETE FROM public.user_subscriptions;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  UPDATE public.billing_transactions
  SET subscription_id = NULL
  WHERE subscription_id IS NOT NULL;

  v_grant := public.dev_grant_marketing_test_subscription('1000000000');
  IF coalesce((v_grant->>'profiles_matched')::int, 0) = 0 THEN
    v_grant := public.dev_grant_marketing_test_subscription('100000000');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'subscriptions_deleted', v_deleted,
    'grant', v_grant
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dev_reset_subscriptions_grant_test_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_reset_subscriptions_grant_test_user() TO service_role;

-- تطبيق فوري عند الترحيل (بيئة مرتبطة بالمشروع فقط)
SELECT public.dev_reset_subscriptions_grant_test_user();
