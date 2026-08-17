-- إحصاءات الشركاء المتصلين:
-- - online_now: جلسات حديثة بلا احتساب جلسة المستدعي
-- - online_guests: ضيوف متصلون الآن (مفاتيح g|…)
-- - p_exclude_client_key: مفتاح نبضة الجهاز الحالي لاستبعاده بدقة

CREATE OR REPLACE FUNCTION public.get_app_audience_stats(
  p_exclude_client_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reg bigint := 0;
  v_on bigint := 0;
  v_guests bigint := 0;
  v_excl text := NULLIF(btrim(COALESCE(p_exclude_client_key, '')), '');
  v_uid text := NULL;
BEGIN
  BEGIN
    v_uid := NULLIF(auth.uid()::text, '');
  EXCEPTION
    WHEN OTHERS THEN
      v_uid := NULL;
  END;

  IF to_regclass('public.users_profiles') IS NOT NULL THEN
    SELECT COUNT(*)::bigint INTO v_reg FROM public.users_profiles;
  END IF;

  IF to_regclass('public.app_presence_heartbeats') IS NOT NULL THEN
    SELECT COUNT(*)::bigint INTO v_on
    FROM public.app_presence_heartbeats h
    WHERE h.last_seen > (timezone('utc', now()) - interval '90 seconds')
      AND (v_excl IS NULL OR h.client_key IS DISTINCT FROM v_excl)
      AND (
        v_uid IS NULL
        OR h.client_key NOT LIKE (v_uid || '|%')
      );

    SELECT COUNT(*)::bigint INTO v_guests
    FROM public.app_presence_heartbeats h
    WHERE h.last_seen > (timezone('utc', now()) - interval '90 seconds')
      AND h.client_key LIKE 'g|%'
      AND (v_excl IS NULL OR h.client_key IS DISTINCT FROM v_excl);
  ELSIF to_regclass('public.user_sessions') IS NOT NULL THEN
    SELECT COUNT(DISTINCT user_id)::bigint INTO v_on
    FROM public.user_sessions
    WHERE last_active > (timezone('utc', now()) - interval '90 seconds')
      AND (v_uid IS NULL OR user_id::text IS DISTINCT FROM v_uid);
    v_guests := 0;
  END IF;

  RETURN jsonb_build_object(
    'registered_users', v_reg,
    'online_now', GREATEST(v_on, 0),
    'online_guests', GREATEST(v_guests, 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_app_audience_stats(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats(text) TO anon;

-- توافق الاستدعاء بدون وسيط (إن وُجدت النسخة القديمة بلا وسيط).
CREATE OR REPLACE FUNCTION public.get_app_audience_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_app_audience_stats(NULL);
$$;

REVOKE ALL ON FUNCTION public.get_app_audience_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats() TO anon;

COMMENT ON FUNCTION public.get_app_audience_stats(text) IS
  'online_now excludes caller (by uid and optional client key); online_guests = g|* minus self guest key.';
