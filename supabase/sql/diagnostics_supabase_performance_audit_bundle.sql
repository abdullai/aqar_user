-- =============================================================================
-- حزمة تشخيص أداء Supabase (فهارس + RLS + حجم بيانات) — قراءة فقط
-- =============================================================================
-- التشغيل: Supabase → SQL Editor (صلاحيات قراءة pg_catalog).
-- المخرجات: صدّر النتائج (CSV أو نسخ الجداول) وأرسلها للمراجعة التالية.
--
-- دليل ترتيب الملفات والخطوات التالية: ../PERFORMANCE_AUDIT.md
-- تشخيص الرئيسية/الضيف: diagnostics_home_feed_data_quality.sql ، diagnostics_guest_public_listings_visibility.sql
-- قالب EXPLAIN: diagnostics_performance_explain_template.sql
-- قوالب فهارس (تعليق فقط): diagnostics_suggested_indexes_TEMPLATE.sql
--
-- لا يُنفَّذ حذف أو CREATE INDEX من هذا الملف تلقائياً؛ الفهارس تُقرر بعد EXPLAIN.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) أحجام الجداول والصفوف التقريبية (أين الضغط)
-- -----------------------------------------------------------------------------
SELECT relname AS table_name,
       pg_total_relation_size(format('%I.%I', nspname, relname)::regclass) AS total_bytes,
       reltuples::bigint AS est_rows
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE nspname = 'public'
  AND relkind = 'r'
ORDER BY total_bytes DESC
LIMIT 40;

-- -----------------------------------------------------------------------------
-- 2) فهارس المستخدم: عدد المسح + الحجم (مرشّحات للمراجعة عند idx_scan منخفض)
-- -----------------------------------------------------------------------------
SELECT s.schemaname,
       s.relname AS table_name,
       s.indexrelname AS index_name,
       s.idx_scan,
       s.idx_tup_read,
       s.idx_tup_fetch,
       pg_relation_size(s.indexrelid) AS index_bytes
FROM pg_stat_user_indexes s
WHERE s.schemaname = 'public'
ORDER BY s.idx_scan ASC, index_bytes DESC
LIMIT 80;

-- -----------------------------------------------------------------------------
-- 3) جداول بمسح تسلسلي متكرر (مؤشر على فهرس ناقص أو إحصاء قديم)
-- -----------------------------------------------------------------------------
SELECT relname AS table_name,
       seq_scan,
       idx_scan,
       n_live_tup::bigint AS est_live_rows
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND seq_scan > 0
ORDER BY seq_scan DESC
LIMIT 40;

-- -----------------------------------------------------------------------------
-- 4) سياسات RLS على جداول ساخنة في تطبيق aqar_user (PostgREST)
-- -----------------------------------------------------------------------------
SELECT tablename,
       policyname,
       cmd,
       roles::text AS roles,
       qual::text AS using_expr,
       with_check::text AS with_check_expr
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'properties',
    'market_property_requests',
    'reservations',
    'listing_requests',
    'listing_request_invites',
    'listing_offers',
    'listing_contracts',
    'listing_permits',
    'users_profiles',
    'account_profiles',
    'in_app_notifications',
    'user_devices'
  )
ORDER BY tablename,
         cmd,
         policyname;

-- -----------------------------------------------------------------------------
-- 5) هل RLS مفعّل على الجداول الحرجة؟
-- -----------------------------------------------------------------------------
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN (
    'properties',
    'market_property_requests',
    'reservations',
    'listing_requests',
    'listing_request_invites',
    'listing_offers',
    'listing_contracts',
    'listing_permits',
    'users_profiles'
  )
ORDER BY c.relname;

-- -----------------------------------------------------------------------------
-- 6) اختياري: pg_stat_statements (شغّل يدوياً فقط إن كانت الإضافة مفعّلة)
-- -----------------------------------------------------------------------------
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements; -- يحتاج صلاحيات؛ غالباً مفعّل في Supabase
-- SELECT calls,
--        round(total_exec_time::numeric, 2) AS total_ms,
--        round(mean_exec_time::numeric, 2) AS mean_ms,
--        rows,
--        left(query, 200) AS query_prefix
-- FROM pg_stat_statements
-- WHERE query NOT ILIKE '%pg_stat_statements%'
-- ORDER BY total_exec_time DESC
-- LIMIT 25;

-- =============================================================================
-- قالب EXPLAIN (المرحلة 4 من الخطة): لصق الاستعلام الفعلي بدل التعليق
-- =============================================================================
-- مثال الاستخدام بعد نسخ SQL من سجلات PostgREST أو من وضع debug:
--
-- EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
-- SELECT ... ;
--
