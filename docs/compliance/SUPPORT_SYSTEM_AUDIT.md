# Support System Audit

## Channels implemented

| Channel | Location | Persistence |
|---------|----------|-------------|
| Technical support email | `SupportPage` + `PlatformComplianceConfig.supportEmail()` | None (mailto) |
| Complaints email | same + `complaintsEmail()` | None (mailto) |
| In-app complaint | `showInAppComplaintDialog` | `regc_user_complaints` + audit `complaint.submitted` |

## Tickets / SLA / internal notes

- **Full ticketing system** (SLA timers, internal notes, attachments) is **not** implemented as a first-class module in this repo.
- Recommended path: integrate external helpdesk (Zendesk/Jira SM) **or** add tables `support_tickets`, `ticket_messages` in a future migration with strict RLS.

## Access control

- Complaints: RLS owner-only on `regc_user_complaints`.
- Escalations: `regc_complaint_escalations` insert/select tied to owning complaint.

## Audit

- Each in-app complaint submission triggers `compliance_append_audit`.

## Recommendations

1. Add staff-only dashboard (separate admin deployment) reading `regc_user_complaints` via `service_role`.  
2. Define SLA table + status transitions when ticketing matures.
