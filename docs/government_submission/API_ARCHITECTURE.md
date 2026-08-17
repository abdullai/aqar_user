# API architecture

## Consumer app

- **Transport:** HTTPS to `SUPABASE_URL`.  
- **Auth header:** `Authorization: Bearer <user JWT>` after login.  
- **Data access:** PostgREST auto-generated REST + RPC via `supabase_flutter`.

## Edge Functions (recommended additions)

| Function | Purpose |
|----------|---------|
| `rate-limit-otp` | Throttle OTP verify attempts by IP + phone hash |
| `rega-webhook` | Verify signatures from REGA callbacks |
| `export-audit` | SIEM export (service role, scheduled) |

## Admin (future)

Separate deployment using **service_role** on VPC or IP allow-listed runner — **never** inside consumer APK/IPA.

## Versioning

- Contract tests for critical RPC names used in app (`accept_terms_v1`, `compliance_append_audit`, …).
