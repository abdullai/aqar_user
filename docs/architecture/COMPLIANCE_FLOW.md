# Compliance flow (legal + consent)

```mermaid
flowchart TD
  A[App launch / gate] --> B{Active legal version?}
  B -->|No match| C[Show terms + cookies acceptance]
  C --> D[RPC record_legal_acceptances_after_terms_v1]
  D --> E[RPC upsert_consent_preferences_v1 optional]
  E --> F[RPC compliance_append_audit]
  B -->|OK| G[Main app shell]
```

## Tables

- `regc_legal_policy_documents` — versioned text.  
- `regc_user_legal_acceptances` — per-user pointer to `policy_id`.  
- `regc_consent_preferences` — analytics / marketing flags.

## Evidence

- `docs/regulatory_evidence/CONSENT_TRACKING_EVIDENCE.md`  
- `docs/regulatory_evidence/POLICY_VERSIONING_EVIDENCE.md`
