# Data Retention

## Principles

- Retain personal and transactional data **no longer than necessary** for service delivery, dispute resolution, and statutory obligations.
- Separate **operational retention** from **legal hold** windows when investigations apply.

## Categories (indicative — set final periods with counsel)

| Category | Indicative retention | Notes |
|----------|---------------------|--------|
| Account & profile | Life of account + statutory window | Subject to deletion requests where lawful. |
| Listings & media | Until deletion + backup cycle | Hard delete policies depend on Supabase storage rules. |
| Audit / security logs | 12–24 months (example) | Extend if regulator or contract requires. |
| Complaints | 24–36 months (example) | Escalations in `regc_complaint_escalations`. |
| Marketing consents | While account active + proof window | Evidence of acceptance versions. |

## Deletion

- User-initiated account deletion flows must cascade per database design (FK `ON DELETE` policies).
- Backups: ensure eventual consistency with deletion (document backup encryption and purge SLO).

## Legal records

Commercial registration, REGA correspondence, and licensing artifacts are **not** stored in this app folder; maintain in operator document control.
