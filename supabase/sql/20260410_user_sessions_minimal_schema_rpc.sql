-- =============================================================================
-- جدول user_sessions بصيغة مبسّطة (كما عندك):
--   id uuid, user_id uuid, device text, last_active timestamptz, created_at timestamptz
--
-- الدالتان يخزّنان في [device] نصاً JSON من التطبيق (مستقر للمقارنة، بدون user-agent):
--   {"install_id":"uuid","platform":"web|android|...","label":"…"}
--
-- نفّذ في Supabase SQL Editor. إن وُجدت دوال قديمة بأربعة بارامترات تُحذف أولاً.
-- =============================================================================

DROP FUNCTION IF EXISTS public.register_single_user_session(text, text, text, text);
DROP FUNCTION IF EXISTS public.reconcile_user_session(text, text, text, text);

CREATE OR REPLACE FUNCTION public.register_single_user_session(p_device text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_device text := COALESCE(NULLIF(TRIM(p_device), ''), 'unknown');
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  DELETE FROM public.user_sessions WHERE user_id = uid;

  INSERT INTO public.user_sessions (user_id, device, last_active, created_at)
  VALUES (uid, v_device, timezone('utc', now()), timezone('utc', now()));

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_user_session(p_device text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  existing text;
  v_device text := COALESCE(NULLIF(TRIM(p_device), ''), 'unknown');
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  SELECT us.device INTO existing
  FROM public.user_sessions us
  WHERE us.user_id = uid
  LIMIT 1;

  IF NOT FOUND THEN
    INSERT INTO public.user_sessions (user_id, device, last_active, created_at)
    VALUES (uid, v_device, timezone('utc', now()), timezone('utc', now()));
    RETURN jsonb_build_object('ok', true, 'action', 'inserted');
  END IF;

  IF existing IS DISTINCT FROM v_device THEN
    RETURN jsonb_build_object('ok', false, 'error', 'session_replaced');
  END IF;

  UPDATE public.user_sessions
  SET last_active = timezone('utc', now())
  WHERE user_id = uid;

  RETURN jsonb_build_object('ok', true, 'action', 'touched');
END;
$$;

REVOKE ALL ON FUNCTION public.register_single_user_session(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reconcile_user_session(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_single_user_session(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_user_session(text) TO authenticated;

-- RLS (عدّل إن كانت سياساتك جاهزة لتجنب التعارض)
ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_sessions_select_own ON public.user_sessions;
CREATE POLICY user_sessions_select_own ON public.user_sessions
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS user_sessions_delete_own ON public.user_sessions;
CREATE POLICY user_sessions_delete_own ON public.user_sessions
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- الإدراج/التحديث عبر دوال SECURITY DEFINER؛ لا حاجة لسياسة INSERT للعميل إن لم تُدرِج من التطبيق مباشرة.

COMMENT ON FUNCTION public.register_single_user_session(text) IS
  'One active row per user in user_sessions; device holds JSON payload from app.';
COMMENT ON FUNCTION public.reconcile_user_session(text) IS
  'Updates last_active or returns session_replaced if device token differs.';
