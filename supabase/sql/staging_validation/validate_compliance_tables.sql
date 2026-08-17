-- =============================================================================
-- validate_compliance_tables.sql — STAGING ONLY (read-only)
-- =============================================================================
SELECT 'table.regc_legal_policy_documents.exists'::text AS test_name,
  CASE WHEN to_regclass('public.regc_legal_policy_documents') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_legal_policy_documents')::text, 'MISSING') AS detail
UNION ALL
SELECT 'table.regc_user_legal_acceptances.exists',
  CASE WHEN to_regclass('public.regc_user_legal_acceptances') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_user_legal_acceptances')::text, 'MISSING')
UNION ALL
SELECT 'table.regc_audit_logs.exists',
  CASE WHEN to_regclass('public.regc_audit_logs') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_audit_logs')::text, 'MISSING')
UNION ALL
SELECT 'table.regc_user_complaints.exists',
  CASE WHEN to_regclass('public.regc_user_complaints') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_user_complaints')::text, 'MISSING')
UNION ALL
SELECT 'table.regc_complaint_escalations.exists',
  CASE WHEN to_regclass('public.regc_complaint_escalations') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_complaint_escalations')::text, 'MISSING')
UNION ALL
SELECT 'table.regc_security_events.exists',
  CASE WHEN to_regclass('public.regc_security_events') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_security_events')::text, 'MISSING')
UNION ALL
SELECT 'table.regc_consent_preferences.exists',
  CASE WHEN to_regclass('public.regc_consent_preferences') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_consent_preferences')::text, 'MISSING')
UNION ALL
SELECT 'table.regc_incidents.exists',
  CASE WHEN to_regclass('public.regc_incidents') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
  coalesce(to_regclass('public.regc_incidents')::text, 'MISSING')
ORDER BY 1;
