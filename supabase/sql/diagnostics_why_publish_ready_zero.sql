-- لماذا property_image_public_home_readable = 0 ؟
-- نفّذ كل قسم على حدة في SQL Editor.
-- إن ظهر is_admin (42501): نفّذ APPLY_NOW_00_is_admin_grant_anon.sql أولاً.

-- (1) هل توجد صور أصلاً؟
SELECT count(*)::bigint AS total_property_images FROM public.property_images;

-- (2) كم إعلان يمرّ فلتر الرئيسية البسيط (20260461)؟
SELECT count(*)::bigint AS home_filter_properties
FROM public.properties p
WHERE p.status <> 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    p.status IN (
      'published','active','available','live','reserved','approved',
      'listed','open','visible','for_sale','for_rent','forsale','forrent'
    )
    OR (p.status = 'draft' AND p.workflow_stage IN ('published','reserved'))
  );

-- (3) كم إعلان يمرّ publish_ready الصارم؟ (مسوّق + REGA + وسائط…)
SELECT count(*)::bigint AS publish_ready_properties
FROM public.properties p
WHERE public.property_public_publish_ready(p);

-- (4) صور مرتبطة بإعلانات home_filter (بعد v3 — نفس دالة السياسة)
-- إن لم تُنفَّذ v3 بعد، استخدم القسم (4b) اليدوي.
SELECT count(*)::bigint AS images_on_home_filter_listings
FROM public.property_images pi
WHERE public.property_id_public_home_feed_visible(pi.property_id);

-- (4b) نفس (4) بدون الدالة — للمشرف فقط قبل تطبيق v3
-- SELECT count(*)::bigint AS images_on_home_filter_listings_manual ...

-- (4c) عينة: صور يتيمة (property_id غير موجود أو محذوف)
SELECT count(*)::bigint AS orphan_or_deleted_parent_images
FROM public.property_images pi
WHERE NOT EXISTS (
  SELECT 1 FROM public.properties p
  WHERE p.id = pi.property_id AND p.status IS DISTINCT FROM 'deleted'
);

-- (5) أسباب استبعاد أول 20 إعلان (للتصحيح اليدوي)
SELECT
  p.id,
  left(coalesce(p.title,''), 40) AS title,
  p.status,
  p.workflow_stage,
  public.property_has_listing_media(p.id, p.video_url) AS has_media,
  (p.published_by_marketer_id IS NOT NULL) AS has_marketer,
  public.property_public_publish_ready(p) AS publish_ready
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
ORDER BY p.created_at DESC NULLS LAST
LIMIT 20;
