# Production Hardening Checklist

Use as a release gate before production cutover.

## Supabase

- [ ] RLS enabled on all user-data tables (inventory: `audit_rls_regc_privileges_and_policies.sql`).
- [ ] `service_role` key only in server/CI secrets — not in Flutter bundle.
- [ ] Auth: email confirmations, password policy, MFA policy for staff accounts.
- [ ] Storage buckets: public vs private; signed URLs for private assets.
- [ ] Realtime: channel authorization matches RLS semantics.
- [ ] Database backups + PITR enabled (per Supabase plan).
- [ ] Least privilege DB roles for any custom roles (`admin` pattern) — avoid broad `GRANT ALL`.

## Flutter / Web

- [ ] `--dart-define` / CI secrets for `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
- [ ] Web idle + tab binding verified (`web_session_ttl`, `WebAuthTabGuard`).
- [ ] Error screens do not leak stack traces to end users in release mode.
- [ ] File uploads: size limits, type allow-list, server-side virus scan (placeholder acceptable until gateway exists).

## Network / Edge

- [ ] TLS 1.2+ everywhere; HSTS at CDN.
- [ ] WAF rules: OWASP CRS baseline; geo block if required.
- [ ] CORS: restrict origins to app + admin hosts only.

## Compliance hooks

- [ ] `regc_*` migrations applied in staging + smoke tests (terms accept, complaint, consent).
- [ ] Legal/policy version in `regc_legal_policy_documents` matches `legal_documents_versions` gate where applicable.

## Monitoring

- [ ] Sentry / Logflare / Supabase logs wired with redaction.
- [ ] Alerts on auth anomaly spikes.
