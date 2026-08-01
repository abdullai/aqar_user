# SESSION_SECURITY_EVIDENCE

## Architectural summary

Sessions are backed by **Supabase Auth** refresh + access tokens. The app adds **idle / web guest** behaviour and background lock preferences where implemented (see `lib/core/session/`).

## Example session validation (mock narrative)

1. User logs in → access JWT stored in secure storage (platform-dependent).  
2. Access token expires → SDK refresh using refresh token (configure **rotation** in dashboard).  
3. Web guest idle beyond TTL → re-auth or guest expiry per product rules.

## Example log snippet (mock)

```json
{ "event_type": "app.session_pause", "metadata": { "mock": true }, "created_at": "2026-05-01T08:00:00Z" }
```

## Hardening references

- `docs/security/HARDENING_CHECKLIST.md`  
- `lib/core/session/web_session_ttl.dart`

**Validator:** narrative + `staging_validation` suite; DB has limited visibility into device storage.
