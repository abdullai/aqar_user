-- =============================================================================
-- 2026-05-30 — متصل الآن وآخر ظهور لحظي
-- =============================================================================
-- الهدف:
--   1) كل نبضة [ping_app_presence] للمستخدم المسجّل تُحدّث أيضاً
--      [users_profiles.chat_last_seen_at] حتى تنعكس فوراً على بطاقات الإعلان
--      وطلبات السوق (يوجد بالفعل اشتراك Realtime على users_profiles داخل
--      [UserPresenceStrip]).
--   2) [get_app_audience_stats] يقصّر النافذة إلى 90 ثانية (من 4 دقائق) ليتوافق
--      مع نبضات العميل القصيرة الجديدة (≤ 20 ثانية).
--   3) عند تسجيل الخروج / إخفاء التبويب: يستطيع العميل إرسال نبضة وداع تُسجّل
--      [chat_last_seen_at] فوراً (سنفعّلها من Flutter).
--
-- ملاحظات أمان: SECURITY DEFINER + بدون مدخلات حسّاسة. النبضة تتطلّب فقط
-- p_client_key لا يكشف هوية. تحديث chat_last_seen_at يتم لحامل الجلسة فقط
-- (auth.uid()).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (1) ping_app_presence: نبضة + تحديث آخر ظهور للمستخدم المسجّل
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ping_app_presence(p_client_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  k    text := left(trim(coalesce(p_client_key, '')), 512);
  v_uid uuid := auth.uid();
BEGIN
  IF length(k) < 8 THEN
    RETURN;
  END IF;

  -- 1) نبضة الإحصاء العام (الضيف + المسجّل).
  INSERT INTO public.app_presence_heartbeats (client_key, last_seen)
  VALUES (k, timezone('utc', now()))
  ON CONFLICT (client_key) DO UPDATE
    SET last_seen = timezone('utc', now());

  -- 2) آخر ظهور حقيقي للمستخدم المسجّل — يظهر على بطاقات السوق والإعلانات.
  IF v_uid IS NOT NULL
     AND to_regclass('public.users_profiles') IS NOT NULL THEN
    UPDATE public.users_profiles
       SET chat_last_seen_at = timezone('utc', now())
     WHERE user_id = v_uid;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.ping_app_presence(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ping_app_presence(text) TO anon;
GRANT EXECUTE ON FUNCTION public.ping_app_presence(text) TO authenticated;

COMMENT ON FUNCTION public.ping_app_presence(text) IS
  'Heartbeat: refreshes app_presence_heartbeats and (for signed-in users) users_profiles.chat_last_seen_at — used by realtime online indicator.';

-- ---------------------------------------------------------------------------
-- (2) ping_app_offline: نبضة وداع — تسجّل آخر ظهور قبل الخروج
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ping_app_offline()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;
  IF to_regclass('public.users_profiles') IS NOT NULL THEN
    -- عند الخروج: نضع الزمن قبل عتبة الـ "online" بثوانٍ كافية حتى يظهر
    -- «آخر ظهور» مباشرة بدلاً من «متصل الآن» المتجمّد.
    UPDATE public.users_profiles
       SET chat_last_seen_at = timezone('utc', now()) - interval '90 seconds'
     WHERE user_id = v_uid;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.ping_app_offline() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ping_app_offline() TO authenticated;

COMMENT ON FUNCTION public.ping_app_offline() IS
  'Mark current user as offline immediately (sets chat_last_seen_at to ~90s ago) — used on tab close / logout for instant "last active" UI.';

-- ---------------------------------------------------------------------------
-- (3) get_app_audience_stats: نافذة أقصر (90 ثانية)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_app_audience_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reg bigint := 0;
  v_on  bigint := 0;
BEGIN
  IF to_regclass('public.users_profiles') IS NOT NULL THEN
    SELECT COUNT(*)::bigint INTO v_reg FROM public.users_profiles;
  END IF;

  IF to_regclass('public.app_presence_heartbeats') IS NOT NULL THEN
    SELECT COUNT(*)::bigint INTO v_on
    FROM public.app_presence_heartbeats
    WHERE last_seen > (timezone('utc', now()) - interval '90 seconds');
  ELSIF to_regclass('public.user_sessions') IS NOT NULL THEN
    SELECT COUNT(DISTINCT user_id)::bigint INTO v_on
    FROM public.user_sessions
    WHERE last_active > (timezone('utc', now()) - interval '90 seconds');
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
  'registered_users from users_profiles; online_now from app_presence_heartbeats within last 90s (real-time presence).';

-- ---------------------------------------------------------------------------
-- (4) اطمئن إلى وجود index سريع على chat_last_seen_at (للاستعلامات اللحظية).
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.users_profiles') IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name   = 'users_profiles'
         AND column_name  = 'chat_last_seen_at'
     ) THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_users_profiles_chat_last_seen_at
             ON public.users_profiles (chat_last_seen_at DESC)';
  END IF;
END;
$$;

COMMIT;
