# RLS audit report — compliance stack (`regc_*`)

## Scope

Tables introduced or governed by:

`supabase/migrations/20260515183000_compliance_legal_audit_rls.sql`

## Design goals

1. **Anonymous** users may read **active** legal policy text only (`regc_legal_policy_documents`) where policies allow — no access to other users’ complaints, consent, or audit history.  
2. **Authenticated** users operate on **own rows** (`user_id = auth.uid()`), except centralized append-only audit via RPC.  
3. **No RLS bypass** from the mobile/web app: client uses **anon** + **authenticated** keys only.  
4. **service_role** reserved for migrations, break-glass, and server-side jobs — never embedded in shipped apps.

## Policy inventory

Run and attach results:

`supabase/sql/audit_rls_regc_privileges_and_policies.sql` (Section A + B).

## RPC bypass review

Functions marked `SECURITY DEFINER` must:

- `SET search_path = public` (applied in this migration).  
- Bind actor identity to `auth.uid()` (or equivalent) — verify per-function in migration source.

## Realtime / Storage

RLS applies to Postgres; **Storage** and **Realtime** require separate policy review — see `docs/government_submission/STORAGE_SECURITY.md` and project bucket dashboard.

## Residual risks

| Risk | Mitigation |
|------|------------|
| DBA direct table edit | Role separation, SIEM, optional WAL archiving |
| New tables without RLS | Migration checklist + CI policy lint (future) |

## Conclusion (template)

- [ ] Inventory SQL executed on staging __________  
- [ ] Spot-check: anon SELECT legal docs only  
- [ ] Spot-check: user A cannot read user B complaints  

**Auditor sign-off:** __________________ **Date:** __________
