-- Lightweight client heartbeats for approximate "online now" counts (web + mobile + guest).
-- Replaces reliance on legacy user_sessions rows for get_app_audience_stats when this table exists.

BEGIN;

CREATE TABLE IF NOT EXISTS public.app_presence_heartbeats (
  client_key text PRIMARY KEY,
  last_seen timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_app_presence_heartbeats_last_seen
  ON public.app_presence_heartbeats (last_seen DESC);

ALTER TABLE public.app_presence_heartbeats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_presence_heartbeats_no_direct ON public.app_presence_heartbeats;
CREATE POLICY app_presence_heartbeats_no_direct ON public.app_presence_heartbeats
  FOR ALL TO authenticated, anon
  USING (false)
  WITH CHECK (false);

CREATE OR REPLACE FUNCTION public.ping_app_presence(p_client_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  k text := left(trim(coalesce(p_client_key, '')), 512);
BEGIN
  IF length(k) < 8 THEN
    RETURN;
  END IF;
  INSERT INTO public.app_presence_heartbeats (client_key, last_seen)
  VALUES (k, timezone('utc', now()))
  ON CONFLICT (client_key) DO UPDATE
    SET last_seen = timezone('utc', now());
END;
$$;

REVOKE ALL ON FUNCTION public.ping_app_presence(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ping_app_presence(text) TO anon;
GRANT EXECUTE ON FUNCTION public.ping_app_presence(text) TO authenticated;

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
    WHERE last_seen > (timezone('utc', now()) - interval '2 minutes');
  ELSIF to_regclass('public.user_sessions') IS NOT NULL THEN
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

REVOKE ALL ON FUNCTION public.get_app_audience_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_app_audience_stats() TO anon;

COMMENT ON FUNCTION public.ping_app_presence(text) IS
  'Upserts a short client key (e.g. uid|install or g|install) to refresh last_seen for audience online_now.';
COMMENT ON FUNCTION public.get_app_audience_stats() IS
  'registered_users from users_profiles; online_now from app_presence_heartbeats (2m window) if table exists, else user_sessions.';

COMMIT;
