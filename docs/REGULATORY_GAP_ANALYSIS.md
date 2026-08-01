# Regulatory gap analysis

This document lists **what the repository demonstrates** versus **what still requires external action**.

## Achieved in engineering / documentation

- Compliance data model (`regc_*`) with RLS and definer RPCs.  
- Evidence pack (`docs/regulatory_evidence/`).  
- Staging SQL validators (`supabase/sql/staging_validation/`).  
- Mock CSV shapes (`docs/evidence_exports/`).  
- Static security inventory script (`tools/security_inventory/scan.py`).  
- Architecture narratives (`docs/architecture/`).  
- Executive summary (`docs/EXECUTIVE_COMPLIANCE_SUMMARY.md`).

## Requires government linkage (ربط حكومي)

- REGA production APIs and callback endpoints.  
- Nafath / national IdP OIDC client credentials and test realm.

## Requires formal contracts (عقود رسمية)

- Data processing agreement with cloud host.  
- Sub-processor list (email, maps, analytics if used).

## Requires human certifications (شهادات بشرية)

- App store / enterprise signing authority approvals.  
- Optional ISO 27001 / SOC2 **reports from vendors** (not source code).

## Requires legal approval (اعتماد قانوني)

- Published AR/EN privacy, terms, cookies, complaint policies.  
- Escalation SLAs and jurisdiction clauses.

## Requires external penetration testing (اختبارات اختراق)

- Authenticated + unauthenticated testing against **staging clone**.  
- Storage signed-URL bypass attempts; IDOR on RPC parameters.

## Requires live SSL / DNS (شهادات فعلية)

- Production hostname TLS certificates (typically automated via provider).  
- DNS ownership proof for licensing.

## Requires real WAF / CDN (حقيقي)

- Edge rules for rate limit, bot management, geo block if policy requires.

## Requires external monitoring (مراقبة خارجية)

- Uptime SLO dashboards; log shipping to retained bucket.

## Requires SIEM / SOC (عند النضج التشغيلي)

- Correlation rules for auth anomalies, mass export, privilege changes.

---

**Conclusion:** The repo is **submission-oriented**; **operational certification** closes gaps above.
