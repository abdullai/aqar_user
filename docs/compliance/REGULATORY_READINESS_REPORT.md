# Regulatory Readiness Report (Saudi real-estate platform)

## Entity & licensing

| Item | Readiness | Evidence / action |
|------|-----------|-------------------|
| Commercial registration incl. brokerage / 682010 | Operator | CR extract + activities list |
| MC (Saudi Business Center) | Operator | Certificate scans in secure vault |
| REGA advertiser/listing flows | Partial | In-app license steps; API TBD |
| Nafath / unified access | Planned | OIDC integration TBD |

## Technical enablers in codebase

- Compliance tables `regc_*` + audit RPCs.
- Support & complaint intake with audit event.
- Policy versioning table `regc_legal_policy_documents` (parallel to `legal_documents_versions` gate).

## Submission package

See `docs/government_submission/README.md` for consolidated submission layout.

## Sign-off

Legal / compliance officer signature: _________________  Date: _________
