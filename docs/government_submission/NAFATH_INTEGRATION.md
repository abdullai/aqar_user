# Nafath integration (plan)

## Target architecture

1. **OIDC / OAuth2** with Nafath as IdP (exact flow per approved integration guide).  
2. Supabase **Third-party auth** or custom JWT exchange Edge Function.  
3. Map national ID / UUID claims to `auth.users` metadata — **never** trust unsigned JWT fields.

## App changes (future)

- Web + mobile deep link return handler.  
- Step-up MFA for high-risk actions (contracts, payouts).

## Until integration is live

- Use public portal URL for user education only (`nafathPublicUrl()`).  
- Do **not** ship mock endpoints on production Supabase.

See `MOCK_INTEGRATIONS.md` for demo-only guidance.
