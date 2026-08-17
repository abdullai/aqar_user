-- =============================================================================
-- المالك يقرأ عقاره وصوره (معاينة / مسودة) — نفس الحاجة التي تغطيها سياسات المسوّق.
-- بدون ذلك قد يفشل SELECT على properties/property_images في لوحة المالك
-- بينما يمرّ للمسوّق عبر marketer_can_read_property_for_marketing.
--
-- نفّذ في Supabase → SQL Editor. السياسات تُضاف بجانب الموجودة (OR على SELECT).
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "owner_select_own_properties"
  ON public.properties;

CREATE POLICY "owner_select_own_properties"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (owner_id = auth.uid());

DROP POLICY IF EXISTS "owner_select_images_of_own_properties"
  ON public.property_images;

CREATE POLICY "owner_select_images_of_own_properties"
  ON public.property_images
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_images.property_id
        AND p.owner_id = auth.uid()
    )
  );

COMMIT;
