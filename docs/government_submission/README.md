# Government submission package

This folder bundles **operator-facing** materials for REGA / MC / cybersecurity narratives.  
Detailed legal texts remain under `docs/compliance/`.

| Document | Purpose |
|----------|---------|
| `REGULATORY_REQUIREMENTS.md` | Submission checklist + link to full requirements |
| `REGA_READINESS.md` | REGA integration status |
| `NAFATH_INTEGRATION.md` | Nafath / OIDC plan |
| `SECURITY_ARCHITECTURE.md` | High-level security architecture |
| `DATA_FLOW.md` | Data movement & trust boundaries |
| `INCIDENT_RESPONSE.md` | Incident handling summary |
| `PRIVACY_COMPLIANCE.md` | PDPL-oriented summary |
| `LICENSE_READINESS_CHECKLIST.md` | Licensing gate checklist |
| `API_ARCHITECTURE.md` | Client–Supabase–Edge overview |
| `DATABASE_SECURITY.md` | Postgres + RLS summary |
| `STORAGE_SECURITY.md` | Buckets & signed URLs |
| `MOCK_INTEGRATIONS.md` | Demo mode & mock government flows |

**Mock / demo:** use isolated Supabase project + `GOVERNMENT_DEMO_MODE=1` only on demo builds — never production.
