# Audit logging flow

```mermaid
sequenceDiagram
  participant A as Authenticated client
  participant R as RPC compliance_append_audit
  participant T as regc_audit_logs

  A->>R: event_type + metadata JSON
  R->>R: assert auth.uid() not null
  R->>T: INSERT user_id=auth.uid()
  T-->>A: void / success
```

## Integrity

- Direct `INSERT` on `regc_audit_logs` is **not** granted to `authenticated`; only RPC path.

## Evidence

- `docs/regulatory_evidence/AUDIT_LOGGING_EVIDENCE.md`  
- `supabase/sql/staging_validation/validate_audit_logs.sql`
