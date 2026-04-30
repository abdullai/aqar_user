-- =============================================================================
-- قراءة موحّدة للمسوّق: عقار المعاينة + صوره عند وجود دعوة أو عرض أو عقد أو تصريح.
--
-- المشكلة: سياسة 20260328 تعتمد على listing_request_invites فقط؛ من لديه عرض
-- بدون دعوة نشطة قد لا يمرّ EXISTS فيُرفض SELECT على properties → بطاقة بلا سعر/صور.
-- كما أن EXISTS المتداخلة قد تتعارض مع RLS على listing_requests.
--
-- الحل: دالة SECURITY DEFINER + row_security = off (مثل marketer_can_read_listing_request).
--
-- متطلبات: أعمدة request_id، preview_property_id على listing_requests؛
--           ربط properties بـ request_id أو كمعاينة عبر preview_property_id.
--
-- نفّذ في Supabase → SQL Editor. للتراجع: أسقط السياسات الجديدة وأعد سياسة 20260328 إن لزم.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "marketer_select_linked_preview_properties"
  ON public.properties;

DROP POLICY IF EXISTS "marketer_select_linked_property_images"
  ON public.property_images;

DROP POLICY IF EXISTS "marketer_select_linked_preview_properties_v2"
  ON public.properties;

DROP POLICY IF EXISTS "marketer_select_linked_property_images_v2"
  ON public.property_images;

DROP FUNCTION IF EXISTS public.marketer_can_read_property_for_marketing(uuid);

CREATE OR REPLACE FUNCTION public.marketer_can_read_property_for_marketing(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT p_property_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.listing_requests lr
    WHERE (
        lr.preview_property_id = p_property_id
        OR EXISTS (
          SELECT 1
          FROM public.properties p
          WHERE p.id = p_property_id
            AND p.request_id IS NOT NULL
            AND p.request_id = lr.id
        )
      )
      AND (
        EXISTS (
          SELECT 1
          FROM public.listing_request_invites inv
          WHERE inv.request_id = lr.id
            AND inv.marketer_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1
          FROM public.listing_offers o
          WHERE o.request_id = lr.id
            AND o.marketer_id = auth.uid()
        )
      )
  );
$$;

COMMENT ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) IS
  'RLS: مسوّق له دعوة/عرض/عقد/تصريح على طلب يربط هذا العقار (معاينة أو request_id).';

REVOKE ALL ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) TO service_role;

CREATE POLICY "marketer_select_linked_preview_properties_v2"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (public.marketer_can_read_property_for_marketing(id));

CREATE POLICY "marketer_select_linked_property_images_v2"
  ON public.property_images
  FOR SELECT
  TO authenticated
  USING (
    public.marketer_can_read_property_for_marketing(property_images.property_id)
  );

COMMIT;
