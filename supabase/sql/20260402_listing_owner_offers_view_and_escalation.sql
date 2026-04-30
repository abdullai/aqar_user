-- =============================================================================
-- تتبع مشاهدة المالك لصفحة العروض + طلب تصعيد/إيقاف تسويق للمراجعة الإدارية
-- =============================================================================

BEGIN;

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS owner_viewed_offers_at timestamptz;

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS marketing_cancel_request_at timestamptz;

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS marketing_cancel_request_reason text;

-- أول مرة يفتح فيها المالك شاشة العروض (لا يُعاد ضبط التاريخ)
CREATE OR REPLACE FUNCTION public.record_owner_viewed_listing_offers(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  rid uuid := p_request_id;
  n int;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE public.listing_requests lr
  SET
    owner_viewed_offers_at = coalesce(lr.owner_viewed_offers_at, now()),
    updated_at = now()
  WHERE lr.id = rid
    AND lr.owner_id = uid;

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.record_owner_viewed_listing_offers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_owner_viewed_listing_offers(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.owner_request_marketing_admin_escalation(
  p_request_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  rid uuid := p_request_id;
  n int;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE public.listing_requests lr
  SET
    marketing_cancel_request_at = now(),
    marketing_cancel_request_reason = coalesce(v_reason, lr.marketing_cancel_request_reason),
    updated_at = now()
  WHERE lr.id = rid
    AND lr.owner_id = uid;

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.owner_request_marketing_admin_escalation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_request_marketing_admin_escalation(uuid, text) TO authenticated;

COMMIT;
