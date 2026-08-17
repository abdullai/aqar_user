-- جذر المشكلة: anon = 0 حتى بعد force — نفّذ كل قسم لوحده

-- (0) هل الجدول فارغ أصلاً؟
SELECT count(*)::bigint AS total_rows_in_properties FROM public.properties;

-- (1) كل قيم status (بما فيها deleted)
SELECT coalesce(status::text, '<null>') AS status, count(*)::bigint AS n
FROM public.properties
GROUP BY 1
ORDER BY n DESC;

-- (2) نوع عمود status
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'properties'
  AND column_name IN ('status', 'workflow_stage', 'home_feed_suppressed');

-- (3) كمشرف بدون أي فلتر
SELECT count(*)::bigint AS superuser_sees_all FROM public.properties;

-- (4) سياسات anon على properties — هل توجد PERMISSIVE؟
SELECT policyname, permissive, roles::text, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd IN ('SELECT', 'ALL')
ORDER BY policyname;

-- (5) RESTRICTIVE (إن وُجدت ولا يمرّ أي صف لـ anon)
SELECT policyname, qual::text
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND permissive = 'RESTRICTIVE';

-- (6) سياسة تجريبية ضيقة جداً — هل anon يرى شيئاً؟
DROP POLICY IF EXISTS "properties_anon_debug_any_non_deleted" ON public.properties;

CREATE POLICY "properties_anon_debug_any_non_deleted"
  ON public.properties
  FOR SELECT
  TO anon
  USING (status::text IS DISTINCT FROM 'deleted');

SET ROLE anon;
SELECT count(*)::bigint AS anon_with_debug_policy_only
FROM public.properties;
RESET ROLE;

-- إن (6) > 0: المشكلة في شرط properties_public_home_select (status/workflow).
-- إن (6) = 0 و (0) > 0: RESTRICTIVE أو كل الصفوف deleted أو GRANT.
--   → نفّذ APPLY_NOW_nuclear_why_anon_sees_zero.sql
-- إن (0) = 0: لا بيانات — أنشئ إعلاناً من التطبيق.
