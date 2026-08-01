# Regulatory Evidence Pack

**Purpose:** Submission-ready **narrative + technical excerpts** linking migrations, SQL validators, and mock samples.  
**Not a substitute for:** staging query outputs, pentest reports, or legal sign-off.

| # | File | Focus |
|---|------|--------|
| 1 | `DATABASE_RLS_EVIDENCE.md` | RLS design, policy excerpts, inventory SQL |
| 2 | `API_SECURITY_EVIDENCE.md` | PostgREST / RPC surface, role separation |
| 3 | `JWT_VALIDATION_EVIDENCE.md` | JWT lifecycle, SDK validation, abuse tests |
| 4 | `CONSENT_TRACKING_EVIDENCE.md` | Preferences + legal acceptance + audit |
| 5 | `AUDIT_LOGGING_EVIDENCE.md` | `compliance_append_audit`, append-only model |
| 6 | `COMPLAINT_ESCALATION_EVIDENCE.md` | Tickets, RLS isolation, escalation chain |
| 7 | `STORAGE_SECURITY_EVIDENCE.md` | Buckets, signed URLs, MIME placeholders |
| 8 | `SESSION_SECURITY_EVIDENCE.md` | TTL, refresh, web guest activity |
| 9 | `GOVERNMENT_DEMO_EVIDENCE.md` | Demo flag, isolated DB, no prod impact |
| 10 | `POLICY_VERSIONING_EVIDENCE.md` | `regc_legal_policy_documents`, active row rule |

**Related:** `supabase/sql/staging_validation/`, `docs/evidence_exports/`, `tools/security_inventory/scan.py`.

## Evidence chain

1. Run SQL validators on staging → export CSV.  
2. Run `python tools/security_inventory/scan.py` → attach `out/inventory_report.md` (local).  
3. Keep mock samples under `docs/evidence_exports/` for shape-only demos.