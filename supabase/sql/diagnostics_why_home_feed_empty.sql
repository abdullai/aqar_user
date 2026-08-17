-- لماذا الرئيسية فارغة؟ (بعد نجاح v4 و REST 200)
-- نفّذ كل قسم لوحده — الواجهة تعرض أحياناً آخر SELECT فقط.

-- (1) إجمالي الإعلانات (بدون فلتر)
SELECT count(*)::bigint AS all_properties FROM public.properties;

SELECT count(*)::bigint AS not_deleted
FROM public.properties WHERE status IS DISTINCT FROM 'deleted';

-- (2) توزيع status (أهم 15)
SELECT status, count(*)::bigint AS n
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted'
GROUP BY status
ORDER BY n DESC NULLS LAST
LIMIT 15;

-- (3) توزيع workflow_stage للمسودات
SELECT workflow_stage, count(*)::bigint AS n
FROM public.properties
WHERE status = 'draft'
GROUP BY workflow_stage
ORDER BY n DESC NULLS LAST
LIMIT 15;

-- (4) مكمّن home_feed_suppressed
SELECT
  COALESCE(home_feed_suppressed, false) AS suppressed,
  count(*)::bigint AS n
FROM public.properties
WHERE status IS DISTINCT FROM 'deleted'
GROUP BY 1;

-- (5) فلاتر الرئيسية
SELECT count(*)::bigint AS home_feed_broad_fn
FROM public.properties p
WHERE public.property_id_public_home_feed_visible(p.id);

SELECT count(*)::bigint AS publish_ready_strict
FROM public.properties p
WHERE public.property_public_publish_ready(p);

-- (6) صور
SELECT count(*)::bigint AS total_property_images FROM public.property_images;

-- (7) ماذا يرى anon على properties؟ (بعد GRANT is_admin)
SET ROLE anon;
SELECT count(*)::bigint AS properties_visible_as_anon FROM public.properties;
RESET ROLE;

-- (8) سياسة SELECT لـ anon على properties
SELECT policyname, permissive, qual::text AS using_expr
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd = 'SELECT'
  AND 'anon' = ANY (roles)
ORDER BY policyname;

-- (9) آخر 15 إعلان غير محذوف — لماذا لا يظهر؟
SELECT
  p.id,
  left(coalesce(p.title, ''), 35) AS title,
  p.status,
  p.workflow_stage,
  COALESCE(p.home_feed_suppressed, false) AS suppressed,
  public.property_id_public_home_feed_visible(p.id) AS home_broad,
  public.property_public_publish_ready(p) AS publish_ready
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
ORDER BY p.created_at DESC NULLS LAST
LIMIT 15;
