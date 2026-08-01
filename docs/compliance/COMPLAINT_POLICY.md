# Complaint Policy

## Channels

1. **In-app:** Settings → Support & complaints → *Log in-app complaint* (persists to `regc_user_complaints` + `regc_audit_logs` when migration applied).
2. **Email:** dedicated complaints mailbox (`COMPLIANCE_COMPLAINTS_EMAIL`).
3. **Web form (optional):** `COMPLIANCE_COMPLAINTS_WEB_URL` when configured.

## Workflow

1. **Intake:** acknowledge receipt (auto-reply template recommended).
2. **Triage:** categorize (technical, billing, regulatory, abuse).
3. **SLA (example):** first response within **2 business days** for non-critical cases (set final SLA with counsel).
4. **Escalation:** record in `regc_complaint_escalations` when handing to legal, REGA liaison, or executive committee.
5. **Closure:** document outcome; retain per `DATA_RETENTION.md`.

## Abuse & safety

Escalate immediately for threats, fraud rings, or child safety issues per internal emergency protocol.

## Regulatory sync

Where REGA or other authorities require formal submission, maintain copies of what was filed and when (outside-app document control acceptable).
