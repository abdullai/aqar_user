# Executive compliance summary

**Audience:** Management, regulators, enterprise security reviewers.  
**Classification:** Internal — redact before external distribution.  
**Companion:** `docs/PRODUCTION_SECURITY_COMPLIANCE_MASTER_REPORT.md`, `docs/regulatory_evidence/`.

---

## 1. Project summary (ملخص المشروع)

A cross-platform **Flutter** real-estate application backed by **Supabase** (Postgres + Auth + Storage + Realtime). Compliance features use the dedicated **`regc_*`** schema prefix in `public` to avoid collisions with legacy tables.

## 2. Compliance summary (ملخص الامتثال)

- Versioned legal documents, user acceptances, consent preferences, complaints, escalations, audit logs, and security events.  
- Policies and operator narratives live under `docs/compliance/` and `docs/regulatory_evidence/`.

## 3. Security summary (ملخص الأمان)

- **RLS** on compliance tables; **RPC** for append-only audit; explicit **REVOKE** patterns for sensitive DML.  
- **Staging validators:** `supabase/sql/staging_validation/`.  
- **Static inventory:** `tools/security_inventory/scan.py`.

## 4. Government readiness (الجاهزية الحكومية)

- Submission pack: `docs/government_submission/`.  
- REGA / Nafath: **roadmap + public URLs** — production API integration requires official onboarding.

## 5. Operational readiness (الجاهزية التشغيلية)

- Run staging validation suite; attach CSV exports to evidence binder.  
- Configure backups, monitoring, and WAF at hosting layer.

## 6. Nafath status (النفاذ الوطني)

- **Planned / documented** — `docs/government_submission/NAFATH_INTEGRATION.md`.  
- **Live OIDC:** pending national IdP registration and legal review.

## 7. REGA status (الهيئة العامة للعقار)

- **Planned / documented** — `docs/government_submission/REGA_READINESS.md`.  
- **Live APIs:** pending REGA credentials and contractual scope.

## 8. MC / Saudi business center (المركز السعودي للأعمال)

- Public reference URL configurable via compliance env — see `PlatformComplianceConfig.mcBusinessCenterUrl()`.

## 9. Data protection (حماية البيانات)

- TLS transport; RLS; audit RPCs; retention narrative in `docs/compliance/DATA_RETENTION.md`.

## 10. Incident management (إدارة الحوادث)

- `docs/government_submission/INCIDENT_RESPONSE.md` + `docs/compliance/INCIDENT_RESPONSE.md`.

## 11. Audit logging (سجلات التدقيق)

- `regc_audit_logs` + `compliance_append_audit` — evidence: `docs/regulatory_evidence/AUDIT_LOGGING_EVIDENCE.md`.

## 12. Complaints & escalation (الشكاوى والتصعيد)

- `regc_user_complaints` + `regc_complaint_escalations` — evidence: `COMPLAINT_ESCALATION_EVIDENCE.md`, `validate_ticket_isolation.sql`.

## 13. Consent management (إدارة الموافقات)

- Preferences + legal acceptance — `CONSENT_TRACKING_EVIDENCE.md`, `validate_consent_versioning.sql`.

## 14. Current risk level (مستوى المخاطر)

**Medium–High residual** until: external pentest, production WAF/SIEM, and legal sign-off on published policies.

## 15. Non-software requirements (متطلبات خارج البرمجة)

- Corporate licenses, domain/DNS/SSL operations, DPAs, regulator keys, SOC staffing model.

---

**Prepared:** engineering documentation set — **not** a government approval.
