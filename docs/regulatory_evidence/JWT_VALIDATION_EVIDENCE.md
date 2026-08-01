# JWT_VALIDATION_EVIDENCE

## Architectural summary

Supabase Auth issues JWTs signed with the project’s **JWT secret**. The Flutter `supabase_flutter` client validates **signature**, **expiry (`exp`)**, and **issuer** before attaching the token to API calls.

## Claims relevant to RLS

| Claim | Use |
|-------|-----|
| `sub` | Becomes `auth.uid()` in Postgres policies. |
| `exp` | Session expiry enforcement. |
| `role` | Typically `authenticated` for logged-in users. |

## Example audit trail (metadata — mock)

```json
{
  "event_type": "session.token_refreshed",
  "metadata": { "platform": "web", "mock": true },
  "note": "Attach real staging row export to evidence binder"
}
```

## Staging tests (manual / REST)

Document outcomes in this pack:

1. **Expired JWT** — expect `401` from PostgREST.  
2. **Tampered payload** (altered `sub` after signing) — signature failure.  
3. **Wrong project** JWT — signature / issuer mismatch.

**SQL helper (grants, not crypto):** `supabase/sql/staging_validation/validate_jwt_claims.sql`

## Code reference (client)

Session TTL and web guest activity: `lib/core/session/web_session_ttl.dart` (and related session files) — cite file paths in pentest appendix.
