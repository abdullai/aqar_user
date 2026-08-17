# CONSENT_TRACKING_EVIDENCE

## Architectural summary

1. **Legal policy versioning** — `regc_legal_policy_documents` (active row per type+language).  
2. **Acceptance records** — `regc_user_legal_acceptances` after terms flow.  
3. **Cookie / analytics preferences** — `regc_consent_preferences` + RPC `upsert_consent_preferences_v1`.  
4. **Audit** — `compliance_append_audit` records `consent.preferences_updated` and `terms.accepted`.

## RPC excerpt — consent upsert + audit

```sql
PERFORM public.compliance_append_audit(
  'consent.preferences_updated',
  jsonb_build_object(
    'analytics_cookies', p_analytics,
    'marketing_cookies', p_marketing,
    'essential_ack', coalesce(p_essential_ack, true)
  )
);
```

## Example consent row (mock CSV)

See `docs/evidence_exports/consent_tracking_sample.csv`.

## Policy versioning acceptance (mock)

See `docs/evidence_exports/policy_acceptance_sample.csv`.

## Withdrawal / change

Users update preferences via the same upsert path; operators document **retention** separately (`docs/compliance/DATA_RETENTION.md`).

**Validator:** `supabase/sql/staging_validation/validate_consent_versioning.sql`
