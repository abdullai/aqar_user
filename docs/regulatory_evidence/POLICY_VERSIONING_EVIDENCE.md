# POLICY_VERSIONING_EVIDENCE

## Architectural summary

Legal text is versioned in `regc_legal_policy_documents` with columns `(policy_type, language, version)` and a **partial unique index** enforcing **one active row** per `(policy_type, language)`.

## Index excerpt

```sql
CREATE UNIQUE INDEX IF NOT EXISTS legal_policy_documents_one_active_per_lang_type
  ON public.regc_legal_policy_documents (policy_type, language)
  WHERE active;
```

## Acceptance linkage

`regc_user_legal_acceptances` references `policy_id` → immutable version pointer for audits.

## Example (mock)

See `docs/evidence_exports/policy_acceptance_sample.csv` and seeded reference rows in migration (replace with lawyer-approved text before go-live).

**Validator:** `supabase/sql/staging_validation/validate_consent_versioning.sql`
