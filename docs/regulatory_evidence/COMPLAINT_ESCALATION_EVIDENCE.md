# COMPLAINT_ESCALATION_EVIDENCE

## Architectural summary

End-user complaints are stored in `regc_user_complaints` with **strict ownership RLS**. Escalations are linked rows in `regc_complaint_escalations` readable/insertable only when the parent complaint belongs to `auth.uid()`.

## RLS excerpt — escalation via parent ownership

```sql
CREATE POLICY complaint_escalations_select_via_complaint ON public.regc_complaint_escalations
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.regc_user_complaints c
      WHERE c.id = complaint_id AND c.user_id = auth.uid()
    )
  );
```

## Example escalation flow (mock)

See `docs/evidence_exports/complaint_escalation_sample.csv`.

## Example internal note (operator — mock log)

```text
[2026-05-02T09:15:00Z] ticket=00000000-0000-4000-8000-00000000e001 status=escalated to=compliance@example.sa sla_hours=48 MOCK
```

**Validator:** `supabase/sql/staging_validation/validate_ticket_isolation.sql`
