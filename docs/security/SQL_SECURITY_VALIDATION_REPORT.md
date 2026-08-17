# SQL security validation report

**Purpose:** Document how database security is **verified** in this repository and what remains **manual / staging-only**.

## Automated inventory (run as `postgres` in SQL Editor)

Execute:

`supabase/sql/audit_rls_regc_privileges_and_policies.sql`

**Outputs:**

1. **Section A** — All RLS policies on `regc_%` tables (name, command, roles, `USING`, `WITH CHECK`).  
2. **Section B** — `relrowsecurity` / `relforcerowsecurity` flags.  
3. **Section C** — Table grants for `anon`, `authenticated`, `service_role`, `postgres`.

Save query results as CSV/PDF attachments for licensing or internal audit.

## Behavioral tests (not runnable as anon inside SQL Editor alone)

JWT-bound behavior (forged token, wrong `sub`, expired `exp`) must be exercised via:

- Supabase REST with `apikey` + `Authorization: Bearer …`, or  
- Flutter integration tests against a **staging** project, or  
- `supabase/sql/audit_rls_behavioral_test_matrix.md` checklist.

## Expected invariants

| Invariant | Verification |
|-----------|--------------|
| anon cannot UPDATE/DELETE sensitive `regc_*` | Section C grants + REST negative tests |
| No user can set arbitrary `user_id` on audit rows | RPC body vs `auth.uid()` inside definer |
| No privilege escalation via public RPC | Review `SECURITY DEFINER` + `search_path` |

## Gaps (explicit)

- **Forged JWT:** Must fail at API gateway (invalid signature); document result in staging.  
- **service_role in client:** Forbidden; scan CI/build for key leakage (see `ENVIRONMENT_SECURITY_REPORT.md`).

## Sign-off (template)

| Role | Name | Date | Result |
|------|------|------|--------|
| DBA / Security | | | Pass / Fail |
