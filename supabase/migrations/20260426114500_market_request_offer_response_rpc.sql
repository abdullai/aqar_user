ALTER TABLE IF EXISTS public.market_request_offers
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

CREATE OR REPLACE FUNCTION public.respond_market_request_offer(
  p_offer_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer public.market_request_offers%ROWTYPE;
  v_action text := lower(trim(coalesce(p_action, '')));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT o.* INTO v_offer
  FROM public.market_request_offers o
  JOIN public.market_property_requests r ON r.id = o.market_request_id
  WHERE o.id = p_offer_id
    AND r.requester_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  IF v_action IN ('accept', 'accepted', 'approve', 'approved') THEN
    UPDATE public.market_request_offers
    SET status = 'accepted', updated_at = now()
    WHERE id = p_offer_id;

    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE market_request_id = v_offer.market_request_id
      AND id <> p_offer_id
      AND coalesce(status, '') IN ('submitted', 'pending');

    UPDATE public.market_property_requests
    SET status = 'completed', updated_at = now()
    WHERE id = v_offer.market_request_id
      AND requester_id = v_uid;
  ELSIF v_action IN ('reject', 'rejected', 'decline', 'declined') THEN
    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text) TO authenticated;
