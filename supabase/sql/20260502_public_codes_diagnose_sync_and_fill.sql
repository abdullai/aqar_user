-- =============================================================================
-- 1) تشخيص: من لديه رقم مرجع منصّة (10 أرقام) ناقص أو غير صالح؟
--    هذا الرقم ≠ «رقم إعلان الهيئة» (REGA) المخزَّن في marketing_license_snapshot
--    أو rega_payload تحت rega_ad_license_number بعد استخراج الترخيص.
--
-- 2) مزامنة: نسخ رقم الطلب إلى العقار عندما request_id مربوط والعقار بلا رقم صالح.
--
-- 3) ملء: استدعاء allocate_public_listing_code_10d() لكل ما بقي ناقصاً
--    (يتطلب تطبيق migration 20260501120000_public_listing_code_global_allocator.sql)
--
-- شغّل أولاً الأقسام التي تنتهي بـ SELECT فقط؛ راجع النتائج ثم نفّذ BEGIN…COMMIT للتحديث.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- أ) ملخص أعداد (للقراءة فقط)
-- ---------------------------------------------------------------------------
SELECT 'properties_missing_or_bad_code' AS check_key,
       count(*)::int AS cnt
FROM public.properties
WHERE listing_public_code IS NULL
   OR length(trim(listing_public_code)) = 0
   OR listing_public_code !~ '^[0-9]{10}$';

SELECT 'listing_requests_missing_or_bad_code' AS check_key,
       count(*)::int AS cnt
FROM public.listing_requests
WHERE listing_request_public_code IS NULL
   OR length(trim(listing_request_public_code)) = 0
   OR listing_request_public_code !~ '^[0-9]{10}$';

SELECT 'market_property_requests_missing_or_bad_code' AS check_key,
       count(*)::int AS cnt
FROM public.market_property_requests
WHERE request_public_code IS NULL
   OR length(trim(request_public_code)) = 0
   OR request_public_code !~ '^[0-9]{10}$';

-- ---------------------------------------------------------------------------
-- ب) تفاصيل عقارات بلا رقم مرجع صالح (مع request_id إن وُجد)
-- ---------------------------------------------------------------------------
SELECT p.id,
       p.title,
       p.status,
       p.workflow_stage,
       p.request_id,
       p.listing_public_code AS current_listing_public_code,
       lr.listing_request_public_code AS from_linked_request
FROM public.properties p
LEFT JOIN public.listing_requests lr ON lr.id = p.request_id
WHERE p.listing_public_code IS NULL
   OR length(trim(p.listing_public_code)) = 0
   OR p.listing_public_code !~ '^[0-9]{10}$'
ORDER BY p.created_at DESC
LIMIT 500;

-- ---------------------------------------------------------------------------
-- ج) تفاصيل طلبات التسويق بلا رقم
-- ---------------------------------------------------------------------------
SELECT id,
       title,
       status,
       workflow_stage,
       listing_request_public_code
FROM public.listing_requests
WHERE listing_request_public_code IS NULL
   OR length(trim(listing_request_public_code)) = 0
   OR listing_request_public_code !~ '^[0-9]{10}$'
ORDER BY created_at DESC
LIMIT 500;

-- ---------------------------------------------------------------------------
-- د) تفاصيل طلبات السوق بلا رقم
-- ---------------------------------------------------------------------------
SELECT id,
       title,
       status,
       request_public_code
FROM public.market_property_requests
WHERE request_public_code IS NULL
   OR length(trim(request_public_code)) = 0
   OR request_public_code !~ '^[0-9]{10}$'
ORDER BY created_at DESC
LIMIT 500;

-- ---------------------------------------------------------------------------
-- هـ) تشخيص اختياري: عقار منشور (أو قريب) بلا رقم إعلان هيئة في اللقطة
--     (يعتمد على عمود marketing_license_snapshot من نوع jsonb؛ عدّل إن كان الاسم مختلفاً)
-- ---------------------------------------------------------------------------
-- SELECT p.id,
--        p.title,
--        p.status,
--        p.workflow_stage,
--        p.marketing_license_snapshot ->> 'rega_ad_license_number' AS rega_from_snapshot
-- FROM public.properties p
-- WHERE coalesce(lower(p.status), '') IN ('published', 'live', 'active', 'listed')
--   AND (
--     p.marketing_license_snapshot IS NULL
--     OR trim(coalesce(p.marketing_license_snapshot ->> 'rega_ad_license_number', '')) = ''
--   )
-- LIMIT 200;

-- ---------------------------------------------------------------------------
-- و) تعارض: نفس الرقم المرجعي في أكثر من جدول نشط (نادر)
-- ---------------------------------------------------------------------------
-- WITH u AS (
--   SELECT trim(listing_public_code) AS c, 'properties'::text AS t, id::text AS rid
--   FROM public.properties
--   WHERE listing_public_code ~ '^[0-9]{10}$'
--   UNION ALL
--   SELECT trim(listing_request_public_code), 'listing_requests', id::text
--   FROM public.listing_requests
--   WHERE listing_request_public_code ~ '^[0-9]{10}$'
--   UNION ALL
--   SELECT trim(request_public_code), 'market_property_requests', id::text
--   FROM public.market_property_requests
--   WHERE request_public_code ~ '^[0-9]{10}$'
-- )
-- SELECT c, count(*) AS cnt, array_agg(t || ':' || rid) AS refs
-- FROM u
-- GROUP BY c
-- HAVING count(*) > 1;

-- =============================================================================
-- ز) تطبيق: مزامنة + ملء — معلّق افتراضياً. بعد مراجعة أقسام أ–د، أزل /* */ حول
--    هذا القسم فقط ثم نفّذ، أو انسخه إلى نافذة منفصلة.
--    بديل: supabase/sql/20260501_backfill_public_listing_codes_existing_rows.sql
--    بعد تشغيل مزامنة UPDATE أعلاه يدوياً إن احتجت.
-- =============================================================================
/*
BEGIN;

UPDATE public.properties p
SET listing_public_code = lr.listing_request_public_code
FROM public.listing_requests lr
WHERE p.request_id = lr.id
  AND lr.listing_request_public_code IS NOT NULL
  AND length(trim(lr.listing_request_public_code)) = 10
  AND lr.listing_request_public_code ~ '^[0-9]{10}$'
  AND (
    p.listing_public_code IS NULL
    OR length(trim(p.listing_public_code)) = 0
    OR p.listing_public_code !~ '^[0-9]{10}$'
  );

DO $$
DECLARE
  r record;
  v text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.properties
    WHERE listing_public_code IS NULL
       OR length(trim(listing_public_code)) = 0
       OR listing_public_code !~ '^[0-9]{10}$'
  LOOP
    v := public.allocate_public_listing_code_10d();
    UPDATE public.properties SET listing_public_code = v WHERE id = r.id;
  END LOOP;
END $$;

DO $$
DECLARE
  r record;
  v text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.listing_requests
    WHERE listing_request_public_code IS NULL
       OR length(trim(listing_request_public_code)) = 0
       OR listing_request_public_code !~ '^[0-9]{10}$'
  LOOP
    v := public.allocate_public_listing_code_10d();
    UPDATE public.listing_requests SET listing_request_public_code = v WHERE id = r.id;
  END LOOP;
END $$;

DO $$
DECLARE
  r record;
  v text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.market_property_requests
    WHERE request_public_code IS NULL
       OR length(trim(request_public_code)) = 0
       OR request_public_code !~ '^[0-9]{10}$'
  LOOP
    v := public.allocate_public_listing_code_10d();
    UPDATE public.market_property_requests SET request_public_code = v WHERE id = r.id;
  END LOOP;
END $$;

COMMIT;
*/
