# Production Readiness Report

## Build & deploy

| Item | Status |
|------|--------|
| Flutter multi-platform (Android/iOS/Web) | Supported |
| Env separation (dev/stage/prod) | Use distinct Supabase projects + distinct `.env` / CI secrets |
| `default.env` in repo | Contains placeholders only — no production secrets |

## Runtime reliability

| Item | Notes |
|------|--------|
| Crash reporting | Integrate Crashlytics/Sentry (placeholder in checklist) |
| Offline / retry | `connectivity_guard` patterns; extend per screen |
| Web performance | Defer heavy maps; profile with Chrome Lighthouse |

## Compliance & security gates

- Complete `docs/security/HARDENING_CHECKLIST.md` before go-live.
- Run `supabase/sql/audit_rls_regc_privileges_and_policies.sql` in staging.

## Readiness score (self-assessment)

**Production readiness:** ~72% — pending WAF, pentest, monitoring, and operator legal artifacts.
