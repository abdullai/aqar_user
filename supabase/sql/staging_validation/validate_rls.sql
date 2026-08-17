-- =============================================================================
-- validate_rls.sql — STAGING ONLY (read-only)
-- Verifies RLS is enabled on public.regc_* tables. Does not modify data.
-- =============================================================================
WITH regc_tables AS (
  SELECT c.relname::text AS table_name,
         c.relrowsecurity AS rls_on,
         c.relforcerowsecurity AS rls_forced
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND c.relname LIKE 'regc\_%' ESCAPE '\'
)
SELECT
  table_name || '.rls_enabled' AS test_name,
  CASE WHEN rls_on THEN 'PASS' ELSE 'FAIL' END AS status,
  'relrowsecurity=' || rls_on::text AS detail
FROM regc_tables
UNION ALL
SELECT
  table_name || '.policy_count',
  CASE WHEN pc.cnt > 0 THEN 'PASS' ELSE 'FAIL' END,
  'policy_count=' || pc.cnt::text
FROM regc_tables t
LEFT JOIN LATERAL (
  SELECT count(*)::int AS cnt
  FROM pg_policies p
  WHERE p.schemaname = 'public' AND p.tablename = t.table_name
) pc ON true
ORDER BY 1;
