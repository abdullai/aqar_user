# Security architecture (summary)

```mermaid
flowchart TB
  subgraph Client["Flutter client"]
    UI[UI + state]
    SDK[supabase_flutter]
  end
  subgraph Edge["Optional Edge Functions"]
    RL[Rate limit / webhooks]
  end
  subgraph Supabase["Supabase"]
    API[PostgREST + Auth + Realtime]
    PG[(Postgres + RLS)]
    ST[(Storage)]
  end
  UI --> SDK --> API
  API --> PG
  API --> ST
  SDK --> Edge
  Edge --> API
```

## Controls

- **Auth:** Supabase Auth JWT.  
- **AuthZ:** RLS on `public` tables; `SECURITY DEFINER` RPCs for controlled writes (`compliance_append_audit`, …).  
- **Compliance data:** `regc_*` namespace to avoid legacy table collisions.  
- **Web session hardening:** idle logout + tab binding (see codebase `web_session_ttl`, `WebAuthTabGuard`).

## Out of scope in client

- WAF, bot management, DDoS — **edge network** responsibility.
