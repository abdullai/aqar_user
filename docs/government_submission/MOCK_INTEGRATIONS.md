# Mock integrations & demo environment

## Flag

- `GOVERNMENT_DEMO_MODE` or `COMPLIANCE_DEMO_GOV_MODE` in `.env` / build defines — read via `PlatformComplianceConfig.governmentDemoMode()` (`1` / `true` / `yes` / `on`).  
- **Default:** off. Production builds must leave it **off**.

## What “mock” means here

- **No** fake Nafath server in production.  
- Demo stack = separate Supabase project + optional seed SQL (commented) for sample `regc_*` rows.

## Suggested demo seed (manual)

In **demo DB only**, optionally insert:

- 1–2 rows in `regc_user_complaints` for demo user IDs.  
- Sample `regc_audit_logs` via RPC as demo script.

Keep scripts in `supabase/sql/` with filename prefix `demo_` and **do not** enable in production migration chain.

## REGA / Nafath mocks

- UI can show static “Demo mode” banner when `governmentDemoMode()` is true (implement only when product approves — currently **no banner** to avoid UX change).

## Testing matrix

| Scenario | Environment |
|----------|-------------|
| JWT from demo project | Demo |
| REGA stub responses | Local Edge mock or static JSON fixtures in tests |
