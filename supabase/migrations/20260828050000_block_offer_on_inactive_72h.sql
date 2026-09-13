-- منع إرسال عرض تسويقي عندما يكون الطلب في «بدون إجراء 72 ساعة».
-- المسوّق لا ينشر الإعلان من هذه المرحلة؛ النشر فقط بعد العقد/التصريح.

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
  v_existing_id uuid;
  v_existing_status text;
  v_existing_round int;
  v_id uuid;
  v_stage text;
  v_status text;
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

  IF coalesce(req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  v_stage := lower(trim(coalesce(req.workflow_stage, '')));
  v_status := lower(trim(coalesce(req.status::text, '')));

  IF v_stage IN (
    'marketer_selected', 'contract_pending', 'contract_sent', 'contract_returned',
    'contract_signed', 'contract_cancelled', 'cancelled', 'terminated',
    'permit_pending', 'permit_issued', 'published', 'reserved', 'archived',
    'inactive_72h', 'inactive72h', 'owner_action_required'
  ) OR v_status IN (
    'inactive_72h', 'inactive72h', 'owner_action_required'
  ) THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_owner := req.owner_id;
  v_round := coalesce(req.marketing_round, 1);

  SELECT o.id,
         lower(trim(coalesce(o.status::text, ''))),
         coalesce(o.round_no, 1)
    INTO v_existing_id, v_existing_status, v_existing_round
  FROM public.listing_offers o
  WHERE o.request_id = p_request_id
    AND o.marketer_id = uid
  ORDER BY o.created_at DESC NULLS LAST, o.id DESC
  LIMIT 1
  FOR UPDATE;

  IF v_existing_id IS NOT NULL THEN
    IF v_existing_status IN ('submitted', 'pending')
       AND v_existing_round = v_round THEN
      RAISE EXCEPTION 'duplicate_offer_same_round';
    END IF;

    UPDATE public.listing_offers
       SET status = 'submitted',
           round_no = v_round,
           price = p_offer_amount,
           offer_amount = p_offer_amount,
           notes = coalesce(p_notes, ''),
           expires_at = now() + interval '72 hours',
           last_call_at = NULL,
           last_call_count = 0,
           lost_at = NULL,
           updated_at = now()
     WHERE id = v_existing_id
     RETURNING id INTO v_id;
  ELSE
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
  END IF;

  UPDATE public.listing_requests lr
  SET
    status = 'offers_received',
    updated_at = now()
  WHERE lr.id = p_request_id
    AND lower(trim(coalesce(lr.workflow_stage, ''))) IN (
      'waiting_marketers', 'added_by_owner', ''
    );

  PERFORM public.workflow_create_notification(
    v_owner,
    'offer_received',
    'وصلك عرض تسويق جديد',
    'راجع العروض في صفحتي واختر الأنسب.',
    'listing_request',
    p_request_id,
    jsonb_build_object(
      'request_id', p_request_id,
      'offer_id', v_id,
      'deep_route', 'owner_offers',
      'main_tab', 'my_ads',
      'role', 'owner'
    )
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_listing_offer(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_listing_offer(uuid, numeric, text) TO authenticated;

COMMIT;
