-- =============================================================================
-- validate_realtime_authorization.sql — STAGING ONLY (read-only)
-- Supabase exposes tables to realtime via publication — verify inventory.
-- =============================================================================
SELECT 'publication.supabase_realtime.exists'::text AS test_name,
  CASE WHEN EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
    THEN 'PASS' ELSE 'FAIL' END AS status,
  'catalog_check' AS detail
UNION ALL
SELECT 'publication.supabase_realtime.table_count',
  'PASS'::text,
  'listed_tables=' || count(*)::text
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime';
