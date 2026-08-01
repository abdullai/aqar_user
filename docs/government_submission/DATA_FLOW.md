# Data flow

## Registration / login

User → Supabase Auth → `auth.users` → trigger/profile rows in `public.users_profiles` (existing schema).

## Listings & media

User → Flutter → PostgREST → `properties` / storage buckets → CDN URLs.

## Compliance

User → RPC / `regc_*` tables:

- Terms accept → `accept_terms_v1` + `record_legal_acceptances_after_terms_v1` → `regc_user_legal_acceptances`, `regc_consent_preferences`, `regc_audit_logs`.  
- Complaint → `regc_user_complaints` + audit.  
- Consent update → `upsert_consent_preferences_v1`.

## Government (future)

REGA/Nafath → **Edge Function** (service role) → controlled writes to internal tables — **not** directly from mobile anon key.

## PII minimization

- Avoid caching national ID in logs.  
- Redact tokens in analytics pipelines.
