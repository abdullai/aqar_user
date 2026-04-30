-- =============================================================================
-- يسمح لعضو الفريق بقراءة سجلات النشاط التي قام بها هو فقط (إلى جانب سياسة المالك الحالية).
-- المالك يبقى يرى كل org_activity_log عبر السياسة الموجودة مسبقاً.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS org_activity_log_select_member_own ON public.org_activity_log;

CREATE POLICY org_activity_log_select_member_own ON public.org_activity_log
  FOR SELECT TO authenticated
  USING (
    actor_user_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.org_memberships m
      WHERE m.org_id = org_activity_log.org_id
        AND m.user_id = auth.uid()
        AND m.status = 'active'
    )
  );

COMMIT;
