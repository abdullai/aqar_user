-- =============================================================================
-- إصلاح نهائي للتجربة: إعلان واحد + سياسة anon واضحة
-- (بعد diagnostics_properties_table_empty_or_rls.sql)
-- =============================================================================

BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;

-- سياسة رئيسية واحدة (نصّ صريح مع تحويل enum إن وُجد)
DROP POLICY IF EXISTS "properties_anon_debug_any_non_deleted" ON public.properties;
DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;
DROP POLICY IF EXISTS "properties_public_home_select_old" ON public.properties;

CREATE POLICY "properties_public_home_select"
  ON public.properties
  FOR SELECT
  TO anon, authenticated
  USING (
    coalesce(status::text, '') IS DISTINCT FROM 'deleted'
    AND COALESCE(home_feed_suppressed, false) = false
    AND (
      coalesce(status::text, '') IN (
        'published', 'active', 'available', 'live', 'reserved', 'approved',
        'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
      )
      OR (
        coalesce(status::text, '') = 'draft'
        AND coalesce(workflow_stage::text, '') IN (
          'waiting_marketers', 'marketer_selected', 'contract_pending',
          'contract_sent', 'contract_returned', 'contract_signed',
          'permit_pending', 'permit_issued', 'published', 'reserved', 'inactive_72h'
        )
      )
    )
  );

-- حدّث أحدث صف (حتى لو كان deleted) للتجربة
UPDATE public.properties p
SET
  status = 'published',
  workflow_stage = 'published',
  home_feed_suppressed = false
WHERE p.id = (
  SELECT id FROM public.properties ORDER BY created_at DESC NULLS LAST LIMIT 1
)
RETURNING p.id, p.status, p.workflow_stage;

COMMIT;

SELECT count(*)::bigint AS total_rows FROM public.properties;
SELECT count(*)::bigint AS not_deleted
FROM public.properties
WHERE coalesce(status::text, '') IS DISTINCT FROM 'deleted';

SET ROLE anon;
SELECT count(*)::bigint AS properties_visible_as_anon FROM public.properties;
RESET ROLE;
