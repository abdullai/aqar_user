-- =============================================================================
-- تحذير: هذا الملف يفترض جدول user_sessions بأعمدة منفصلة
--   (device_key, platform, user_agent, device_label, last_seen_at, …).
--
-- إن كان إنتاجك يستخدم المخطط المبسّط فقط:
--   id, user_id, device, last_active, created_at
-- فلا تنفّذ إنشاء/تعديل الجدول من هنا؛ طبّق بدلاً منه:
--   20260410_user_sessions_minimal_schema_rpc.sql
-- (يستبدل دوال register_single_user_session / reconcile_user_session بإصدار p_device نص واحد).
-- =============================================================================
--
-- جلسة واحدة نشطة لكل مستخدم + سجل دخول + دعم Realtime لإبطال الجلسة.
-- فعّل نسخ الجدول لـ Supabase Realtime: user_sessions (للأحداث DELETE).

CREATE TABLE IF NOT EXISTS public.user_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_key text NOT NULL,
  platform text NOT NULL DEFAULT '',
  user_agent text,
  device_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON public.user_sessions (user_id);

CREATE TABLE IF NOT EXISTS public.login_logs (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_key text NOT NULL DEFAULT '',
  platform text NOT NULL DEFAULT '',
  user_agent text,
  device_label text,
  event text NOT NULL DEFAULT 'login',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_logs_user_id ON public.login_logs (user_id);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_sessions_select_own" ON public.user_sessions;
CREATE POLICY "user_sessions_select_own" ON public.user_sessions
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_sessions_delete_own" ON public.user_sessions;
CREATE POLICY "user_sessions_delete_own" ON public.user_sessions
  FOR DELETE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "login_logs_select_own" ON public.login_logs;
CREATE POLICY "login_logs_select_own" ON public.login_logs
  FOR SELECT USING (auth.uid() = user_id);

-- تسجيل دخول جديد: إلغاء كل الجلسات السابقة لهذا المستخدم ثم إنشاء جلسة واحدة.
CREATE OR REPLACE FUNCTION public.register_single_user_session(
  p_device_key text,
  p_platform text,
  p_user_agent text DEFAULT NULL,
  p_device_label text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  new_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  DELETE FROM public.user_sessions WHERE user_id = uid;

  INSERT INTO public.user_sessions (
    user_id, device_key, platform, user_agent, device_label
  )
  VALUES (
    uid,
    p_device_key,
    COALESCE(p_platform, ''),
    COALESCE(p_user_agent, ''),
    COALESCE(p_device_label, '')
  )
  RETURNING id INTO new_id;

  INSERT INTO public.login_logs (
    user_id, device_key, platform, user_agent, device_label, event
  )
  VALUES (
    uid,
    p_device_key,
    COALESCE(p_platform, ''),
    COALESCE(p_user_agent, ''),
    COALESCE(p_device_label, ''),
    'login'
  );

  RETURN jsonb_build_object('ok', true, 'session_id', new_id);
END;
$$;

-- عند إقلاع التطبيق: تحديث الجلسة الحالية أو اكتشاف أن جهازاً آخر استولى على الحساب.
CREATE OR REPLACE FUNCTION public.reconcile_user_session(
  p_device_key text,
  p_platform text,
  p_user_agent text DEFAULT NULL,
  p_device_label text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  r RECORD;
  new_id uuid;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  SELECT id, device_key INTO r
  FROM public.user_sessions
  WHERE user_id = uid
  LIMIT 1;

  IF NOT FOUND THEN
    INSERT INTO public.user_sessions (
      user_id, device_key, platform, user_agent, device_label
    )
    VALUES (
      uid,
      p_device_key,
      COALESCE(p_platform, ''),
      COALESCE(p_user_agent, ''),
      COALESCE(p_device_label, '')
    )
    RETURNING id INTO new_id;

    RETURN jsonb_build_object('ok', true, 'session_id', new_id, 'action', 'inserted');
  END IF;

  IF r.device_key IS DISTINCT FROM p_device_key THEN
    RETURN jsonb_build_object('ok', false, 'error', 'session_replaced');
  END IF;

  UPDATE public.user_sessions
  SET
    last_seen_at = now(),
    user_agent = COALESCE(NULLIF(TRIM(COALESCE(p_user_agent, '')), ''), user_agent),
    device_label = COALESCE(NULLIF(TRIM(COALESCE(p_device_label, '')), ''), device_label),
    platform = COALESCE(NULLIF(TRIM(COALESCE(p_platform, '')), ''), platform)
  WHERE id = r.id;

  RETURN jsonb_build_object('ok', true, 'session_id', r.id, 'action', 'touched');
END;
$$;

CREATE OR REPLACE FUNCTION public.is_user_session_active(p_session_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_sessions
    WHERE id = p_session_id
      AND user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.register_single_user_session(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_user_session(text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_user_session_active(uuid) TO authenticated;
