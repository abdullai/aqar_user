-- =============================================================================
-- مسوّق يقرأ عقار المعاينة + صوره المرتبطة بدعواته (RLS)
-- بدون ذلك قد تظهر بطاقات «إعلاناتي» بدون صور/عنوان لأن SELECT على properties يُرفض.
-- نفّذ مرة واحدة في Supabase SQL Editor.
-- يتطلب عمود listing_requests.preview_property_id (موجود في تدفق التسويق).
-- =============================================================================

DROP POLICY IF EXISTS "marketer_select_linked_preview_properties" ON public.properties;
CREATE POLICY "marketer_select_linked_preview_properties"
ON public.properties
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.listing_request_invites inv
    JOIN public.listing_requests lr ON lr.id = inv.request_id
    WHERE inv.marketer_id = auth.uid()
      AND (
        properties.id = lr.preview_property_id
        OR properties.request_id = lr.id
      )
  )
);

DROP POLICY IF EXISTS "marketer_select_linked_property_images" ON public.property_images;
CREATE POLICY "marketer_select_linked_property_images"
ON public.property_images
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = property_images.property_id
      AND EXISTS (
        SELECT 1
        FROM public.listing_request_invites inv
        JOIN public.listing_requests lr ON lr.id = inv.request_id
        WHERE inv.marketer_id = auth.uid()
          AND (
            p.id = lr.preview_property_id
            OR p.request_id = lr.id
          )
      )
  )
);
