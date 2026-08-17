-- =============================================================================
-- تراجع: إزالة سياسة المسوّق على listing_requests + الدالة المساعدة.
-- نفّذ إذا ظهرت أخطاء تحميل بعد تطبيق النسخة السابقة.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "marketer_select_linked_listing_requests"
  ON public.listing_requests;

DROP FUNCTION IF EXISTS public.marketer_can_read_listing_request(uuid);

COMMIT;
