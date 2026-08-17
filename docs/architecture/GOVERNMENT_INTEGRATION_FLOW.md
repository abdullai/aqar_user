# Government integration flow (target state)

```mermaid
flowchart LR
  subgraph Client
    C[Flutter App]
  end
  subgraph Platform
    E[Edge Functions / Gateway]
    D[(Postgres RLS)]
  end
  subgraph Gov
    N[Nafath / OIDC]
    R[REGA APIs]
  end

  C -->|HTTPS| E
  E --> N
  E --> R
  E --> D
```

## Current vs target

- **Today:** public URLs + documentation; demo flag for isolated stacks.  
- **Target:** signed webhooks, mTLS or IP allow lists per REGA program.

## Evidence

- `docs/government_submission/`  
- `docs/regulatory_evidence/GOVERNMENT_DEMO_EVIDENCE.md`
