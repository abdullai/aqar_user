-- توسيع حالات الطلبات الظاهرة في الرئيسية (يتوافق مع inFilter في user_dashboard.loaders.dart).
-- نفّذ في Supabase SQL Editor بعد التأكد من القيم الفعلية في عمود status.

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
