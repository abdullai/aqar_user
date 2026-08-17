-- =============================================================================
-- تشخيص 401 على properties للضيف (الويب) — شغّل في Supabase SQL Editor
-- =============================================================================
-- 401 من PostgREST ≠ «لا صفوف». غالباً:
--   (أ) Authorization يحمل JWT منتهٍ أو مفتاح sb_publishable_ كـ Bearer
--   (ب) apikey غير صالح / مقطوع
--   (ج) RLS نادراً يظهر كـ 403 وليس 401
--
-- من SQL هنا تتحقق من (ج) فقط. (أ)(ب) من Network في المتصفح:
--   Request Headers → إن وُجد Authorization: Bearer sb_publishable_… → خطأ عميل
--   إن وُجد Bearer eyJ… منتهٍ → امسح localStorage للموقع أو أعد الدخول كضيف
-- =============================================================================

-- (1) سياسات SELECT على properties لدور anon
SELECT policyname, roles, permissive, qual::text AS using_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd = 'SELECT'
ORDER BY policyname;

-- (2) ماذا يرى anon من properties (نفس منطق الرئيسية تقريباً)
SET ROLE anon;
SELECT COUNT(*)::bigint AS properties_visible_to_anon
FROM public.properties p
WHERE p.status <> 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false;
RESET ROLE;

-- (3) طلبات السوق للضيف (للمقارنة — إن نجحت في Network و properties فشلت → ليست RLS)
SET ROLE anon;
SELECT COUNT(*)::bigint AS market_requests_visible_to_anon
FROM public.market_property_requests m
WHERE m.status IN ('published', 'active', 'live');
RESET ROLE;

-- (4) إن فشل SET ROLE anon:
--   GRANT anon TO postgres;  -- مرة واحدة كمشرف
-- ثم أعد تشغيل البلوك (2)(3).
