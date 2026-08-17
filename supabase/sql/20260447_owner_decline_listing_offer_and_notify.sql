-- =============================================================================
-- رفض عرض من المالك عبر RPC (SECURITY DEFINER) + سبب اختياري + إشعار للمسوّق
-- عمود owner_decline_reason للعرض في التطبيق.
-- =============================================================================

BEGIN;

ALTER TABLE public.listing_offers
  ADD COLUMN IF NOT EXISTS owner_decline_reason text;

CREATE OR REPLACE FUNCTION public.owner_decline_listing_offer(
  p_offer_id uuid,
  p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  off record;
  req record;
  v_reason text;
  body_ar text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO off FROM public.listing_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = off.request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF coalesce(off.status, '') NOT IN ('submitted', 'pending', '') THEN
    RAISE EXCEPTION 'offer_not_pending';
  END IF;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');

  UPDATE public.listing_offers
  SET
    status = 'declined',
    owner_decline_reason = v_reason,
    updated_at = now()
  WHERE id = p_offer_id;

  IF v_reason IS NULL THEN
    body_ar := 'رفض المالك عرضك. يمكنك متابعة طلبات أخرى.';
  ELSE
    body_ar := 'رفض المالك عرضك. السبب: ' || v_reason;
  END IF;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_declined',
    'تم رفض عرضك',
    body_ar,
    'listing_request',
    off.request_id,
    jsonb_build_object(
      'request_id', off.request_id,
      'offer_id', p_offer_id,
      'deep_route', 'listing_request_status',
      'main_tab', 'my_ads',
      'role', 'marketer',
      'owner_decline_reason', v_reason
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_decline_listing_offer(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_decline_listing_offer(uuid, text) TO authenticated;

-- توجيه واضح لصفحة عروض المالك عند وصول عرض.
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

-- إثراء JSON للتوجيه في التطبيق (بدون تكرار إشعار من Dart).
CREATE OR REPLACE FUNCTION public.accept_listing_offer(p_offer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  off record;
  req record;
  v_round int;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

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

  v_round := coalesce(req.marketing_round, 1);
  IF coalesce(off.round_no, 1) IS DISTINCT FROM v_round THEN
    RAISE EXCEPTION 'stale_round';
  END IF;

  UPDATE public.listing_offers
  SET status = 'owner_accepted',
      owner_responded_at = now(),
      updated_at = now()
  WHERE id = p_offer_id;

  UPDATE public.listing_offers
  SET status = 'owner_rejected',
      updated_at = now()
  WHERE request_id = off.request_id
    AND coalesce(round_no, 1) = v_round
    AND id <> p_offer_id
    AND status IN ('submitted', 'pending');

  UPDATE public.listing_requests
  SET
    selected_offer_id = p_offer_id,
    selected_marketer_id = off.marketer_id,
    workflow_stage = 'marketer_selected',
    contract_started_at = coalesce(req.contract_started_at, now()),
    updated_at = now()
  WHERE id = off.request_id;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_accepted',
    'تم قبول عرضك',
    'يمكنك متابعة التعاقد من إدارتي.',
    'listing_request',
    off.request_id,
    jsonb_build_object(
      'request_id', off.request_id,
      'deep_route', 'listing_request_status',
      'main_tab', 'my_ads',
      'role', 'marketer'
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_listing_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_offer(uuid) TO authenticated;

COMMIT;
