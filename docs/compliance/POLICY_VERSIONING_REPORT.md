# Policy Versioning Report

## Two-layer model (current)

1. **Gate document (short body in DB):** `legal_documents_versions` + RPCs `get_active_legal_version`, `accept_terms_v1` — drives mandatory re-accept in `PostAuthShell`.
2. **Full policy archive:** `regc_legal_policy_documents` (`policy_type`, `language`, `version`, `content`, `active`, `effective_date`).

## Version alignment

- Seed version `2026-04-05-SA` aligns with active legal gate version in repo migrations (`legal_documents_versions`).
- When publishing a new legal gate version:
  1. Insert new rows into `legal_documents_versions` (existing process).
  2. Insert matching `regc_legal_policy_documents` rows (per language + policy_type) and deactivate old rows (`active = false`) respecting partial unique index.

## Client behavior

- `PlatformPoliciesScreen` loads bundled `docs/compliance/*.md` when packaged as assets; server can supersede by reading `regc_legal_policy_documents` in a future service layer.

## Acceptance tracking

- `regc_user_legal_acceptances` stores (`user_id`, `policy_id`, `consent_type`, `accepted_at`).
- Audit: `terms.accepted` in `regc_audit_logs` via RPC chain.

## Open items

- Automated CMS for operators to edit `regc_legal_policy_documents` without SQL.
- PDF publication pipeline from same version source (see `docs/compliance/print/`).
