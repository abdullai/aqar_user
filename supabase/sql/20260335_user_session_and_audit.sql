-- جلسة واحدة (آخر تسجيل دخول يفوز) + سجل دخول بسيط.
-- بعد التنفيذ: Dashboard → Database → Replication → أنشئ من user_session_state إن لم يظهر تلقائياً.

CREATE TABLE IF NOT EXISTS public.user_session_state (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  session_epoch bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.user_session_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_session_state_own_all ON public.user_session_state;
CREATE POLICY user_session_state_own_all ON public.user_session_state
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.bump_user_session_epoch()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  u uuid := auth.uid();
  e bigint;
BEGIN
  IF u IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  INSERT INTO public.user_session_state (user_id, session_epoch)
  VALUES (u, 1)
  ON CONFLICT (user_id) DO UPDATE
  SET session_epoch = public.user_session_state.session_epoch + 1,
      updated_at = timezone('utc', now())
  RETURNING session_epoch INTO e;

  RETURN e;
END;
$$;

REVOKE ALL ON FUNCTION public.bump_user_session_epoch() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bump_user_session_epoch() TO authenticated;

CREATE TABLE IF NOT EXISTS public.user_login_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  event text NOT NULL DEFAULT 'sign_in',
  platform text,
  device_model text,
  app_version text,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.user_login_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_login_audit_insert_own ON public.user_login_audit;
CREATE POLICY user_login_audit_insert_own ON public.user_login_audit
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS user_login_audit_select_own ON public.user_login_audit;
CREATE POLICY user_login_audit_select_own ON public.user_login_audit
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Realtime: من لوحة Supabase → Database → Replication أضف الجدول user_session_state
-- أو نفّذ يدوياً: ALTER PUBLICATION supabase_realtime ADD TABLE public.user_session_state;
