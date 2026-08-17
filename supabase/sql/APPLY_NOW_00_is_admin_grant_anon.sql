-- =============================================================================
-- تشخيص + إصلاح: permission denied for function is_admin (42501)
--
-- يحدث عندما تستدعي سياسة RLS is_admin() ودور anon/authenticated
-- ليس لديه GRANT EXECUTE على الدالة (شائع بعد emergency hardening).
--
-- نفّذ هذا الملف أولاً — ثم APPLY_NOW_v4_property_images_anon_rest.sql
-- =============================================================================

-- (أ) أين يُذكر is_admin في السياسات؟
SELECT tablename,
       policyname,
       roles::text,
       cmd,
       permissive,
       qual::text AS using_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND (
    qual::text ILIKE '%is_admin%'
    OR coalesce(with_check::text, '') ILIKE '%is_admin%'
  )
ORDER BY tablename, policyname;

-- (ب) من يملك EXECUTE على is_admin؟
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS args,
       array_agg(DISTINCT grantee::text ORDER BY grantee::text) AS grantees
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
LEFT JOIN information_schema.routine_privileges rp
  ON rp.specific_schema = n.nspname
 AND rp.routine_name = p.proname
 AND rp.grantee IN ('anon', 'authenticated', 'PUBLIC', 'public')
WHERE n.nspname = 'public'
  AND p.proname = 'is_admin'
GROUP BY p.proname, p.oid;

-- (ج) منح التنفيذ — آمن إذا كانت الدالة تُرجع false لغير المشرفين
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_admin'
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated', r.fn);
    RAISE NOTICE 'GRANT EXECUTE ON % TO anon, authenticated', r.fn;
  END LOOP;
END $$;
