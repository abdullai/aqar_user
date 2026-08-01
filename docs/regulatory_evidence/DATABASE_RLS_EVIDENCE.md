# DATABASE_RLS_EVIDENCE

## Architectural summary

Row Level Security (RLS) on the compliance stack ensures **PostgREST** cannot return or mutate rows outside the caller’s authorization, even if the client is compromised. The `regc_*` namespace isolates compliance data from legacy table names (e.g. historical `complaints` without `user_id`).

**Primary migration:** `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql`  
**Inventory (run on staging as `postgres`):** `supabase/sql/audit_rls_regc_privileges_and_policies.sql`

## RLS enablement (excerpt)

```sql
ALTER TABLE public.regc_legal_policy_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_user_legal_acceptances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_user_complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_complaint_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.regc_consent_preferences ENABLE ROW LEVEL SECURITY;
```

## Example policy — own-row complaints

```sql
CREATE POLICY complaints_select_own ON public.regc_user_complaints
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY complaints_insert_own ON public.regc_user_complaints
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
```

## Example RLS behavior (expected)

| Actor | `regc_user_complaints` | `regc_audit_logs` |
|-------|------------------------|-------------------|
| anon | No rows | No rows |
| User A (JWT) | Only rows where `user_id = A` | Only own audit rows (SELECT); INSERT via RPC only |
| service_role | Break-glass / migrations | Full (ops only) |

## Grants excerpt (sensitive writes denied to anon)

```sql
GRANT SELECT ON public.regc_legal_policy_documents TO anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.regc_audit_logs FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compliance_append_audit(text, jsonb) TO authenticated;
```

## Staging validation artifact

Run: `supabase/sql/staging_validation/validate_rls.sql`  
Attach result grid as **screenshot or CSV** for the evidence binder.
