-- =============================================================================
-- إصلاح 401 على property_images عبر REST (ضيف / Publishable key)
--
-- count = 0 من استعلام property_image_public_home_readable طبيعي إذا:
--   • لا توجد صور في property_images، أو
--   • لا إعلان يمرّ فلتر property_public_publish_ready (مسوّق/REGA/وسائط).
--
-- هذا السكربت يفتح قراءة الصور لأي إعلان يظهر في فلتر الرئيسية العام
-- (نفس منطق 20260461_properties_public_home_select_rls) — بدون اشتراط publish_ready.
--
-- ⚠️ النسخة أدناه تفشل بـ permission denied for function is_admin — استخدم بدلاً منها:
--    APPLY_NOW_v3_property_images_anon_rest.sql
--
-- نفّذ كاملاً في SQL Editor ثم اختبر REST (انظر الأسفل).
-- =============================================================================

BEGIN;

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.property_images TO anon, authenticated;

ALTER TABLE public.property_images ENABLE ROW LEVEL SECURITY;

-- سياسة مبسطة للتضمين في PostgREST (لا تعتمد على publish_ready الصارم)
DROP POLICY IF EXISTS "property_images_public_home_select" ON public.property_images;
DROP POLICY IF EXISTS "property_images_anon_home_embed" ON public.property_images;

CREATE POLICY "property_images_anon_home_embed"
  ON public.property_images
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_images.property_id
        AND p.status IS DISTINCT FROM 'deleted'
        AND COALESCE(p.home_feed_suppressed, false) = false
        AND (
          p.status IN (
            'published', 'active', 'available', 'live', 'reserved', 'approved',
            'listed', 'open', 'visible', 'for_sale', 'for_rent', 'forsale', 'forrent'
          )
          OR (
            p.status = 'draft'
            AND p.workflow_stage IN ('published', 'reserved')
          )
        )
    )
  );

COMMENT ON POLICY "property_images_anon_home_embed" ON public.property_images IS
  'صور الإعلانات الظاهرة في الرئيسية العامة — يطابق فلتر التطبيق (20260461).';

COMMIT;

-- ─── تحقق كمشرف (قد يكون > 0 حتى لو publish_ready = 0) ───
SELECT 'images_for_home_filter' AS check_name,
       count(*)::bigint AS count
FROM public.property_images pi
WHERE EXISTS (
  SELECT 1 FROM public.properties p
  WHERE p.id = pi.property_id
    AND p.status IS DISTINCT FROM 'deleted'
    AND COALESCE(p.home_feed_suppressed, false) = false
    AND (
      p.status IN (
        'published','active','available','live','reserved','approved',
        'listed','open','visible','for_sale','for_rent','forsale','forrent'
      )
      OR (p.status = 'draft' AND p.workflow_stage IN ('published','reserved'))
    )
);

-- ─── تحقق كدور anon (الأهم — يجب ألا يفشل) ───
SET ROLE anon;
SELECT count(*)::bigint AS property_images_visible_as_anon
FROM public.property_images;
RESET ROLE;

-- بعد النشر: في المتصفح أو curl يجب أن يعيد 200 وليس 401:
-- GET /rest/v1/property_images?select=property_id,path&limit=1
-- Header: apikey: <sb_publishable_...>
