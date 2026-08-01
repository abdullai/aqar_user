# Database Optimization Report

## Inventory scripts

- `supabase/PERFORMANCE_AUDIT.md` (if present in repo)  
- `supabase/sql/diagnostics_*` templates  
- New: `supabase/sql/audit_rls_regc_privileges_and_policies.sql` (policy overhead awareness)

## regc_* indexes (from migration)

- `regc_audit_logs (user_id, created_at DESC)`  
- `regc_audit_logs (event_type)`  
- `regc_user_complaints (user_id, created_at DESC)`  
- `regc_complaint_escalations (complaint_id)`  
- `regc_security_events (user_id, created_at DESC)`  
- `regc_user_legal_acceptances (user_id, policy_id)` UNIQUE

## Suggested follow-ups (run with `EXPLAIN ANALYZE` on staging)

1. If `regc_audit_logs` grows large, consider **monthly partition** or archive job.  
2. Add BRIN on `created_at` if time-range queries dominate.  
3. Review existing hot RPCs from product (listing feeds, audience stats) against `supabase/PERFORMANCE_AUDIT.md`.

## Query anti-patterns

- Avoid `select *` from wide tables in list views — explicit columns reduce IO.
