# Database security

## RLS

- All `regc_*` tables run with RLS enabled (see migration `20260515183000_compliance_legal_audit_rls.sql`).  
- Inventory: `supabase/sql/audit_rls_regc_privileges_and_policies.sql`.

## Roles

- Application clients: **anon** + **authenticated** only.  
- **service_role**: CI, migrations, admin backend.

## RPC hardening

- `SECURITY DEFINER` functions must `SET search_path = public` (already applied in compliance RPCs).  
- Review any new definer functions for injection via dynamic SQL.

## Auditing

- `regc_audit_logs` append-only from client perspective (insert via RPC).  
- DBAs still capable of manual delete — operational controls required.
