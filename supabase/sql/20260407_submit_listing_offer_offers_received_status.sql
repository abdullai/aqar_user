-- =============================================================================
-- After a marketer submits an offer: set listing_requests.status = offers_received
-- so merged marketer/owner hub rows move to Negotiation / Contracting tabs instantly.
-- Optional: configure Supabase Database Webhook on public.in_app_notifications INSERT
-- → POST to Edge Function send_push (see handle in send_push/index.ts) for FCM.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.submit_listing_offer(
  p_request_id uuid,
  p_offer_amount numeric,
  p_notes text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_round int;
  v_owner uuid;
  dup int;
  v_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id = uid THEN
    RAISE EXCEPTION 'owner_cannot_offer';
  END IF;

  IF coalesce(req.workflow_stage, '') IN (
    'marketer_selected', 'contract_pending', 'contract_sent', 'contract_returned',
    'contract_signed', 'contract_cancelled', 'cancelled', 'terminated',
    'permit_pending', 'permit_issued', 'published', 'reserved'
  ) THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_owner := req.owner_id;
  v_round := coalesce(req.marketing_round, 1);

  SELECT COUNT(*) INTO dup
  FROM public.listing_offers o
  WHERE o.request_id = p_request_id
    AND o.marketer_id = uid
    AND coalesce(o.round_no, 1) = v_round
    AND o.status IN ('submitted', 'pending');

  IF dup > 0 THEN
    RAISE EXCEPTION 'duplicate_offer_same_round';
  END IF;

  INSERT INTO public.listing_offers (
    request_id,
    marketer_id,
    price,
    notes,
    status,
    round_no,
    offer_amount,
    created_at,
    expires_at
  ) VALUES (
    p_request_id,
    uid,
    p_offer_amount,
    coalesce(p_notes, ''),
    'submitted',
    v_round,
    p_offer_amount,
    now(),
    now() + interval '72 hours'
  )
  RETURNING id INTO v_id;

  UPDATE public.listing_requests lr
  SET
    status = 'offers_received',
    updated_at = now()
  WHERE lr.id = p_request_id;

  PERFORM public.workflow_create_notification(
    v_owner,
    'offer_received',
    'وصلك عرض تسويق جديد',
    'راجع العروض في صفحتي واختر الأنسب.',
    'listing_request',
    p_request_id,
    jsonb_build_object('request_id', p_request_id, 'offer_id', v_id)
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_listing_offer(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_listing_offer(uuid, numeric, text) TO authenticated;

COMMIT;
