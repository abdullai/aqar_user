-- =============================================================================
-- تشخيص سريع: شغّل في Supabase SQL Editor بالترتيب.
-- الهدف: مقارنة ما يراه postgres (بدون RLS) بما يراه دور anon (كعميل التطبيق).
--
-- إن ظهرت لك نتيجة عمود واحد فقط: بعض الواجهات تعرض آخر SELECT في السكربت؛
-- استخدم البلوك (4) الذي يُرجع عمودين في صف واحد بعد SET ROLE مرة واحدة.
-- إن فشل SET ROLE anon: نفّذ مرة واحدة كمشرف ثم أعد المحاولة:
--   GRANT anon TO postgres;
-- =============================================================================

-- (1) هل RLS مفعّل؟
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('properties', 'market_property_requests');

-- (2) كل سياسات SELECT على الجدولين (الحاسم: هل يوجد TO anon لـ properties؟)
SELECT tablename,
       policyname,
       roles,
       cmd,
       qual::text AS using_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('properties', 'market_property_requests')
ORDER BY tablename, policyname;

-- (2b) PERMISSIVE vs RESTRICTIVE على properties — إن ظهرت RESTRICTIVE ضيّقة مع
--      `properties_public_home_select` قد تُحجب المسودات رغم نجاح سياسة الرئيسية.
SELECT tablename,
       policyname,
       permissive,
       roles,
       cmd,
       qual::text AS using_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'properties'
  AND cmd = 'SELECT'
ORDER BY policyname;

-- (3) عدّ الصفوف «كما يفترض التطبيق» — بدون تمثيل RLS (مثل استعلامك الذي أعطى 21)
SELECT COUNT(*) AS count_superuser_logic
FROM public.properties
WHERE status <> 'deleted'
  AND COALESCE(home_feed_suppressed, false) = false
  AND (
    status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved',
      'listed', 'open', 'visible', 'for_sale', 'for_rent'
    )
    OR (
      status = 'draft'
      AND workflow_stage IN (
        'waiting_marketers', 'marketer_selected', 'contract_pending',
        'contract_sent', 'contract_returned', 'contract_signed',
        'permit_pending', 'permit_issued', 'published', 'reserved',
        'inactive_72h'
      )
    )
  );

-- (4) ماذا يرى دور anon؟ — عمودان في نفس الصف (عقارات الرئيسية + طلبات السوق).
--     إن فشل SET ROLE: جرّب GRANT أعلاه، أو اختبر من REST بمفتاح anon المنشور.
SET ROLE anon;
SELECT
  (
    SELECT COUNT(*)::bigint
    FROM public.properties
    WHERE status <> 'deleted'
      AND COALESCE(home_feed_suppressed, false) = false
      AND (
        status IN (
          'published', 'active', 'available', 'live', 'reserved', 'approved',
          'listed', 'open', 'visible', 'for_sale', 'for_rent'
        )
        OR (
          status = 'draft'
          AND workflow_stage IN (
            'waiting_marketers', 'marketer_selected', 'contract_pending',
            'contract_sent', 'contract_returned', 'contract_signed',
            'permit_pending', 'permit_issued', 'published', 'reserved',
            'inactive_72h'
          )
        )
      )
  ) AS count_properties_as_anon,
  (
    SELECT COUNT(*)::bigint
    FROM public.market_property_requests
    WHERE status IN (
      'published', 'active', 'live', 'open', 'visible',
      'under_review', 'in_progress', 'seeking', 'bidding',
      'negotiating', 'collecting_offers'
    )
  ) AS market_requests_as_anon;
RESET ROLE;
