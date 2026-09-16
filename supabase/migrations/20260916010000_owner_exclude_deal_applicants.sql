-- Owner exclusion workflow for incoming deal applicants.
-- Run this migration in Supabase SQL Editor before using the new exclusion buttons.

BEGIN;

ALTER TABLE public.market_request_offers
  ADD COLUMN IF NOT EXISTS owner_rejection_reason text,
  ADD COLUMN IF NOT EXISTS owner_rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS owner_rejected_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS owner_rejection_reason text,
  ADD COLUMN IF NOT EXISTS owner_rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS owner_rejected_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.respond_market_request_offer(
  p_offer_id uuid,
  p_action text,
  p_reason text DEFAULT NULL
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
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT o.* INTO v_offer
  FROM public.market_request_offers o
  JOIN public.market_property_requests r ON r.id = o.market_request_id
  WHERE o.id = p_offer_id AND r.requester_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'offer_not_found_or_not_owner'; END IF;

  IF v_action IN ('accept', 'accepted', 'approve', 'approved') THEN
    IF EXISTS (
      SELECT 1 FROM public.market_request_offers o2
      WHERE o2.market_request_id = v_offer.market_request_id
        AND o2.id <> p_offer_id
        AND lower(trim(coalesce(o2.status, ''))) IN ('accepted', 'approved', 'selected')
    ) THEN RAISE EXCEPTION 'another_offer_already_selected'; END IF;

    UPDATE public.market_request_offers
    SET status = 'accepted', owner_rejection_reason = NULL,
        owner_rejected_at = NULL, owner_rejected_by = NULL, updated_at = now()
    WHERE id = p_offer_id;

    UPDATE public.market_property_requests
    SET selected_offer_id = p_offer_id, updated_at = now()
    WHERE id = v_offer.market_request_id AND requester_id = v_uid;
  ELSIF v_action IN ('reject', 'rejected', 'decline', 'declined', 'exclude', 'excluded') THEN
    IF v_reason IS NULL THEN RAISE EXCEPTION 'rejection_reason_required'; END IF;
    UPDATE public.market_request_offers
    SET status = 'rejected', owner_rejection_reason = v_reason,
        owner_rejected_at = now(), owner_rejected_by = v_uid, updated_at = now()
    WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_market_request_offer(
  p_offer_id uuid,
  p_action text
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.respond_market_request_offer(p_offer_id, p_action, NULL);
$$;

CREATE OR REPLACE FUNCTION public.reject_property_reservation(
  p_reservation_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF v_reason IS NULL THEN RAISE EXCEPTION 'rejection_reason_required'; END IF;

  UPDATE public.reservations r
  SET status = 'cancelled', owner_rejection_reason = v_reason,
      owner_rejected_at = now(), owner_rejected_by = v_uid
  FROM public.properties p
  WHERE r.id = p_reservation_id
    AND r.property_id = p.id
    AND p.owner_id = v_uid
    AND lower(trim(coalesce(r.status, ''))) IN ('pending', 'paid');

  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found_or_not_owner'; END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_property_reservation(uuid, text) TO authenticated;

COMMIT;
