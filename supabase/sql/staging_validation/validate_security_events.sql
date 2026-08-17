-- =============================================================================
-- validate_security_events.sql — STAGING ONLY (read-only)
-- =============================================================================
WITH anon_privs AS (
  SELECT coalesce(
    string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type),
    ''
  ) AS privs
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'regc_security_events'
    AND grantee = 'anon'
),
auth_privs AS (
  SELECT coalesce(
    string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type),
    ''
  ) AS privs
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'regc_security_events'
    AND grantee = 'authenticated'
)
SELECT 'regc_security_events.anon_no_dml'::text AS test_name,
  CASE
    WHEN (SELECT privs FROM anon_privs) = ''
      OR (
        strpos((SELECT privs FROM anon_privs), 'INSERT') = 0
        AND strpos((SELECT privs FROM anon_privs), 'UPDATE') = 0
        AND strpos((SELECT privs FROM anon_privs), 'DELETE') = 0
      )
    THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'anon_privs=[' || (SELECT privs FROM anon_privs) || ']' AS detail
UNION ALL
SELECT 'regc_security_events.authenticated_no_direct_insert',
  CASE
    WHEN strpos((SELECT privs FROM auth_privs), 'INSERT') = 0 THEN 'PASS'
    ELSE 'FAIL'
  END,
  'authenticated_table_privs=[' || (SELECT privs FROM auth_privs) || ']'
UNION ALL
SELECT 'append_security_event_v1.grant_authenticated_not_anon',
  CASE
    WHEN EXISTS (
      SELECT 1 FROM information_schema.routine_privileges r
      WHERE r.routine_schema = 'public'
        AND r.routine_name = 'append_security_event_v1'
        AND r.grantee = 'authenticated'
    )
    AND NOT EXISTS (
      SELECT 1 FROM information_schema.routine_privileges r
      WHERE r.routine_schema = 'public'
        AND r.routine_name = 'append_security_event_v1'
        AND r.grantee = 'anon'
    )
    THEN 'PASS'
    ELSE 'FAIL'
  END,
  'verify routine_privileges for append_security_event_v1';
