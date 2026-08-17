-- =============================================================================
-- validate_audit_logs.sql — STAGING ONLY (read-only)
-- =============================================================================
WITH anon_privs AS (
  SELECT coalesce(
    string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type),
    ''
  ) AS privs
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public'
    AND table_name = 'regc_audit_logs'
    AND grantee = 'anon'
),
policy_cnt AS (
  SELECT count(*)::int AS cnt
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'regc_audit_logs'
),
rpc_anon_cnt AS (
  SELECT count(*)::int AS cnt
  FROM information_schema.routine_privileges
  WHERE routine_schema = 'public'
    AND routine_name = 'compliance_append_audit'
    AND grantee = 'anon'
)
SELECT 'regc_audit_logs.anon_no_insert_update_delete'::text AS test_name,
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
  'anon_privileges=[' || (SELECT privs FROM anon_privs) || ']' AS detail
UNION ALL
SELECT 'regc_audit_logs.has_rls_policies',
  CASE WHEN (SELECT cnt FROM policy_cnt) > 0 THEN 'PASS' ELSE 'FAIL' END,
  'policy_count=' || (SELECT cnt FROM policy_cnt)::text
UNION ALL
SELECT 'compliance_append_audit.not_granted_to_anon',
  CASE WHEN (SELECT cnt FROM rpc_anon_cnt) = 0 THEN 'PASS' ELSE 'FAIL' END,
  'anon_execute_grants=' || (SELECT cnt FROM rpc_anon_cnt)::text;
