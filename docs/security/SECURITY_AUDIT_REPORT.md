# Security Audit Report (Repository + Supabase alignment)

**Scope:** Flutter client (`aqar_user`), Supabase Postgres/RLS, web shell, storage as referenced in repo.  
**Method:** Static review + SQL inventory scripts; **not** a full penetration test.

## Executive summary

| Area | Status | Notes |
|------|--------|--------|
| Auth (Supabase) | Partially verified | JWT validation delegated to SDK; test forged tokens via REST. |
| RLS (`regc_*`) | Inventory via SQL | Run `supabase/sql/audit_rls_regc_privileges_and_policies.sql`. |
| Anon write surface | Designed deny | Confirm no `INSERT`/`UPDATE` on audit tables for `anon`. |
| Secrets in client | Risk | Never ship service_role; rotate anon key if leaked. |
| Web headers | Partial | `Referrer-Policy` set in `web/index.html`; full CSP conflicts with Maps — use CDN/WAF in prod. |
| Rate limiting | Gap | Enforce at API gateway / Edge Functions; not fully in-repo. |

## Privilege matrix (expected)

Canonical extended matrix: [`PRIVILEGE_MATRIX.md`](PRIVILEGE_MATRIX.md).

| Role | `regc_legal_policy_documents` | `regc_audit_logs` | `regc_user_complaints` | RPC `compliance_append_audit` |
|------|------------------------------|-------------------|-------------------------|--------------------------------|
| anon | SELECT (active) | no direct insert | no | no |
| authenticated | SELECT | SELECT own; insert via RPC only | INSERT/SELECT own | EXECUTE |
| service_role | bypass RLS | admin ops only | break-glass | n/a in client |

## JWT & session

- **Validation:** Supabase client verifies JWT signature and expiry.
- **Session hijacking / replay:** Web tab binding + idle re-auth (see `web_auth_tab_guard`, `web_session_ttl`); extend with refresh rotation policies in Supabase Auth settings.
- **Refresh tokens:** Configure rotation & reuse detection in Supabase dashboard.

## OWASP-oriented checklist (high level)

1. **Injection:** Prefer RPC/parameterized queries; RLS as second layer.  
2. **Broken access:** RLS + ownership checks on `regc_*`.  
3. **Sensitive data exposure:** TLS; no PII in client logs.  
4. **XSS (web):** Flutter web minimizes raw HTML; audit any `HtmlWidget` if added.  
5. **CSRF:** Supabase uses bearer tokens; same-site cookies for hosted auth where applicable.  
6. **Security misconfiguration:** Lock Storage buckets; review Realtime channel filters.  
7. **Brute force / OTP abuse:** Use Supabase rate limits + `login_security` patterns in app; add Edge rate cap for OTP RPCs in production.

## Audit logging integrity

- `regc_audit_logs` append via `compliance_append_audit` (SECURITY DEFINER); clients cannot set arbitrary `user_id` in RPC body.
- **Tampering:** DBAs can always modify data; mitigate with restricted roles + optional append-only tablespace / external SIEM export.

## Next actions (human / ops)

- [ ] Run behavioral matrix (`supabase/sql/audit_rls_behavioral_test_matrix.md`) from staging.  
- [ ] Enable Supabase Auth hooks / leaked password protection if applicable.  
- [ ] WAF + bot management on public API host.  
- [ ] Third-party pentest before licensing submission.

## References

- `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql`  
- `supabase/sql/audit_rls_regc_privileges_and_policies.sql`
