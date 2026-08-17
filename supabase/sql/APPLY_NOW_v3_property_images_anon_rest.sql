-- =============================================================================
-- إصلاح 401 على property_images + خطأ is_admin (42501)
--
-- السبب: سياسة EXISTS على properties تُقيّم كل سياسات RLS للجدول،
--         بما فيها سياسات تستدعي is_admin() بدون GRANT EXECUTE لـ anon.
--
-- الحل: دالة SECURITY DEFINER + SET row_security = off (نفس نمط
--       property_image_public_home_readable) — فلتر الرئيسية البسيط فقط.
--
-- ⚠️ إن فشل بـ is_admin: نفّذ أولاً APPLY_NOW_00_is_admin_grant_anon.sql
--    ثم APPLY_NOW_v4_property_images_anon_rest.sql (يزيل كل السياسات القديمة).
--
-- نفّذ كاملاً في SQL Editor ثم اختبر REST (انظر الأسفل).
-- =============================================================================

BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.property_images TO anon, authenticated;

ALTER TABLE public.property_images ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.property_id_public_home_feed_visible(
  p_property_id uuid
)
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
      FROM public.properties p
      WHERE p.id = p_property_id
        AND p.status IS DISTINCT FROM 'deleted'
        AND COALESCE(p.home_feed_suppressed, false) = false
        AND (
          p.status IN (
            'published', 'active', 'available', 'live', 'reserved', 'approved',
            'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
          )
          OR (
            p.status = 'draft'
            AND p.workflow_stage IN (
              'waiting_marketers',
              'marketer_selected',
              'contract_pending',
              'contract_sent',
              'contract_returned',
              'contract_signed',
              'permit_pending',
              'permit_issued',
              'published',
              'reserved',
              'inactive_72h'
            )
          )
        )
    );
$$;

COMMENT ON FUNCTION public.property_id_public_home_feed_visible(uuid) IS
  'هل الإعلان يظهر في فلتر الرئيسية العام؟ (بدون publish_ready — لتجنب is_admin في RLS).';

REVOKE ALL ON FUNCTION public.property_id_public_home_feed_visible(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_id_public_home_feed_visible(uuid)
  TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "property_images_public_home_select" ON public.property_images;
DROP POLICY IF EXISTS "property_images_anon_home_embed" ON public.property_images;

CREATE POLICY "property_images_anon_home_embed"
  ON public.property_images
  FOR SELECT
  TO anon, authenticated
  USING (public.property_id_public_home_feed_visible(property_id));

COMMENT ON POLICY "property_images_anon_home_embed" ON public.property_images IS
  'صور الإعلانات الظاهرة في الرئيسية — عبر دالة آمنة بدون تقييم RLS على properties.';

COMMIT;

-- ─── تحقق كمشرف ───
SELECT 'images_for_home_feed' AS check_name,
       count(*)::bigint AS count
FROM public.property_images pi
WHERE public.property_id_public_home_feed_visible(pi.property_id);

SELECT count(*)::bigint AS total_property_images FROM public.property_images;

SELECT count(*)::bigint AS home_filter_properties
FROM public.properties p
WHERE public.property_id_public_home_feed_visible(p.id);

-- ─── تحقق كدور anon (يجب ألا يفشل بـ is_admin) ───
SET ROLE anon;
SELECT count(*)::bigint AS property_images_visible_as_anon
FROM public.property_images;
RESET ROLE;

-- بعد النشر: GET /rest/v1/property_images?select=property_id,path&limit=1
-- Header: apikey: <sb_publishable_...>  → 200 (قد يكون [] إن count=0)
