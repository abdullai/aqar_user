# Security event flow

```mermaid
sequenceDiagram
  participant A as Authenticated client
  participant R as RPC append_security_event_v1
  participant S as regc_security_events

  A->>R: action + metadata
  R->>R: assert auth.uid() not null
  R->>S: INSERT user_id=auth.uid()
```

## Difference from audit

- **Security events:** security-relevant signals (can feed SIEM export).  
- **Audit logs:** broader compliance trail (`compliance_append_audit`).

## Evidence

- `docs/regulatory_evidence/SESSION_SECURITY_EVIDENCE.md`  
- `supabase/sql/staging_validation/validate_security_events.sql`
