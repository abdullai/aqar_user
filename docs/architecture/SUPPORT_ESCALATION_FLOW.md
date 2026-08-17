# Support & complaint escalation flow

```mermaid
flowchart TD
  U[User opens Support] --> T[Create regc_user_complaints row]
  T --> RLS{RLS: user_id = auth.uid}
  RLS -->|OK| E[Optional regc_complaint_escalations]
  E --> Ops[Operator queue outside DB or desk UI]
```

## Isolation

- User **A** cannot `SELECT` complaints for user **B** (policy enforced).

## Evidence

- `docs/regulatory_evidence/COMPLAINT_ESCALATION_EVIDENCE.md`  
- `supabase/sql/staging_validation/validate_ticket_isolation.sql`
