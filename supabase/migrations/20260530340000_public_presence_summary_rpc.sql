-- =============================================================================
-- 2026-05-30 — RPC عام لآخر نشاط بطاقات الإعلانات/الطلبات
-- =============================================================================
-- السبب:
--   • بطاقات الرئيسية يجب أن تعرض «متصل الآن» للجميع (مسجّل أو ضيف)
--     لكن عمود users_profiles.chat_last_seen_at محمي بـ RLS ولا يُقرأ من anon.
--   • نُنشئ SECURITY DEFINER RPC تُرجع الحد الأدنى الضروري فقط
--     (online_now: bool, last_seen_at: timestamptz, hidden: bool).
--
-- خصوصية:
--   • إن كان المستخدم أخفى وقت ظهوره (chat_last_seen_hidden=true) نُرجع hidden=true
--     ولا نُعيد التاريخ الفعلي.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_user_presence_summary(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last  timestamptz;
  v_hide  boolean := false;
  v_recent boolean := false;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_user_id');
  END IF;

  SELECT chat_last_seen_at, coalesce(chat_last_seen_hidden, false)
    INTO v_last, v_hide
  FROM public.users_profiles
  WHERE user_id = p_user_id
  LIMIT 1;

  v_recent := v_last IS NOT NULL
    AND v_last > timezone('utc', now()) - interval '60 seconds';

  RETURN jsonb_build_object(
    'ok', true,
    'online_now', v_recent,
    'hidden', v_hide,
    'last_seen_at', CASE
      WHEN v_hide AND NOT v_recent THEN NULL
      ELSE v_last
    END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_presence_summary(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_presence_summary(uuid)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_user_presence_summary(uuid) IS
  'Public presence summary for cards: returns online_now, hidden, and last_seen_at (hidden when user opted-out and not currently online).';

COMMIT;

-- =============================================================================
-- اختبار سريع:
--   SELECT public.get_user_presence_summary('00000000-0000-0000-0000-000000000000');
-- =============================================================================
