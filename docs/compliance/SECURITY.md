# Security Overview

## Objectives

Confidentiality, integrity, and availability of user and listing data, with traceability for compliance investigations.

## Controls (implemented or scaffolded)

| Area | Status |
|------|--------|
| Transport encryption (TLS) | Deploy-time (hosting / CDN). |
| Authentication | Supabase Auth; OTP flow; web tab binding for session isolation. |
| Authorization | PostgreSQL RLS on sensitive tables; RPC `SECURITY DEFINER` for audit append. |
| Session management | Idle policies on web; session epoch coordination (`user_session_state`). |
| Audit logging | `regc_audit_logs` + `user_login_audit`; client hooks for key events. |
| Security events | `regc_security_events` table + `append_security_event_v1` RPC (optional use). |
| Rate limiting | Document here; enforce at API gateway / Edge Functions for production. |
| MFA | UI placeholder in Settings; enable after Nafath/OIDC integration. |
| JWT validation | Handled by Supabase client libraries; rotate keys per Supabase guidance. |
| Device fingerprint | Existing device registration RPCs; extend for risk scoring as needed. |
| CSRF / XSS | Flutter web: prefer strict cookie policies on API domains; sanitize user HTML if introduced. |
| Security headers | `Referrer-Policy` meta on web shell; extend via reverse proxy (CSP, HSTS, X-Frame-Options). |

## Roles

- **End users:** least privilege via RLS.
- **Operators:** service role only in controlled admin backends (not shipped in consumer app).
- **anon:** no write access to compliance tables; read-only active legal policy rows where granted.

## References

- `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql`
- `lib/services/compliance_audit_service.dart`
