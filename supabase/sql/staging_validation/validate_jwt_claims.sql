-- =============================================================================
-- validate_jwt_claims.sql — STAGING ONLY (read-only)
-- Validates compliance RPCs are not executable by anon (DB catalog view).
-- Full JWT crypto tests are REST / client-side.
-- =============================================================================
WITH compliance_routines AS (
  SELECT unnest(ARRAY[
    'compliance_append_audit',
    'append_security_event_v1',
    'upsert_consent_preferences_v1',
    'record_legal_acceptances_after_terms_v1'
  ]) AS routine_name
),
anon_grants AS (
  SELECT r.routine_name, count(*)::int AS anon_cnt
  FROM information_schema.routine_privileges r
  JOIN compliance_routines c ON c.routine_name = r.routine_name
  WHERE r.routine_schema = 'public'
    AND r.grantee = 'anon'
  GROUP BY r.routine_name
),
auth_grants AS (
  SELECT r.routine_name, count(*)::int AS auth_cnt
  FROM information_schema.routine_privileges r
  JOIN compliance_routines c ON c.routine_name = r.routine_name
  WHERE r.routine_schema = 'public'
    AND r.grantee = 'authenticated'
  GROUP BY r.routine_name
)
SELECT c.routine_name || '.no_anon_execute'::text AS test_name,
  CASE WHEN coalesce(a.anon_cnt, 0) = 0 THEN 'PASS' ELSE 'FAIL' END AS status,
  'anon_grants=' || coalesce(a.anon_cnt, 0)::text AS detail
FROM compliance_routines c
LEFT JOIN anon_grants a ON a.routine_name = c.routine_name
UNION ALL
SELECT c.routine_name || '.authenticated_execute',
  CASE WHEN coalesce(b.auth_cnt, 0) >= 1 THEN 'PASS' ELSE 'WARN' END,
  'authenticated_grants=' || coalesce(b.auth_cnt, 0)::text
FROM compliance_routines c
LEFT JOIN auth_grants b ON b.routine_name = c.routine_name
ORDER BY 1;
