# Staging validation suite

**Location:** `supabase/sql/staging_validation/`  
**Safety:** Scripts are **read-only** `SELECT` checks against the catalog and (where noted) public compliance tables. They do **not** modify production data. Run on **staging** or a **clone** first.

## How to run

1. Open Supabase SQL Editor (staging project).  
2. Paste the contents of one file → Run.  
3. Export the result grid as **CSV** into `docs/evidence_exports/` (dated subfolder recommended).

## Files

| File | Intent |
|------|--------|
| `validate_rls.sql` | `regc_*` RLS enabled + policy counts |
| `validate_audit_logs.sql` | Anon DML denied; RPC not granted to anon |
| `validate_compliance_tables.sql` | Required tables exist |
| `validate_security_events.sql` | Table + RPC grants aligned |
| `validate_storage_policies.sql` | `storage.*` policy inventory |
| `validate_ticket_isolation.sql` | Complaint / escalation policies |
| `validate_consent_versioning.sql` | Unique partial index + active row sanity |
| `validate_jwt_claims.sql` | Compliance RPC catalog grants |
| `validate_realtime_authorization.sql` | Realtime publication inventory |
| `validate_government_demo_mode.sql` | No anon execute on compliance RPCs |

## Pass / Fail

- **`PASS` / `FAIL` / `WARN`** appear in the `status` column.  
- **`WARN`** means “acceptable but needs human follow-up” (e.g. empty seed).

## Troubleshooting validator FAILs

### `validate_jwt_claims.sql` — `no_anon_execute` = **FAIL** (`anon_execute_grants=1`)

Supabase / cluster defaults may grant **`EXECUTE` on `public` functions to `anon` or `PUBLIC`** even when your migration only granted `authenticated`. The RPCs still reject unauthenticated callers via `auth.uid()` checks, but the **catalog** shows a wider surface.

**Fix:** apply migration `supabase/migrations/20260516100000_compliance_revoke_anon_public_surface.sql`, then re-run the validator.

### `validate_audit_logs.sql` / `validate_security_events.sql` — anon shows `REFERENCES` / `TRUNCATE` / etc.

Same class of issue: **inherited table grants** on `regc_*`. The migration above `REVOKE ALL … FROM anon` on sensitive tables (and re-`GRANT SELECT` on legal docs only).

## Full bundle (optional)

Run files **in order** and zip CSV exports for regulator evidence.
