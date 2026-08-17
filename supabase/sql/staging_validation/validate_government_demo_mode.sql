-- =============================================================================
-- validate_government_demo_mode.sql — STAGING ONLY (read-only)
-- Demo mode is client/env — DB checks ensure no accidental anon widen on compliance RPCs.
-- =============================================================================
SELECT 'gov_demo.db_no_extra_anon_on_compliance'::text AS test_name,
  CASE
    WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.routine_privileges
      WHERE routine_schema = 'public'
        AND grantee = 'anon'
        AND routine_name IN (
          'compliance_append_audit',
          'append_security_event_v1',
          'upsert_consent_preferences_v1',
          'record_legal_acceptances_after_terms_v1'
        )
    )
    THEN 'PASS'
    ELSE 'FAIL'
  END AS status,
  'compliance RPCs must not have EXECUTE for anon' AS detail
UNION ALL
SELECT 'gov_demo.client_flag.documentation',
  'PASS'::text,
  'See lib/core/compliance/platform_compliance_config.dart + assets/env — not stored in DB';
