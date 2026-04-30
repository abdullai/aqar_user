-- =============================================================================
-- إصلاح: infinite recursion detected in policy for relation "users_profiles" (42P17)
--
-- السبب الشائع: سياسة على جدول A تقرأ users_profiles، وسياسة على users_profiles
-- تقرأ A (أو تعيد استعلام users_profiles) → حلقة لا نهائية عند التقييم.
--
-- هنا نعالج حلقة in_app_notifications ↔ users_profiles عبر دوال SECURITY DEFINER
-- تقرأ صف المستخدم الحالي دون إعادة تقييم RLS على users_profiles داخل السياسة.
--
-- نفّذ في Supabase → SQL Editor. راجع بعدها إن استمر الخطأ (انظر نهاية الملف).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- دوال مساعدة (تجاوز RLS داخلياً لأن الدالة تعمل بصلاحية المالِك/SECURITY DEFINER)
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
-- إعادة سياسات in_app_notifications بدون EXISTS على users_profiles
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

COMMIT;

-- =============================================================================
-- إن استمر خطأ التكرار بعد هذا الملف:
--
-- 1) اعرض سياسات users_profiles:
--    SELECT pol.polname, pg_get_expr(pol.polqual, pol.polrelid) AS using_expr,
--           pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check
--    FROM pg_policy pol
--    JOIN pg_class c ON c.oid = pol.polrelid
--    WHERE c.relname = 'users_profiles' AND c.relnamespace = 'public'::regnamespace;
--
-- 2) ابحث عن أي USING / WITH CHECK يحتوي فرعياً على:
--    "FROM public.users_profiles" أو "FROM users_profiles"
--    داخل سياسة على users_profiles نفسها → استبدله بـ app_rls_my_profile_org_id()
--    أو بدالة DEFINER مخصصة (مثلاً للتحقق من عضوية فريق دون SELECT متداخل على نفس الجدول).
-- =============================================================================
