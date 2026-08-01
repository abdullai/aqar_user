# Authentication flow (high level)

```mermaid
sequenceDiagram
  participant U as User / Browser
  participant A as Flutter App
  participant S as Supabase Auth
  participant P as PostgREST API

  U->>A: Credentials / OTP
  A->>S: signIn / verify
  S-->>A: access JWT + refresh
  A->>P: HTTPS + apikey(anon) + Bearer(JWT)
  P->>P: set_config('request.jwt.claims', …)
  P->>P: RLS (auth.uid())
```

## Notes

- **Never** ship `service_role` in `A`.  
- Web: consider idle timeout (`web_session_ttl` pattern).

## Evidence

- `docs/regulatory_evidence/JWT_VALIDATION_EVIDENCE.md`  
- `supabase/sql/staging_validation/validate_jwt_claims.sql`
