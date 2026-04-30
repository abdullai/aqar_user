-- =============================================================================
-- Alias RPC: marketer_submit_offer → submit_listing_offer
-- يزيل 404 عندما يستدعي العميل marketer_submit_offer بعد فشل المسار الأول.
-- يتطلب وجود public.submit_listing_offer(uuid, numeric, text) مسبقاً.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.marketer_submit_offer(
  p_request_id uuid,
  p_price numeric,
  p_notes text DEFAULT NULL
) RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.submit_listing_offer(
    p_request_id,
    p_price,
    coalesce(nullif(trim(p_notes), ''), '')
  );
$$;

REVOKE ALL ON FUNCTION public.marketer_submit_offer(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_submit_offer(uuid, numeric, text) TO authenticated;

COMMIT;
