-- =============================================================================
-- تحديثات RLS على public.properties: تعديل المالك حتى قبل التصاريح (مع حد التعديلات)
-- + تعديل المسوّق المرتبط بعد إصدار التصريح وقبل النشر (مطابقة الهيئة).
--
-- يستبدل سياسة UPDATE الواسعة `properties_owner_admin_update` إن وُجدت.
-- تنفيذ: Supabase SQL Editor. يتطلب وجود `marketer_can_read_property_for_marketing` (20260430).
-- =============================================================================

BEGIN;

-- العمود مُستخدَم في تطبيق Flutter (map: permit_issued_at) ولم يُضف في 20260329 على properties.
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS permit_issued_at timestamptz;

COMMENT ON COLUMN public.properties.permit_issued_at IS
  'وقت إصدار/اعتماد التصريح للعقار؛ يُفضّل ضبطه من RPC سير العمل عند الموافقة على التصريح.';

-- التطبيق يقرأ selected_marketer_id من properties؛ المصدر المنطقي غالباً listing_requests.
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS selected_marketer_id uuid;

COMMENT ON COLUMN public.properties.selected_marketer_id IS
  'المسوّق المختار للطلب؛ يُفضّل مزامنته من listing_requests عند اختيار العرض.';

UPDATE public.properties p
SET selected_marketer_id = lr.selected_marketer_id
FROM public.listing_requests lr
WHERE p.request_id IS NOT NULL
  AND lr.id = p.request_id
  AND lr.selected_marketer_id IS NOT NULL
  AND p.selected_marketer_id IS DISTINCT FROM lr.selected_marketer_id;

CREATE OR REPLACE FUNCTION public.properties_owner_may_update_listing_body(p public.properties)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  /* وسيط مركّب: يجب استخدام (p).عمود وليس p.عمود في دوال SQL */
  SELECT
    (p).owner_id = auth.uid()
    AND (p).published_at IS NULL
    AND COALESCE(lower(trim((p).status)), '') NOT IN (
      'published', 'active', 'live', 'available', 'approved'
    )
    AND COALESCE(lower(trim((p).workflow_stage)), '') NOT IN (
      'permit_pending',
      'permit_issued',
      'published',
      'reserved',
      'cancelled',
      'terminated',
      'archived',
      'inactive_72h',
      'contract_cancelled'
    )
    AND (
      (p).edit_count IS NULL
      OR (p).edit_count < COALESCE((p).max_edits, 3)
    );
$$;

COMMENT ON FUNCTION public.properties_owner_may_update_listing_body(public.properties) IS
  'RLS: المالك يحدّث جسم الإعلان قبل مرحلة التصاريح وبحد أقصى max_edits.';

CREATE OR REPLACE FUNCTION public.properties_marketer_may_update_rega_align(p public.properties)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND (p).published_at IS NULL
    /* إصدار التصريح: طابع زمني أو على الأقل workflow_stage = permit_issued */
    AND (
      (p).permit_issued_at IS NOT NULL
      OR lower(trim(coalesce((p).workflow_stage, ''))) = 'permit_issued'
    )
    AND COALESCE(lower(trim((p).status)), '') NOT IN (
      'published', 'active', 'live', 'available', 'approved'
    )
    AND COALESCE(lower(trim((p).workflow_stage)), '') IN (
      'permit_pending',
      'permit_issued'
    )
    AND (
      (p).selected_marketer_id = auth.uid()
      OR (p).published_by_marketer_id = auth.uid()
    )
    AND public.marketer_can_read_property_for_marketing((p).id);
$$;

COMMENT ON FUNCTION public.properties_marketer_may_update_rega_align(public.properties) IS
  'RLS: مسوّق مرتبط بالطلب يحدّث حقول المطابقة بعد إصدار التصريح وقبل النشر.';

REVOKE ALL ON FUNCTION public.properties_owner_may_update_listing_body(public.properties) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.properties_marketer_may_update_rega_align(public.properties) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.properties_owner_may_update_listing_body(public.properties) TO authenticated;
GRANT EXECUTE ON FUNCTION public.properties_marketer_may_update_rega_align(public.properties) TO authenticated;

DROP POLICY IF EXISTS "properties_owner_admin_update" ON public.properties;

DROP POLICY IF EXISTS "properties_update_owner_marketer_workflow_v1" ON public.properties;

CREATE POLICY "properties_update_owner_marketer_workflow_v1"
  ON public.properties
  FOR UPDATE
  TO authenticated
  USING (
    public.properties_owner_may_update_listing_body(properties)
    OR public.properties_marketer_may_update_rega_align(properties)
  )
  WITH CHECK (
    public.properties_owner_may_update_listing_body(properties)
    OR public.properties_marketer_may_update_rega_align(properties)
  );

COMMENT ON POLICY "properties_update_owner_marketer_workflow_v1" ON public.properties IS
  'مالك: قبل التصاريح؛ مسوّق: مرحلة تصريح + (permit_issued_at أو workflow_stage=permit_issued)، قبل النشر. أعد سياسة admin يدوياً إن كانت is_admin() متوفرة.';

COMMIT;
