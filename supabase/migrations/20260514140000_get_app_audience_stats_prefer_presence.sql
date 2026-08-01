-- Restore online_now from app_presence_heartbeats when present (heartbeat path),
-- after 20260502180000 had limited stats to user_sessions only.
-- Widen window slightly vs 2m to tolerate 50–55s client poll + network jitter.

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

  IF to_regclass('public.app_presence_heartbeats') IS NOT NULL THEN
    SELECT COUNT(*)::bigint INTO v_on
    FROM public.app_presence_heartbeats
    WHERE last_seen > (timezone('utc', now()) - interval '4 minutes');
  ELSIF to_regclass('public.user_sessions') IS NOT NULL THEN
    SELECT COUNT(DISTINCT user_id)::bigint INTO v_on
    FROM public.user_sessions
    WHERE last_active > (timezone('utc', now()) - interval '4 minutes');
  END IF;

  RETURN jsonb_build_object(
    'registered_users', v_reg,
    'online_now', v_on
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_app_audience_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats() TO anon;

COMMENT ON FUNCTION public.get_app_audience_stats() IS
  'registered_users from users_profiles; online_now from app_presence_heartbeats (4m) if table exists, else user_sessions (4m).';
