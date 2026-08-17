# Final anonymous (`anon`) exposure report

**Method:** Catalog review in migrations + static scan `tools/security_inventory/scan.py` (SQL `GRANT` lines mentioning `anon`).  
**Live verification:** Re-run on staging after every migration batch; merge with `information_schema.role_table_grants`.

## Summary

| Category | Count (approx.) | Risk posture |
|----------|-----------------|---------------|
| `GRANT … TO anon` lines in repo SQL | **36** at last scan | **Review each** — many are intentional public discovery |
| Compliance `regc_*` anon write | **0** (by design) | **Low** |
| Compliance RPC execute for anon | **0** for `compliance_*` / `append_security_*` / `upsert_consent_*` / `record_legal_*` | **Low** |

> Regenerate counts: `python tools/security_inventory/scan.py` → see `out/inventory_summary.csv` (gitignored).

## Compliance tables (`regc_*`)

| Table / surface | anon privilege | RLS sufficient? | Business reason | Severity |
|-----------------|----------------|-----------------|-------------------|----------|
| `regc_legal_policy_documents` | `SELECT` | Yes — policy `active = true` | Anonymous users must read active legal text at gate | **Low** |
| `regc_audit_logs` | None (no INSERT) | N/A | Audit via authenticated RPC only | **Low** |
| `regc_user_complaints` | None | N/A | Authenticated only | **Low** |
| `regc_consent_preferences` | None | N/A | Authenticated only | **Low** |

## Representative public-catalog features (non-exhaustive)

These appear in migrations as **`EXECUTE` for `anon`** — typically for signup, org browse, or aggregate stats. **Each must stay backed by:**

- `SECURITY DEFINER` with narrow logic, **or**  
- RLS on underlying tables, **or**  
- Rate limits at edge.

Examples from scanner output (filenames only — verify in staging):

- `org_browse_public`, `org_public_profile` — public org discovery.  
- `get_app_audience_stats`, `ping_app_presence` — operational telemetry (abuse-sensitive → rate limit).  
- `signup_username_taken`, `signup_phone_taken` — registration helpers (brute-force sensitive → throttle).  
- `get_market_insights_snapshot` — public insights RPC.

## Recommendations

1. Attach **staging** `role_table_grants` export for `anon` to evidence binder.  
2. For each anon RPC: document **max rows returned**, **rate limit**, and **PII fields = none**.  
3. Re-scan after each release: `scan.py` + `validate_rls.sql`.

## Sign-off template

| Reviewer | Date | Outcome |
|----------|------|---------|
| | | Pass / Remediate |
