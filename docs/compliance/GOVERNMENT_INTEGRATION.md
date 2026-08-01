# Government Integration

## Nafath (National Access)

Planned / manual items for production:

- OAuth/OIDC or official integration pattern approved for your environment.
- JWT validation and session mapping to Supabase `auth.users`.
- Step-up authentication for sensitive actions (contracts, payouts, org admin).

**Demo:** use public portal URL from env `COMPLIANCE_NAFATH_PUBLIC_URL` (see `PlatformComplianceConfig`).

## REGA

Planned items:

- API integration for advertiser verification, listing validation, complaint sync, license checks.
- Operational runbooks for data shared with REGA systems.

**Demo:** use `COMPLIANCE_REGA_PUBLIC_URL` for deep links until APIs are live.

## Saudi Business Center (MC)

- Use `COMPLIANCE_MC_BUSINESS_URL` for public references; store certificates off-app in controlled storage.

## Environment keys (examples)

Set in `.env` / CI secrets (not committed):

- `COMPLIANCE_REGA_PUBLIC_URL`
- `COMPLIANCE_NAFATH_PUBLIC_URL`
- `COMPLIANCE_MC_BUSINESS_URL`
- `COMPLIANCE_COMPLAINTS_EMAIL`, `COMPLIANCE_SUPPORT_EMAIL`
- Optional `COMPLIANCE_COMPLAINTS_WEB_URL`

## Demo government profile

For UAT/demo builds, keep **synthetic** identities and disable production government keys. Document demo endpoints separately in operator runbooks.
