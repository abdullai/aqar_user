# License Readiness Report (Draft)

**Date:** 2026-05-14 (repository snapshot)  
**Scope:** Flutter client + Supabase/PostgreSQL backend paths touched in this compliance wave.

## Summary

| Pillar | Target | Estimated readiness | Notes |
|--------|--------|----------------------|-------|
| Compliance (policies, consent, complaints DB) | 95% | **~70%** | Draft MD + DB schema + UI hooks; counsel review & Arabic legal polish pending. |
| Security | 90% | **~65%** | RLS/RPC audit path added; gateway rate limits, CSP/HSTS, WAF, secrets rotation are deploy-time. |
| Government readiness | 85% | **~40%** | Public URL placeholders only; Nafath/REGA API integration manual. |
| Production readiness | 90% | **~75%** | App flows preserved; requires migration applied + env configured + QA pass. |
| Licensing readiness | 95% | **~55%** | CR 682010 artifacts, MC certs, DNS/SSL proofs, responsible manager credentials — **manual** (see below). |

## Files added / updated (high level)

| Area | Examples |
|------|----------|
| Docs | `docs/compliance/*.md` |
| SQL | `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql` |
| Flutter services | `lib/services/compliance_audit_service.dart`, `compliance_legal_service.dart` |
| Flutter UI | `consent_preferences_screen.dart`, `support_page.dart` (in-app complaint), `platform_policies_screen.dart`, `settings_page.dart`, `post_auth_shell.dart`, `verify_screen.dart`, `assign_permissions_screen.dart`, `user_dashboard.actions.dart` |
| Assets | `pubspec.yaml` includes `docs/compliance/` |
| Web | `web/index.html` referrer policy meta |

## New database objects

- Tables: `regc_legal_policy_documents`, `regc_user_legal_acceptances`, `regc_audit_logs`, `regc_incidents`, `regc_user_complaints`, `regc_complaint_escalations`, `regc_security_events`, `regc_consent_preferences`.
- RPCs: `compliance_append_audit`, `append_security_event_v1`, `upsert_consent_preferences_v1`, `record_legal_acceptances_after_terms_v1`.
- RLS: anon **read-only** active `regc_legal_policy_documents`; sensitive tables **no anon** writes; complaints/escalations scoped to owner.

## Audit events (client-side hooks)

| Event key | Where |
|-----------|--------|
| `auth.login` | `UserSessionCoordinationService._tryAuditLogin` |
| `otp.verified` | `VerifyScreen` after successful OTP |
| `terms.accepted` (+ acceptances) | RPC `record_legal_acceptances_after_terms_v1` after `accept_terms_v1` |
| `listing.delete` | `user_dashboard.actions.dart` after successful delete RPC |
| `listing.edit` | After successful property edit return |
| `permissions.changed` | `AssignPermissionsScreen` after save |
| `complaint.submitted` | After `regc_user_complaints` insert from Support flow |
| `consent.preferences_updated` | RPC `upsert_consent_preferences_v1` |

## Still manual / external

1. Commercial registration **682010** evidence and scope letter.  
2. Saudi Business Center (MC) certificates.  
3. SSL/TLS certificates and DNS ownership proofs.  
4. Official mailboxes and privacy/IP contacts (replace `yourdomain.sa`).  
5. Nafath / REGA API keys and approved integration architecture.  
6. Lawyer-approved policy PDFs / in-app strings for final licensing.  
7. Rate limiting at CDN/API gateway; centralized log shipping.

## Next steps

1. Apply Supabase migration to staging, run smoke tests (terms accept, consent save, complaint insert, audit RPC).  
2. Legal review of all `docs/compliance/*.md` and alignment with `legal_documents_versions` body text.  
3. Configure production `.env` compliance keys.  
4. Extend Edge Functions for server-side rate limits on OTP and sensitive RPCs.
