-- تنظيف جلسات الدخول القديمة تلقائياً (90 يوماً افتراضياً) لتخفيف الحمل.
-- يُستدعى من شاشة سجل الجلسات عند الفتح.

BEGIN;

CREATE OR REPLACE FUNCTION public.purge_my_old_user_sessions(p_days int DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  days int := greatest(14, least(coalesce(p_days, 90), 365));
  n int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  IF to_regclass('public.user_login_sessions') IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'deleted', 0, 'skipped', true);
  END IF;

  DELETE FROM public.user_login_sessions s
  WHERE s.user_id = v_uid
    AND s.login_at < (timezone('utc', now()) - make_interval(days => days))
    AND coalesce(s.is_active, false) = false;

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'deleted', n, 'days', days);
END;
$$;

REVOKE ALL ON FUNCTION public.purge_my_old_user_sessions(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_my_old_user_sessions(int) TO authenticated;

COMMIT;
