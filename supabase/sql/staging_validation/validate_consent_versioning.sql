-- =============================================================================
-- validate_consent_versioning.sql — STAGING ONLY (read-only)
-- =============================================================================
WITH idx AS (
  SELECT count(*)::int AS cnt
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND tablename = 'regc_legal_policy_documents'
    AND indexname = 'legal_policy_documents_one_active_per_lang_type'
),
active_rows AS (
  SELECT policy_type, language, count(*) FILTER (WHERE active) AS active_cnt
  FROM public.regc_legal_policy_documents
  GROUP BY policy_type, language
)
SELECT 'index.one_active_per_lang_type.exists'::text AS test_name,
  CASE WHEN (SELECT cnt FROM idx) = 1 THEN 'PASS' ELSE 'FAIL' END AS status,
  'index_found=' || (SELECT cnt FROM idx)::text AS detail
UNION ALL
SELECT 'seed.active_policy_rows.no_duplicate_active',
  CASE WHEN count(*) = 0 THEN 'WARN'
       WHEN bool_and(active_cnt <= 1) THEN 'PASS'
       ELSE 'FAIL' END,
  'groups_checked=' || count(*)::text
FROM active_rows;
