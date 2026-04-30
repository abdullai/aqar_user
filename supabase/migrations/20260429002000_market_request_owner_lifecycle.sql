BEGIN;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS edit_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_edits integer NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS deletion_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS deletion_requested_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS selected_offer_id uuid REFERENCES public.market_request_offers (id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.update_market_property_request_limited(
  p_request_id uuid,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_budget_min numeric DEFAULT NULL,
  p_budget_max numeric DEFAULT NULL,
  p_area_min_m2 numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.market_property_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_req
  FROM public.market_property_requests
  WHERE id = p_request_id
    AND requester_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;

  IF coalesce(v_req.status, '') IN ('completed', 'closed', 'sold', 'delete_requested', 'relisted') THEN
    RAISE EXCEPTION 'request_not_editable';
  END IF;

  IF coalesce(v_req.edit_count, 0) >= coalesce(v_req.max_edits, 3) THEN
    RAISE EXCEPTION 'edit_limit_reached';
  END IF;

  UPDATE public.market_property_requests
  SET
    title = coalesce(nullif(trim(p_title), ''), title),
    description = p_description,
    budget_min = p_budget_min,
    budget_max = p_budget_max,
    area_min_m2 = p_area_min_m2,
    edit_count = coalesce(edit_count, 0) + 1,
    updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'ok', true,
    'edit_count', coalesce(v_req.edit_count, 0) + 1,
    'remaining', greatest(coalesce(v_req.max_edits, 3) - (coalesce(v_req.edit_count, 0) + 1), 0)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.request_delete_market_property_request(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_updated uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE public.market_property_requests
  SET
    status = 'delete_requested',
    deletion_requested_at = now(),
    deletion_requested_by = v_uid,
    updated_at = now()
  WHERE id = p_request_id
    AND requester_id = v_uid
    AND coalesce(status, '') NOT IN ('completed', 'closed', 'sold', 'relisted')
  RETURNING id INTO v_updated;

  IF v_updated IS NULL THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'delete_requested');
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_market_property_request(
  p_request_id uuid,
  p_offer_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_offer_id IS NOT NULL THEN
    SELECT o.id INTO v_offer_id
    FROM public.market_request_offers o
    JOIN public.market_property_requests r ON r.id = o.market_request_id
    WHERE o.id = p_offer_id
      AND o.market_request_id = p_request_id
      AND r.requester_id = v_uid
    LIMIT 1;

    IF v_offer_id IS NULL THEN
      RAISE EXCEPTION 'offer_not_found_for_request';
    END IF;

    UPDATE public.market_request_offers
    SET status = 'accepted', updated_at = now()
    WHERE id = v_offer_id;

    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE market_request_id = p_request_id
      AND id <> v_offer_id
      AND coalesce(status, '') IN ('submitted', 'pending');
  END IF;

  UPDATE public.market_property_requests
  SET
    status = 'completed',
    selected_offer_id = coalesce(v_offer_id, selected_offer_id),
    completed_at = now(),
    completed_by = v_uid,
    updated_at = now()
  WHERE id = p_request_id
    AND requester_id = v_uid
  RETURNING selected_offer_id INTO v_offer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'completed', 'selected_offer_id', v_offer_id);
END;
$$;

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
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT o.* INTO v_offer
  FROM public.market_request_offers o
  JOIN public.market_property_requests r ON r.id = o.market_request_id
  WHERE o.id = p_offer_id
    AND r.requester_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found_or_not_owner';
  END IF;

  IF v_action IN ('accept', 'accepted', 'approve', 'approved') THEN
    PERFORM public.complete_market_property_request(v_offer.market_request_id, p_offer_id);
  ELSIF v_action IN ('reject', 'rejected', 'decline', 'declined') THEN
    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_market_property_request_limited(uuid, text, text, numeric, numeric, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_delete_market_property_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_market_property_request(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.respond_market_request_offer(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.update_market_property_request_limited(uuid, text, text, numeric, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_delete_market_property_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_market_property_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text) TO authenticated;

COMMIT;
