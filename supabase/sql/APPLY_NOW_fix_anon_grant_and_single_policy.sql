-- =============================================================================
-- إصلاح: GRANT + سياسة واحدة لـ anon (بعد final_one_row_diagnostic)
--
-- إن total_rows = 0 في التشخيص → لا تفيد هذه السكربتات؛ أنشئ إعلاناً من التطبيق.
-- =============================================================================

BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON TABLE public.properties TO anon, authenticated, service_role;

ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

-- إزالة كل سياسات SELECT (إعادة بناء نظيفة)
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'properties'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.properties', pol.policyname);
  END LOOP;
END $$;

-- سياسة ضيف/مسجّل: الرئيسية (20260461 + cast)
CREATE POLICY "properties_public_home_select"
  ON public.properties FOR SELECT
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

-- مالك يرى إعلانه
CREATE POLICY "owner_select_own_properties"
  ON public.properties FOR SELECT
  TO authenticated
  USING (owner_id = auth.uid());

COMMIT;

-- تحديث أحدث صف إن وُجد
UPDATE public.properties p
SET status = 'published', workflow_stage = 'published', home_feed_suppressed = false
WHERE p.id = (SELECT id FROM public.properties ORDER BY created_at DESC NULLS LAST LIMIT 1)
RETURNING id, status;

SELECT count(*)::bigint AS total_rows FROM public.properties;

SET ROLE anon;
SELECT count(*)::bigint AS anon_count FROM public.properties;
RESET ROLE;
