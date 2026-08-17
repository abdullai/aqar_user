# AUDIT_LOGGING_EVIDENCE

## Architectural summary

`regc_audit_logs` is **append-oriented** from the application perspective: authenticated users do **not** receive `INSERT` grants on the table; they call `compliance_append_audit`, which sets `user_id := auth.uid()` inside a definer function.

## SQL excerpt

```sql
INSERT INTO public.regc_audit_logs (user_id, event_type, metadata)
VALUES (v_uid, trim(p_event_type), coalesce(p_metadata, '{}'::jsonb));
```

## Example audit trail (mock)

| id | user_id | event_type | metadata | created_at |
|----|---------|------------|----------|------------|
| (uuid) | 00000000-0000-4000-8000-0000000000a1 | terms.accepted | `{"version":"2026-04-05-SA","lang":"ar"}` | 2026-05-01T12:00:00Z |

Full mock export: `docs/evidence_exports/audit_logs_sample.csv`

## Integrity notes

- **Client:** cannot pick another user’s `user_id` via RPC.  
- **DBA:** can still modify rows — mitigate with role separation + optional SIEM export.

**Validator:** `supabase/sql/staging_validation/validate_audit_logs.sql`
