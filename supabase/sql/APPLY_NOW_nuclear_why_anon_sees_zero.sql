-- =============================================================================
-- anon = 0 حتى مع سياسة debug (غير محذوف فقط) → واحد من:
--   • الجدول فارغ
--   • كل الصفوف status = deleted
--   • سياسة RESTRICTIVE تحجب anon
--   • لا GRANT SELECT لـ anon
--
-- نفّذ الملف كاملاً في SQL Editor ثم أرسل نتائج الأقسام 1–4.
-- =============================================================================

-- ── 1) بيانات خام (كمشرف — يتجاوز RLS) ──
SELECT count(*)::bigint AS total_rows FROM public.properties;

SELECT count(*)::bigint AS rows_not_deleted
FROM public.properties
WHERE coalesce(status::text, '') IS DISTINCT FROM 'deleted';

SELECT count(*)::bigint AS rows_published_like
FROM public.properties
WHERE coalesce(status::text, '') IN ('published', 'active', 'available');

SELECT coalesce(status::text, '<null>') AS status, count(*)::bigint AS n
FROM public.properties
GROUP BY 1
ORDER BY n DESC
LIMIT 20;

-- ── 2) صلاحيات الجدول ──
SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'properties'
  AND grantee IN ('anon', 'authenticated', 'PUBLIC')
ORDER BY grantee;

SELECT c.relrowsecurity AS rls_on, c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'properties';

-- ── 3) إزالة RESTRICTIVE (السبب الشائع لـ anon = 0 مع سياسة permissive) ──
DO $$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'properties'
      AND permissive = 'RESTRICTIVE'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.properties', pol.policyname);
    RAISE NOTICE 'Dropped RESTRICTIVE policy: %', pol.policyname;
  END LOOP;
END $$;

-- ── 4) سياسة اختبار: anon يرى كل الصفوف (مؤقتة للتشخيص فقط) ──
BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;

DROP POLICY IF EXISTS "properties_anon_debug_read_all_rows_test" ON public.properties;

CREATE POLICY "properties_anon_debug_read_all_rows_test"
  ON public.properties
  FOR SELECT
  TO anon
  USING (true);

COMMIT;

SET ROLE anon;
SELECT count(*)::bigint AS anon_sees_with_using_true FROM public.properties;
RESET ROLE;

-- قراءة:
-- • anon_sees_with_using_true = 0 و total_rows > 0  → راجع GRANT / مشروع خاطئ
-- • total_rows = 0  → لا بيانات؛ أنشئ إعلاناً من التطبيق
-- • anon_sees_with_using_true > 0  → أزل سياسة الاختبار وأعد properties_public_home_select

-- ── 5) بعد التأكد: أزل سياسة الاختبار وأعد الرئيسية ──
-- DROP POLICY IF EXISTS "properties_anon_debug_read_all_rows_test" ON public.properties;
-- ثم نفّذ APPLY_NOW_revive_and_show_one_property_anon.sql
