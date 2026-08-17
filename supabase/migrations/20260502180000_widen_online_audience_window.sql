-- توسيع نافذة "متصل الآن" في get_app_audience_stats لتقليل التقليل الشديد
-- (جلسات الويب/الجوال قد لا تُحدَّث كل 30 ثانية).
CREATE OR REPLACE FUNCTION public.get_app_audience_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reg bigint := 0;
  v_on bigint := 0;
BEGIN
  IF to_regclass('public.users_profiles') IS NOT NULL THEN
    SELECT COUNT(*)::bigint INTO v_reg FROM public.users_profiles;
  END IF;

  IF to_regclass('public.user_sessions') IS NOT NULL THEN
    SELECT COUNT(DISTINCT user_id)::bigint INTO v_on
    FROM public.user_sessions
    WHERE last_active > (timezone('utc', now()) - interval '2 minutes');
  END IF;

  RETURN jsonb_build_object(
    'registered_users', v_reg,
    'online_now', v_on
  );
END;
$$;

COMMENT ON FUNCTION public.get_app_audience_stats() IS
  'COUNT(users_profiles) and COUNT(DISTINCT user_id) from user_sessions with last_active within the last 2 minutes (approximate concurrent users).';
