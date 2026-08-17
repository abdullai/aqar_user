-- =============================================================================
-- RPC: create_listing_contract_from_offer
-- Creates listing_contracts with status = draft (contract_status enum).
-- Keeps listing_requests.workflow_stage = marketer_selected until send RPC.
-- Idempotent when a row already exists for this offer_id.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.create_listing_contract_from_offer(p_offer_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  off record;
  req record;
  v_existing uuid;
  v_legacy uuid;
  v_new uuid;
  v_round int;
  v_st text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO off FROM public.listing_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = off.request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF req.selected_offer_id IS DISTINCT FROM p_offer_id THEN
    RAISE EXCEPTION 'offer_not_selected';
  END IF;

  IF coalesce(off.status::text, '') NOT IN ('owner_accepted', 'selected') THEN
    RAISE EXCEPTION 'offer_not_accepted';
  END IF;

  -- Idempotent: contract already tied to this offer
  SELECT c.id INTO v_existing
  FROM public.listing_contracts c
  WHERE c.offer_id IS NOT DISTINCT FROM p_offer_id
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    SELECT c.status::text INTO v_st FROM public.listing_contracts c WHERE c.id = v_existing;

    UPDATE public.listing_requests lr
    SET
      contract_id = v_existing,
      workflow_stage = CASE v_st
        WHEN 'draft' THEN 'marketer_selected'
        WHEN 'pending_owner' THEN 'contract_sent'
        WHEN 'pending_marketer' THEN 'contract_returned'
        WHEN 'signed' THEN 'contract_signed'
        WHEN 'cancelled' THEN 'cancelled'
        ELSE lr.workflow_stage
      END,
      updated_at = now()
    WHERE lr.id = req.id;

    RETURN v_existing;
  END IF;

  -- Existing contract on request (legacy row without offer_id): link if same marketer
  IF req.contract_id IS NOT NULL THEN
    SELECT c.id INTO v_legacy
    FROM public.listing_contracts c
    WHERE c.id = req.contract_id
      AND c.request_id = req.id
      AND c.marketer_id = off.marketer_id
      AND (c.offer_id IS NULL OR c.offer_id = p_offer_id)
    LIMIT 1;

    IF v_legacy IS NOT NULL THEN
      UPDATE public.listing_contracts
      SET
        offer_id = p_offer_id,
        updated_at = now()
      WHERE id = v_legacy
        AND (offer_id IS NULL OR offer_id IS DISTINCT FROM p_offer_id);

      SELECT c.status::text INTO v_st FROM public.listing_contracts c WHERE c.id = v_legacy;

      UPDATE public.listing_requests lr
      SET
        workflow_stage = CASE v_st
          WHEN 'draft' THEN 'marketer_selected'
          WHEN 'pending_owner' THEN 'contract_sent'
          WHEN 'pending_marketer' THEN 'contract_returned'
          WHEN 'signed' THEN 'contract_signed'
          WHEN 'cancelled' THEN 'cancelled'
          ELSE lr.workflow_stage
        END,
        updated_at = now()
      WHERE lr.id = req.id;

      RETURN v_legacy;
    END IF;

    RAISE EXCEPTION 'contract_already_linked';
  END IF;

  IF coalesce(req.workflow_stage, '') IS DISTINCT FROM 'marketer_selected' THEN
    RAISE EXCEPTION 'invalid_stage_for_contract';
  END IF;

  v_round := coalesce(off.round_no, 1);

  INSERT INTO public.listing_contracts (
    request_id,
    owner_id,
    marketer_id,
    offer_id,
    round_no,
    status,
    created_at,
    updated_at
  )
  VALUES (
    off.request_id,
    req.owner_id,
    off.marketer_id,
    off.id,
    v_round,
    'draft'::contract_status,
    now(),
    now()
  )
  RETURNING id INTO v_new;

  UPDATE public.listing_requests lr
  SET
    contract_id = v_new,
    workflow_stage = 'marketer_selected',
    updated_at = now()
  WHERE lr.id = req.id;

  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.create_listing_contract_from_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_listing_contract_from_offer(uuid) TO authenticated;

COMMIT;
