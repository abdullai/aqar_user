# Compliance Program Overview

This folder contains operator-facing policies and readiness notes for a Saudi real-estate electronic platform (marketing/brokerage workflows, REGA alignment path, PDPL-oriented privacy posture).

## Contents

| Document | Purpose |
|----------|---------|
| `PRIVACY_POLICY_*.md` | Privacy disclosures (AR/EN drafts). |
| `TERMS_OF_USE_*.md` | Terms of use (AR/EN drafts). |
| `COOKIES_POLICY_*.md` | Cookie categories and consent (AR/EN). |
| `INTELLECTUAL_PROPERTY_*.md` | IP baseline (AR/EN). |
| `SECURITY.md` | Technical and organizational security measures. |
| `INCIDENT_RESPONSE.md` | Security incident workflow. |
| `DATA_RETENTION.md` | Retention and deletion principles. |
| `REGULATORY_REQUIREMENTS.md` | REGA / PDPL / commercial registration alignment checklist. |
| `GOVERNMENT_INTEGRATION.md` | Nafath, REGA APIs, and demo environment notes. |
| `COMPLAINT_POLICY.md` | Complaints intake, SLAs, escalation. |
| `LICENSE_READINESS_REPORT.md` | Consolidated readiness snapshot. |

## Application wiring (repository)

- Policies load in-app from bundled markdown under `docs/compliance/` when present (see `PlatformPoliciesScreen`).
- Server-side versioning and acceptances: migration `supabase/migrations/20260515183000_compliance_legal_audit_rls.sql` (`regc_legal_policy_documents`, `regc_user_legal_acceptances`, audit RPCs).
- Compliance UI entry: **Settings → Compliance & policies** (no new home tabs).

**Disclaimer:** Draft texts are not a substitute for counsel-reviewed policies or regulator-approved disclosures.
