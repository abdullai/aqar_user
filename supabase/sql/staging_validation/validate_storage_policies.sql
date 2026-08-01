-- =============================================================================
-- validate_storage_policies.sql — STAGING ONLY (read-only)
-- Lists storage.* policies + summary row.
-- =============================================================================
WITH policies AS (
  SELECT tablename, policyname, cmd::text AS cmd, coalesce(roles::text, '') AS roles
  FROM pg_policies
  WHERE schemaname = 'storage'
),
detail AS (
  SELECT 'storage.policy.' || tablename || '.' || policyname AS test_name,
    'PASS'::text AS status,
    'cmd=' || cmd || ' roles=' || roles AS detail
  FROM policies
),
summary AS (
  SELECT 'storage.policies.total_count'::text AS test_name,
    'PASS'::text AS status,
    'count=' || (SELECT count(*)::text FROM policies) ||
      ' (review Supabase UI if 0)' AS detail
)
SELECT * FROM detail
UNION ALL
SELECT * FROM summary
ORDER BY test_name;
