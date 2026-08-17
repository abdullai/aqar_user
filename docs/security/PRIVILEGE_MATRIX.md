# Privilege matrix — Supabase roles vs compliance surface

**Legend:** ✓ allowed by design · ✗ denied · RPC = via `SECURITY DEFINER` / `GRANT EXECUTE` · N/A = not applicable.

## Core compliance tables (`public.regc_*`)

| Resource | anon | authenticated | admin (custom JWT claim / break-glass) | service_role |
|----------|------|-----------------|------------------------------------------|----------------|
| `regc_legal_policy_documents` | SELECT active rows only | SELECT | As policy (usually break-glass SQL) | Full (bypass RLS) |
| `regc_user_legal_acceptances` | ✗ | SELECT/INSERT own | Ops tooling | Full |
| `regc_audit_logs` | ✗ | SELECT own rows; INSERT **only** via `compliance_append_audit` | Read export | Full |
| `regc_incidents` | ✗ | Per RLS (if any) | Ops | Full |
| `regc_user_complaints` | ✗ | INSERT/SELECT own | Ops | Full |
| `regc_complaint_escalations` | ✗ | Per complaint ownership chain | Ops | Full |
| `regc_security_events` | ✗ | Own rows if policy allows | Ops | Full |
| `regc_consent_preferences` | ✗ | UPSERT/SELECT own | Ops | Full |

## DDL / destructive operations

| Operation | anon | authenticated | service_role |
|-----------|------|-----------------|----------------|
| UPDATE on `regc_audit_logs` | ✗ | ✗ (design: append-only) | Possible (DBA) |
| DELETE / TRUNCATE | ✗ | ✗ | Possible (DBA — operational control) |

**Note:** PostgREST does not expose `TRUNCATE` to API roles by default; still verify grants in `information_schema.role_table_grants` using the inventory SQL below.

## RPCs (representative)

| Function | anon | authenticated |
|----------|------|-----------------|
| `compliance_append_audit` | ✗ | ✓ (caller `user_id` bound inside definer) |
| Other compliance RPCs | ✗ | Per `GRANT EXECUTE` in migration |

## References

- Inventory: `supabase/sql/audit_rls_regc_privileges_and_policies.sql`  
- Migration: `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql`  
- Behavioral REST/JWT matrix: `supabase/sql/audit_rls_behavioral_test_matrix.md`
