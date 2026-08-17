-- =============================================================================
-- تدقيق RLS + صلاحيات — يكشف لماذا يرى anon/authenticated صفوفاً أو لا.
-- نفّذ في Supabase → SQL Editor (دور postgres / لوحة المشروع).
--
-- ملاحظة واجهة Supabase: عند تشغيل الملف كاملاً قد تُعرض نتيجة آخر SELECT فقط.
--   • شغّل القسم (0) وحده لرؤية ملخص في صف واحد.
--   • شغّل القسم (anon) وحده لرؤية عدّ الصفوف كما يراه دور anon (عمودان).
--   • للتفصيل: شغّل أقسام (A)–(D) كل قسم على حدة.
-- =============================================================================

-- ═══ (0) ملخص في صف واحد — نفّذ هذا السطر وحده أولاً ═══════════════════════
SELECT
  (SELECT c.relrowsecurity
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'properties') AS properties_rls_enabled,
  (SELECT c.relrowsecurity
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'market_property_requests')
    AS market_requests_rls_enabled,
  (SELECT COUNT(*)
   FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND p.tablename = 'properties'
     AND p.cmd = 'SELECT'
     AND ('anon'::name = ANY (p.roles))) AS properties_select_policies_count_for_role_anon,
  (SELECT COUNT(*)
   FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND p.tablename = 'properties'
     AND p.cmd = 'SELECT') AS properties_select_policies_total,
  EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants g
    WHERE g.table_schema = 'public'
      AND g.table_name = 'properties'
      AND g.grantee = 'anon'
      AND g.privilege_type = 'SELECT'
  ) AS anon_has_grant_select_on_properties,
  EXISTS (
    SELECT 1
    FROM information_schema.role_table_grants g
    WHERE g.table_schema = 'public'
      AND g.table_name = 'market_property_requests'
      AND g.grantee = 'anon'
      AND g.privilege_type = 'SELECT'
  ) AS anon_has_grant_select_on_market_requests,
  (SELECT COUNT(*)
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
     )) AS properties_count_logic_superuser,
  (SELECT COUNT(*)
   FROM public.market_property_requests
   WHERE status IN (
     'published', 'active', 'live', 'open', 'visible',
     'under_review', 'in_progress', 'seeking', 'bidding',
     'negotiating', 'collecting_offers'
   )) AS market_requests_count_logic_superuser;

-- ═══ (anon) محاكاة دور anon — نفّذ هذا القسم وحده (صف واحد، عمودان) ═══════
SET ROLE anon;
SELECT
  (SELECT COUNT(*)
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
     )) AS properties_visible_as_anon,
  (SELECT COUNT(*)
   FROM public.market_property_requests
   WHERE status IN (
     'published', 'active', 'live', 'open', 'visible',
     'under_review', 'in_progress', 'seeking', 'bidding',
     'negotiating', 'collecting_offers'
   )) AS market_requests_visible_as_anon;
RESET ROLE;

-- ─── (A) هل RLS مفعّل على الجدولين؟ ─────────────────────────────────────────
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN ('properties', 'market_property_requests');

-- ─── (B) من لديه SELECT على الجدولين؟ (anon / authenticated / public) ───────
SELECT table_schema,
       table_name,
       grantee,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('properties', 'market_property_requests')
  AND grantee IN ('anon', 'authenticated', 'public', 'service_role')
GROUP BY table_schema, table_name, grantee
ORDER BY table_name, grantee;

-- ─── (C) كل سياسات RLS على الجدولين (الحاسم: أسماء السياسات + الأدوار + الشرط) ─
SELECT schemaname,
       tablename,
       policyname,
       cmd AS operation,
       permissive::text AS mode,
       roles::text AS applies_to_roles,
       qual::text AS using_expression,
       with_check::text AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('properties', 'market_property_requests')
ORDER BY tablename, cmd, policyname;

-- ─── (D) عدد صفوف الرئيسية «منطق التطبيق» بدون SET ROLE (كمشرف) ───────────────
SELECT COUNT(*) AS properties_count_logic_as_superuser
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

-- =============================================================================
-- قراءة سريعة للملخص (0):
--
-- • properties_select_policies_count_for_role_anon = 0 → غالباً لا يرى anon
--   صفوف properties عبر RLS (طبّق 20260461_properties_public_home_select_rls.sql).
-- • anon_has_grant_select_on_properties = false → تحتاج GRANT SELECT (ضمن 20260461).
-- • properties_count_logic_superuser كبير و properties_visible_as_anon = 0
--   → نفس التشخيص: RLS/منح على properties.
-- • market_requests_visible_as_anon يطابق عدد الصفوف عندك (مثلاً 4) → طلبات السوق سليمة.
-- =============================================================================
