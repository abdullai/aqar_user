# Incident Response

## 1. Detection

- Automated: Supabase logs, hosting alerts, failed auth spikes, anomaly dashboards.
- Manual: user reports via Support / in-app complaint, operator monitoring.

## 2. Triage & classification

Assign severity (low / medium / high / critical) and incident type (data leak, account takeover, abuse, outage).

## 3. Containment

- Revoke sessions / rotate secrets for affected scopes.
- Disable compromised accounts or API keys.
- Preserve forensic logs (export before retention expiry if required).

## 4. Investigation

- Correlate `regc_audit_logs`, `regc_security_events`, `user_login_audit`, application logs.
- Document timeline and scope of affected users/data.

## 5. Recovery

- Patch vulnerability or misconfiguration.
- Restore services from backups if needed.
- Verify integrity post-remediation.

## 6. Notification

- Internal stakeholders and legal counsel.
- Regulatory or user notifications **only** per counsel guidance and applicable law.

## 7. Post-incident

- Update runbooks, training, and monitoring rules.
- Optional row in `regc_incidents` for internal tracking (RLS: reporter-owned insert).
