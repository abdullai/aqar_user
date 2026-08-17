-- =============================================================================
-- مراجعة شاملة: مفاتيح (من اللوحة) + RLS + منح + ما يراه anon/authenticated
-- المشروع: عقار موثوق — شغّل في Supabase → SQL Editor
--
-- ⚠️ المفاتيح (sb_publishable_ / eyJ anon / sb_secret_) لا تُخزَّن في Postgres
--    ولا يمكن التحقق منها هنا. راجع:
--    Dashboard → Project Settings → API Keys
--    والموقع: https://YOUR_APP/supabase_config.json
--
-- ⚠️ 401 من المتصفح غالباً = Authorization: Bearer JWT قديم (ليس RLS).
--    RLS الفاشل يعطي غالباً 200 + [] أو 403 — نادراً 401.
--
-- كيفية التشغيل: نفّذ كل قسم «وحده» (حدّد السطور و Run) لأن الواجهة
-- تعرض أحياناً نتيجة آخر SELECT فقط.
-- =============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- (0) ملخص واحد — ابدأ هنا
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
  (SELECT c.relrowsecurity FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'properties') AS properties_rls_on,
  (SELECT COUNT(*) FROM pg_policies p
   WHERE p.schemaname = 'public' AND p.tablename = 'properties'
     AND p.cmd = 'SELECT' AND 'anon' = ANY (p.roles)) AS properties_select_policies_for_anon,
  EXISTS (
    SELECT 1 FROM information_schema.role_table_grants g
    WHERE g.table_schema = 'public' AND g.table_name = 'properties'
      AND g.grantee = 'anon' AND g.privilege_type = 'SELECT'
  ) AS anon_grant_select_properties,
  EXISTS (
    SELECT 1 FROM information_schema.role_table_grants g
    WHERE g.table_schema = 'public' AND g.table_name = 'property_images'
      AND g.grantee = 'anon' AND g.privilege_type = 'SELECT'
  ) AS anon_grant_select_property_images,
  (SELECT COUNT(*)::bigint FROM public.properties
   WHERE status <> 'deleted'
     AND COALESCE(home_feed_suppressed, false) = false) AS properties_rows_superuser_rough,
  (SELECT COUNT(*)::bigint FROM public.market_property_requests
   WHERE status IN ('published','active','live')) AS market_rows_superuser_rough;

-- قراءة سريعة:
-- • properties_select_policies_for_anon = 0  → ضيف لن يرى إعلانات (طبّق migration الرئيسية)
-- • anon_grant_select_* = false             → GRANT SELECT ناقص
-- • إن (0) سليم لكن المتصفح 401            → المشكلة عميل/JWT وليس SQL

-- ═══════════════════════════════════════════════════════════════════════════
-- (1) RLS مفعّل؟ على الجداول الحساسة للرئيسية
-- ═══════════════════════════════════════════════════════════════════════════
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
    'properties',
    'property_images',
    'market_property_requests',
    'users_profiles'
  )
ORDER BY c.relname;

-- ═══════════════════════════════════════════════════════════════════════════
-- (2) من لديه GRANT SELECT؟ (anon / authenticated)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('properties', 'property_images', 'market_property_requests')
  AND grantee IN ('anon', 'authenticated', 'public')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;

-- ═══════════════════════════════════════════════════════════════════════════
-- (3) كل سياسات SELECT على properties + property_images + market
-- ═══════════════════════════════════════════════════════════════════════════
SELECT tablename,
       policyname,
       permissive::text AS permissive_or_restrictive,
       roles::text AS roles,
       cmd,
       left(qual::text, 200) AS using_preview
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('properties', 'property_images', 'market_property_requests')
  AND cmd IN ('SELECT', 'ALL')
ORDER BY tablename, policyname;

-- ═══════════════════════════════════════════════════════════════════════════
-- (4) سياسات anon فقط على properties (الأهم للضيف)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT policyname, permissive, roles, qual::text AS using_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd = 'SELECT'
  AND 'anon' = ANY (roles)
ORDER BY policyname;

-- ═══════════════════════════════════════════════════════════════════════════
-- (5) دوال RLS المساعدة — هل anon يستطيع EXECUTE؟ (سبب 403 أحياناً)
-- ═══════════════════════════════════════════════════════════════════════════
SELECT p.proname AS function_name,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'property_public_publish_ready',
    'property_marketer_public_verified',
    'property_has_listing_media',
    'property_image_public_home_readable'
  )
ORDER BY p.proname;

-- ═══════════════════════════════════════════════════════════════════════════
-- (6) ماذا يرى دور anon؟ — صف واحد (عقارات + طلبات سوق)
--     إن فشل: GRANT anon TO postgres;  ثم أعد التشغيل
-- ═══════════════════════════════════════════════════════════════════════════
SET ROLE anon;
SELECT
  (SELECT COUNT(*)::bigint FROM public.properties p
   WHERE p.status <> 'deleted'
     AND COALESCE(p.home_feed_suppressed, false) = false
     AND (
       p.status IN (
         'published','active','available','live','reserved','approved',
         'listed','open','visible','for_sale','for_rent','forsale','forrent'
       )
       OR (p.status = 'draft' AND p.workflow_stage IN ('published','reserved'))
     )) AS home_properties_as_anon,
  (SELECT COUNT(*)::bigint FROM public.market_property_requests m
   WHERE m.status IN (
     'published','active','live','open','visible','under_review',
     'in_progress','seeking','bidding','negotiating','collecting_offers',
     'delete_requested'
   )) AS market_requests_as_anon;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- (7) عينة 5 صفوف كما يراها anon (إن العدد > 0)
-- ═══════════════════════════════════════════════════════════════════════════
SET ROLE anon;
SELECT p.id, p.status, p.workflow_stage, p.home_feed_suppressed, p.created_at
FROM public.properties p
WHERE p.status <> 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
ORDER BY p.created_at DESC NULLS LAST
LIMIT 5;
RESET ROLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- (8) جاهزية النشر العام (دوال الجودة) — كمشرف
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
  COUNT(*) FILTER (WHERE status <> 'deleted') AS total_not_deleted,
  COUNT(*) FILTER (
    WHERE status <> 'deleted'
      AND COALESCE(home_feed_suppressed, false) = false
      AND public.property_public_publish_ready(p)
  ) AS public_publish_ready,
  COUNT(*) FILTER (
    WHERE status <> 'deleted'
      AND public.property_has_listing_media(p.id)
  ) AS has_listing_media
FROM public.properties p;

-- ═══════════════════════════════════════════════════════════════════════════
-- (9) authenticated — هل يرى أكثر من anon؟ (اختياري)
-- ═══════════════════════════════════════════════════════════════════════════
-- SET ROLE authenticated;
-- SELECT COUNT(*) FROM public.properties WHERE status <> 'deleted';
-- RESET ROLE;

-- =============================================================================
-- جدول تفسير النتائج
-- =============================================================================
-- | النتيجة SQL              | المتصفح 401     | المتصفح 200 []   |
-- |--------------------------|-----------------|------------------|
-- | home_properties_as_anon=0| ليس 401 بسبب RLS| طبيعي (فارغ)     |
-- | home_properties_as_anon>0| المشكلة JWT/عميل| يجب ظهور إعلانات |
-- | policies_for_anon=0      | طبّق migration  | —                |
-- | anon_can_execute=false   | قد 403 لا 401   | —                |
-- =============================================================================
