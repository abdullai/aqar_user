# Threat Model (STRIDE-lite) — Motawoq / Aqar User

## Assets

- User accounts & PII (`auth.users`, `users_profiles`, …)
- Listings, contracts, chat metadata
- Compliance evidence (`regc_*` tables)
- Operator secrets (Supabase service role, signing keys) — **off-device only**

## Trust boundaries

1. **Client (Flutter)** — partially hostile (modified builds, rooted devices).  
2. **Supabase API** — Internet-facing; relies on JWT + RLS.  
3. **Postgres** — authoritative data store.  
4. **Storage / Realtime** — must mirror RLS intent with bucket/channel policies.

## Threats & mitigations

| Threat | Mitigation in project |
|--------|------------------------|
| Stolen anon key | RLS; no sensitive reads for anon; rate limit; key rotation. |
| Stolen user JWT | Short TTL; refresh rotation; session epoch / web tab binding. |
| IDOR on complaints | `user_id = auth.uid()` policies on `regc_user_complaints`. |
| Audit spam | RPC only; optional server-side rate cap not yet in migration. |
| SQL injection | Parameterized Supabase client; avoid raw string concat for filters. |
| XSS on web | Flutter default escaping; review WebViews if used for user HTML. |
| Admin abuse | Separate admin app; never embed service_role in consumer app. |

## Out of scope (repo)

- Physical security, SOC staffing, 24/7 monitoring contracts.

## Residual risk

Medium until external pentest + WAF + production auth hardening are complete.
