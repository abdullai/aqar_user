# Compliance Validation Report

## Policy & consent surfaces (in-app)

| Requirement | Implementation | Verified |
|-------------|----------------|----------|
| Terms gate vs server version | `get_active_legal_version` + `PostAuthShell` | Manual |
| Cookie essential ack | `LegalTermsAcceptanceScreen` + prefs key | Manual |
| Legal acceptance DB | `accept_terms_v1` + `record_legal_acceptances_after_terms_v1` → `regc_user_legal_acceptances` | After migration |
| Cookie / analytics prefs | `ConsentPreferencesScreen` → `regc_consent_preferences` + RPC | Manual |
| Complaints + audit | `SupportPage` → `regc_user_complaints` + `compliance_append_audit` | Manual |
| No new home tabs | Compliance under Settings only | Static review |

## REGA / Nafath / MC (readiness)

- Public URLs configurable (`PlatformComplianceConfig`).
- **API integration:** not implemented in client — see `docs/government_submission/`.

## PDPL-style posture

- Purposes documented in `docs/compliance/PRIVACY_POLICY_*.md` (draft).
- Data subject channel: support + complaints mailboxes + in-app complaint.

## Gaps (require human)

- Lawyer-reviewed Arabic/English policy PDFs.
- Formal DPIA / RoPA documentation (operator-held).

## SQL evidence

Run: `supabase/sql/audit_rls_regc_privileges_and_policies.sql` and attach output to this file’s appendix when filing for license.
