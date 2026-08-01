# Consent Management Report

## Flows

| Flow | Behavior |
|------|----------|
| First login | Terms screen + mandatory essential cookie ack (`prefRegulatoryCookieAckKey`) + server `accept_terms_v1` + `record_legal_acceptances_after_terms_v1`. |
| Analytics / marketing toggles | `ConsentPreferencesScreen` → RPC `upsert_consent_preferences_v1` → `regc_consent_preferences` + audit `consent.preferences_updated`. |
| Withdraw optional | Same screen: turn off analytics & marketing, save. |
| Necessary-only | `essential_ack` remains true; cannot disable session storage without breaking login. |

## GDPR-style mapping (informative)

| GDPR-style concept | Saudi PDPL context | Implementation |
|--------------------|--------------------|----------------|
| Purpose limitation | Contract + legal obligation + consent where needed | Policy copy + gate |
| Withdraw consent | Where processing is consent-based | Toggle save + audit |
| Proof of consent | Accountability | `regc_user_legal_acceptances` + audit logs |

## Persistence

- Server: `regc_consent_preferences` (per user PK `user_id`).
- Client: cookie ack pref for UX gating only — **server is source of truth** for optional cookies.

## Gaps

- Re-prompt on policy version bump: enforced for **terms gate** via `legal_documents_versions`; optional cookies may need explicit version stamp in RPC later.

## Tests (manual)

1. Accept terms → verify rows in `regc_user_legal_acceptances` for `terms_of_use` + `cookies_policy`.  
2. Toggle analytics off/on → verify `regc_consent_preferences` + audit event count increases.
