# Production certification checklist

Use this as a **gate** before declaring production-ready for regulated launch.  
Check each item; attach evidence (screenshot, CSV export, contract PDF) in your evidence binder.

## Security

- [ ] Staging: all `staging_validation/*.sql` runs → **PASS** (or documented waivers).  
- [ ] No `service_role` key in client builds (scan + manual review).  
- [ ] `tools/security_inventory/scan.py` run; **anon GRANT** lines reviewed.  
- [ ] WAF / bot rules enabled on API edge.  
- [ ] Supabase Auth: refresh rotation + reuse detection configured.

## Compliance & privacy

- [ ] Legal reviewed `docs/compliance/*_AR.md` / `*_EN.md`.  
- [ ] Cookie / consent UX matches `regc_consent_preferences` model.  
- [ ] DSR (access/erasure) process documented and staffed.

## Database & RLS

- [ ] `audit_rls_regc_privileges_and_policies.sql` output archived.  
- [ ] No accidental `anon` **INSERT/UPDATE/DELETE** on sensitive compliance tables.

## Nafath / REGA / MC

- [ ] Nafath integration path approved (`docs/government_submission/NAFATH_INTEGRATION.md`).  
- [ ] REGA integration path approved (`REGA_READINESS.md`).  
- [ ] MC / business registration evidence on file.

## Complaints & tickets

- [ ] `validate_ticket_isolation.sql` → **PASS**.  
- [ ] SLA table for internal escalation (outside repo or attached runbook).

## Backups & DR

- [ ] Backup schedule enabled + **restore drill** logged.  
- [ ] RPO/RTO targets documented.

## Incidents

- [ ] On-call roster + tabletop exercise date recorded.

## Secrets management

- [ ] CI secrets in vault; no plaintext in git.  
- [ ] Key rotation calendar (anon, JWT signing, third-party APIs).

## Sessions & JWT

- [ ] Session idle policy matches product.  
- [ ] JWT `exp` aligned with risk tolerance.

## File upload & storage

- [ ] Bucket policies reviewed in dashboard.  
- [ ] MIME/size limits enforced client + server where applicable.

## APIs & Realtime

- [ ] `validate_jwt_claims.sql` → **PASS**.  
- [ ] `validate_realtime_authorization.sql` reviewed; only intended tables published.

## Logging & monitoring

- [ ] Centralized logs without raw PII.  
- [ ] Alerts for error rate, auth failures, DB CPU.

---

**Sign-off**

| Role | Name | Signature | Date |
|------|------|-------------|------|
| Security | | | |
| Legal | | | |
| Product | | | |
