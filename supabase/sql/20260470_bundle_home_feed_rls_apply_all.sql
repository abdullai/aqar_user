-- =============================================================================
-- حزمة واحدة: سياسات الرئيسية (إعلانات + طلبات السوق) لـ anon / authenticated
-- =============================================================================
--
-- لا يمكن تشغيل هذا الملف تلقائياً من المستودع على مشروعك — انسخه إلى:
--   Supabase Dashboard → SQL Editor → New query → Run
--
-- ماذا يحقق؟
--   • قراءة عامة لـ public.properties للرئيسية (منشور + مسودات المسار الحيّ)،
--     مع احترام home_feed_suppressed واستبعاد deleted — يطابق
--     lib/shared/core/supabase_schema_selects.dart (propertiesHomeFeedOrFilter).
--   • قراءة عامة لـ public.market_property_requests بحالات الرئيسية — يطابق
--     marketPropertyRequestsHomeStatuses في التطبيق.
--   • إزالة سياسة SELECT قديمة ضيّقة على properties إن وُجدت (سبب شائع لصف 0 من API).
--
-- قبل التنفيذ (اختياري لكن مُستحسن):
--   • تأكد أن عمود home_feed_suppressed موجود على properties (مثلاً migration
--     listing_report إن استخدمتموها)؛ وإلا أنشئه أو عدّل USING أدناه.
--   • لقيد status على market_property_requests بالحالات الموسّعة، نفّذ إن لزم:
--     supabase/sql/20260460_market_property_requests_status_check_align_rls.sql
--
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) صلاحيات القراءة لـ PostgREST (anon / authenticated)
-- -----------------------------------------------------------------------------
GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.market_property_requests TO anon, authenticated;

ALTER TABLE IF EXISTS public.properties ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.market_property_requests ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 2) إزالة سياسة قديمة ضيّقة على العقارات (تتعارض مع مسودات المسار على الرئيسية)
--    انظر: 20260462_properties_drop_redundant_public_read_policy.sql
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "properties_public_read_published_like" ON public.properties;

-- -----------------------------------------------------------------------------
-- 3) سياسة الرئيسية للعقارات — النسخة الموسّعة (مطابقة 20260463 + التطبيق)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;

CREATE POLICY "properties_public_home_select"
ON public.properties
FOR SELECT
TO anon, authenticated
USING (
  status IS DISTINCT FROM 'deleted'
  AND COALESCE(home_feed_suppressed, false) = false
  AND (
    status IN (
      'published', 'active', 'available', 'live', 'reserved', 'approved',
      'listed', 'open', 'visible', 'for_sale', 'for_rent',
      'forsale', 'forrent',
      'pending', 'under_review', 'in_review', 'review', 'processing', 'ready', 'verified'
    )
    OR (
      status = 'draft'
      AND workflow_stage IN (
        'waiting_marketers',
        'marketer_selected',
        'contract_pending',
        'contract_sent',
        'contract_returned',
        'contract_signed',
        'permit_pending',
        'permit_issued',
        'published',
        'reserved',
        'inactive_72h'
      )
    )
  )
);

COMMENT ON POLICY "properties_public_home_select" ON public.properties IS
  'قراءة الرئيسية — موسّع (legacy statuses + draft pipeline). يطابق aqar_user supabase_schema_selects.';

-- -----------------------------------------------------------------------------
-- 4) سياسة الرئيسية لطلبات السوق — مطابقة 20260459 + inFilter في loaders
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS market_property_requests_public_select_published
  ON public.market_property_requests;

CREATE POLICY market_property_requests_public_select_published
  ON public.market_property_requests
  FOR SELECT
  TO anon, authenticated
  USING (status IN (
    'published', 'active', 'live', 'open', 'visible',
    'under_review', 'in_progress', 'seeking', 'bidding',
    'negotiating', 'collecting_offers'
  ));

COMMENT ON POLICY market_property_requests_public_select_published
  ON public.market_property_requests IS
  'قراءة عامة للطلبات في الرئيسية — نفس فلتر التطبيق (marketPropertyRequestsHomeStatuses).';

-- =============================================================================
-- تحقق سريع (اختياري — علّق إن رغبت): أعد تشغيل PostgREST أو انتظر تحديث schema cache
-- =============================================================================
-- SELECT count(*) FROM public.properties
--   WHERE status IS DISTINCT FROM 'deleted'
--   AND COALESCE(home_feed_suppressed, false) = false;
--
-- (كـ service role أو بعد سياساتك الأخرى للمالك — للمقارنة فقط)
