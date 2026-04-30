-- =============================================================================
-- الحل الموحّد (نفّذ هذا الملف مرة واحدة في Supabase → SQL Editor)
--
-- يعالج:
--   1) دوال RLS الآمنة (SECURITY DEFINER + search_path)
--   2) سياسات SELECT/UPDATE لـ in_app_notifications بدون EXISTS على users_profiles
--   3) حذف سياسة SELECT المكررة "read own notifications" (سبب شائع لـ 500 عند جلب OTP)
--   4) سياسة DELETE موحّدة مع نفس مفتاح username
--
-- آمن لإعادة التنفيذ (idempotent). لا تمنح الدالة لـ anon.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) دوال مساعدة — تقرأ صف المستخدم الحالي دون حلقة سياسات على نفس الاستعلام
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.app_rls_my_profile_username()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT nullif(trim(both from up.username::text), '')
  FROM public.users_profiles up
  WHERE up.user_id = auth.uid()
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.app_rls_my_profile_org_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT up.org_id
  FROM public.users_profiles up
  WHERE up.user_id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.app_rls_my_profile_username() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_rls_my_profile_username() TO authenticated;
GRANT EXECUTE ON FUNCTION public.app_rls_my_profile_username() TO service_role;

REVOKE ALL ON FUNCTION public.app_rls_my_profile_org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.app_rls_my_profile_org_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.app_rls_my_profile_org_id() TO service_role;

-- ---------------------------------------------------------------------------
-- 2) إزالة السياسة المكررة التي تستدعي EXISTS على users_profiles
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "read own notifications" ON public.in_app_notifications;

-- ---------------------------------------------------------------------------
-- 3) سياسات in_app_notifications (SELECT / UPDATE / DELETE) — كلها عبر الدالة
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS in_app_notifications_select_own_username ON public.in_app_notifications;
CREATE POLICY in_app_notifications_select_own_username ON public.in_app_notifications
  FOR SELECT TO authenticated
  USING (
    username IS NOT NULL
    AND trim(both from in_app_notifications.username::text)
        = coalesce(public.app_rls_my_profile_username(), '')
    AND coalesce(public.app_rls_my_profile_username(), '') <> ''
  );

DROP POLICY IF EXISTS in_app_notifications_update_own_username ON public.in_app_notifications;
CREATE POLICY in_app_notifications_update_own_username ON public.in_app_notifications
  FOR UPDATE TO authenticated
  USING (
    username IS NOT NULL
    AND trim(both from in_app_notifications.username::text)
        = coalesce(public.app_rls_my_profile_username(), '')
    AND coalesce(public.app_rls_my_profile_username(), '') <> ''
  )
  WITH CHECK (
    username IS NOT NULL
    AND trim(both from in_app_notifications.username::text)
        = coalesce(public.app_rls_my_profile_username(), '')
    AND coalesce(public.app_rls_my_profile_username(), '') <> ''
  );

DROP POLICY IF EXISTS in_app_notifications_delete_own_username ON public.in_app_notifications;
CREATE POLICY in_app_notifications_delete_own_username ON public.in_app_notifications
  FOR DELETE TO authenticated
  USING (
    username IS NOT NULL
    AND trim(both from in_app_notifications.username::text)
        = coalesce(public.app_rls_my_profile_username(), '')
    AND coalesce(public.app_rls_my_profile_username(), '') <> ''
  );

COMMIT;

-- =============================================================================
-- بعد التنفيذ: جرّب تسجيل الدخول ثم شاشة التحقق — يفترض أن تختفي أخطاء 500
-- على in_app_notifications و users_profiles الناتجة عن تقييم السياسة المكررة.
--
-- إن بقي 500 على SELECT users_profiles فقط: راجع سياسات users_profiles التي
-- تستخدم EXISTS فرعياً على users_profiles (انظر 20260412 نهاية الملف).
-- =============================================================================
