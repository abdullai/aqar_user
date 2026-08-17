-- مواءمة RLS مع استعلام الرئيسية في التطبيق:
--   .inFilter('status', ['published', 'active', 'live'])
-- السياسة السابقة سمحت فقط بـ status = 'published' فقط.
-- نفّذ في Supabase → SQL Editor بعد مراجعة حالات status لديك.

DROP POLICY IF EXISTS market_property_requests_public_select_published
  ON public.market_property_requests;

CREATE POLICY market_property_requests_public_select_published
  ON public.market_property_requests
  FOR SELECT
  TO anon, authenticated
  USING (status IN ('published', 'active', 'live'));

COMMENT ON POLICY market_property_requests_public_select_published
  ON public.market_property_requests IS
  'قراءة عامة للطلبات الظاهرة في الرئيسية (ضيف + مسجّل) — نفس فلتر التطبيق.';
