-- =============================================================================
-- ملء أرقام العرض العامة للصفوف القديمة (NULL / غير صالح / ليس 10 أرقام)
-- بعد تطبيق migrations:
--   20260429000500_market_request_public_code.sql (أو ما يعادله)
--   20260501090000_listing_requests_public_code.sql
--   20260501120000_public_listing_code_global_allocator.sql
--
-- يعتمد على: public.allocate_public_listing_code_10d()
--
-- لا يعيد توليد أرقام صالحة موجودة مسبقاً (يُبقيها كما هي).
-- إن ظهر تعارض بين جدولين لنفس الرقم (بيانات قديمة نادرة)، استخدم الاستعلام
-- التشخيصي في الأسفل ثم عالج يدوياً أو كرر تخصيصاً للصف الثاني فقط.
-- =============================================================================

BEGIN;

-- عقارات
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
    UPDATE public.properties
    SET listing_public_code = v
    WHERE id = r.id;
  END LOOP;
END $$;

-- طلبات التسويق listing_requests
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
    UPDATE public.listing_requests
    SET listing_request_public_code = v
    WHERE id = r.id;
  END LOOP;
END $$;

-- طلبات السوق market_property_requests
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
    UPDATE public.market_property_requests
    SET request_public_code = v
    WHERE id = r.id;
  END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- تشخيص: نفس الرقم يظهر في أكثر من جدول (بعد التشغيل أعلاه نادر جداً)
-- =============================================================================
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
