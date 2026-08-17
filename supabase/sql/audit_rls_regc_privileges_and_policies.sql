-- =============================================================================
-- RLS & privilege audit — جداول regc_* + ملخص صلاحيات anon/authenticated
-- شغّل في SQL Editor (دور postgres). للاختبار السلوكي بـ JWT استخدم REST أو supabase tests.
-- =============================================================================

-- A) سياسات RLS على جداول regc_*
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual::text AS using_expression,
  with_check::text AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename LIKE 'regc\_%' ESCAPE '\'
ORDER BY tablename, policyname;

-- B) هل RLS مفعّل؟
SELECT
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_force
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname LIKE 'regc\_%' ESCAPE '\'
ORDER BY c.relname;

-- C) امتيازات الجدول لـ anon / authenticated (جدول ملخص)
SELECT
  table_schema,
  table_name,
  grantee,
  string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name LIKE 'regc\_%' ESCAPE '\'
  AND grantee IN ('anon', 'authenticated', 'service_role', 'postgres')
GROUP BY table_schema, table_name, grantee
ORDER BY table_name, grantee;

-- D) توقعات الامتثال (مرجع يدوي — راجع الصفوف)
-- anon: SELECT على regc_legal_policy_documents فقط عادةً؛ لا INSERT على regc_audit_logs.
-- authenticated: SELECT على سجلاته + RPCs؛ لا INSERT مباشر على regc_audit_logs (عبر RPC فقط).

