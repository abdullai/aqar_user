-- =============================================================================
-- RLS: المسوّق يقرأ صفوف listing_requests المرتبطة بدعوة أو عرض له.
--
-- النسخة السابقة (EXISTS مباشرة داخل USING) قد تسبب خطأ 500 أو «تعذر التحميل»
-- عند وجود سياسات أخرى تربط الجدولين ببعض (حلقة تقييم RLS).
--
-- الحل: دالة SECURITY DEFINER مع SET row_security = off داخلها فقط،
-- تتحقق من الدعوات/العروض دون إعادة دخول سياسة listing_requests على نفسها.
--
-- نفّذ في Supabase → SQL Editor. للتراجع استخدم:
--   supabase/sql/20260429_marketer_select_listing_requests_linked_ROLLBACK.sql
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "marketer_select_linked_listing_requests"
  ON public.listing_requests;

DROP FUNCTION IF EXISTS public.marketer_can_read_listing_request(uuid);

CREATE OR REPLACE FUNCTION public.marketer_can_read_listing_request(req_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.listing_request_invites inv
    WHERE inv.request_id = req_id
      AND inv.marketer_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.listing_offers o
    WHERE o.request_id = req_id
      AND o.marketer_id = auth.uid()
  );
$$;

COMMENT ON FUNCTION public.marketer_can_read_listing_request(uuid) IS
  'RLS helper: مسوّق له دعوة أو عرض على هذا الطلب (بدون حلقة سياسات).';

REVOKE ALL ON FUNCTION public.marketer_can_read_listing_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_listing_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_listing_request(uuid) TO service_role;

CREATE POLICY "marketer_select_linked_listing_requests"
  ON public.listing_requests
  FOR SELECT
  TO authenticated
  USING (public.marketer_can_read_listing_request(id));

COMMIT;
