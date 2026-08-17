-- =============================================================================
-- Compliance: revoke inherited anon/PUBLIC surface on regc_* + RPCs
--
-- Why: staging validators may show EXECUTE for anon on compliance RPCs and
-- table privileges (REFERENCES/TRIGGER/TRUNCATE/SELECT) on regc_audit_logs /
-- regc_security_events inherited from template defaults or broad grants — even
-- when migration 20260515183000 only granted authenticated.
--
-- Safe: re-applies explicit least privilege for anon (SELECT legal docs only).
-- Idempotent: uses REVOKE then GRANT where needed.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Tables — anon must not touch sensitive regc_* (except legal read)
-- -----------------------------------------------------------------------------
REVOKE ALL PRIVILEGES ON TABLE public.regc_audit_logs FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.regc_security_events FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.regc_user_legal_acceptances FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.regc_user_complaints FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.regc_complaint_escalations FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.regc_incidents FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.regc_consent_preferences FROM anon;

-- Anon: active legal text only (RLS still applies on SELECT)
REVOKE ALL PRIVILEGES ON TABLE public.regc_legal_policy_documents FROM anon;
GRANT SELECT ON TABLE public.regc_legal_policy_documents TO anon;

-- -----------------------------------------------------------------------------
-- 2) RPCs — remove anon/PUBLIC execute; keep authenticated (same as original)
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.compliance_append_audit(text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.append_security_event_v1(text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.upsert_consent_preferences_v1(boolean, boolean, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_legal_acceptances_after_terms_v1(text, text, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.compliance_append_audit(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.append_security_event_v1(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_consent_preferences_v1(boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_legal_acceptances_after_terms_v1(text, text, text) TO authenticated;
