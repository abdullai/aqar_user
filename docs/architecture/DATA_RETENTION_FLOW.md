# Data retention flow (conceptual)

```mermaid
flowchart TD
  L[Operational need ends] --> C[Classification: legal hold?]
  C -->|Yes| H[Retain per legal hold register]
  C -->|No| P[Purge / anonymize pipeline]
  P --> A[Audit log retention event]
```

## Repository alignment

- Narrative: `docs/compliance/DATA_RETENTION.md`.  
- Technical deletion: implement via controlled RPC or service_role jobs (**not** exposed to anon).

## Evidence

- `docs/REGULATORY_GAP_ANALYSIS.md` (non-software steps)
