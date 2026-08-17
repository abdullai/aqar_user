-- =============================================================================
-- تشخيص GET /users_profiles → 500 (أسماء وتواريخ لا تظهر للمستخدمين القدامى)
--
-- الخطأ من PostgREST/Postgres وليس من Flutter. غالباً:
--   • سياسة RLS على users_profiles تحتوي SELECT متداخل على نفس الجدول (42P17)
--   • أو دالة/مشغّل TRIGGER يفشل عند قراءة صف معيّن
--
-- 1) نفّذ الاستعلامات أدناه في SQL Editor وانسخ النتائج.
-- 2) طبّق سابقاً إن لم تطبّق:
--      supabase/sql/20260422_users_profiles_rls_consolidated_fix.sql
--      (ثم إن لزم) supabase/sql/20260412_fix_users_profiles_rls_recursion.sql
--      supabase/sql/20260416_signup_rls_safe_checks.sql
-- 3) لا تضع app_rls_my_profile_username() داخل USING لسياسة ON users_profiles
--    (يُذكر في 20260416_signup_rls_safe_checks.sql).
-- =============================================================================

-- أسماء سياسات users_profiles + تعبير USING / WITH CHECK
SELECT pol.polname,
       pg_get_expr(pol.polqual, pol.polrelid) AS using_expr,
       pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check_expr
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = 'users_profiles'
  AND n.nspname = 'public'
ORDER BY pol.polname;

-- مشغّلات على الجدول (قد تسبب خطأ عند القراءة)
SELECT tgname, pg_get_triggerdef(oid, true) AS def
FROM pg_trigger
WHERE tgrelid = 'public.users_profiles'::regclass
  AND NOT tgisinternal
ORDER BY tgname;
