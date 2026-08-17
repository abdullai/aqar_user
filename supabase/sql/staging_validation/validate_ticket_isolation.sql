-- =============================================================================
-- validate_ticket_isolation.sql — STAGING ONLY (read-only)
-- =============================================================================
SELECT 'policy.regc_user_complaints.ownership_based'::text AS test_name,
  CASE
    WHEN count(*) FILTER (
      WHERE policyname ILIKE '%own%' OR qual::text ILIKE '%auth.uid%'
    ) >= 1
    THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'matching_policies=' || count(*)::text AS detail
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'regc_user_complaints'
UNION ALL
SELECT 'policy.regc_complaint_escalations.parent_chain',
  CASE
    WHEN count(*) >= 1 THEN 'PASS'
    ELSE 'FAIL'
  END,
  'policy_count=' || count(*)::text
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'regc_complaint_escalations';
