# Evidence exports (mock)

All CSV files in this folder contain **synthetic identifiers** (`00000000-…`, `a1000000-…`) and **`mock=yes`**.  
**Do not** commit real user data or production exports to git.

## Files

| File | Use |
|------|-----|
| `audit_logs_sample.csv` | Audit trail shape |
| `consent_tracking_sample.csv` | Cookie / preference row shape |
| `complaint_escalation_sample.csv` | Complaint + escalation linkage |
| `security_events_sample.csv` | Security event row shape |
| `policy_acceptance_sample.csv` | Legal acceptance linkage |

Generate **real** staging exports by running SQL in `supabase/sql/staging_validation/` and `COPY (SELECT …) TO STDOUT CSV` (redact PII).
