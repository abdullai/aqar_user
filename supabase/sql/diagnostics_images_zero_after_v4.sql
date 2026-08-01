-- بعد نجاح v4: images_home_feed_visible = 0 — شغّل الأقسام واحداً واحداً

-- (A) هل توجد صور؟
SELECT count(*)::bigint AS total_property_images FROM public.property_images;

-- (B) إعلانات تمرّ فلتر الرئيسية (دالة السياسة)
SELECT count(*)::bigint AS home_feed_properties
FROM public.properties p
WHERE public.property_id_public_home_feed_visible(p.id);

-- (C) إعلانات تمرّ فلتر diagnostics اليدوي الضيق (draft فقط published/reserved)
SELECT count(*)::bigint AS home_filter_manual_narrow
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

-- (D) أول 10 صور + هل الإعلان الأب يمرّ الفلتر؟
SELECT
  pi.id AS image_id,
  pi.property_id,
  left(coalesce(pi.path::text, pi.file_name::text, ''), 60) AS path_preview,
  p.status,
  p.workflow_stage,
  COALESCE(p.home_feed_suppressed, false) AS suppressed,
  public.property_id_public_home_feed_visible(pi.property_id) AS visible_in_home_feed
FROM public.property_images pi
LEFT JOIN public.properties p ON p.id = pi.property_id
ORDER BY pi.created_at DESC NULLS LAST
LIMIT 10;

-- (E) كمشرف: REST يجب 200 — اختبر من المتصفح وليس SQL
-- GET /rest/v1/property_images?select=property_id,path&limit=5
-- Header: apikey فقط (بدون Bearer JWT قديم)
