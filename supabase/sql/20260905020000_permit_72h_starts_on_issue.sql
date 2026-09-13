-- مهلة التصريح 72 ساعة تبدأ عند ضغط المسوّق «إصدار تصريح»، لا عند قبول المالك.

BEGIN;

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
  v_listing_code text := '';
  rej record;
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

  SELECT trim(coalesce(p.listing_public_code::text, '')) INTO v_listing_code
  FROM public.properties p
  WHERE p.request_id = off.request_id
  ORDER BY p.created_at DESC NULLS LAST
  LIMIT 1;

  IF coalesce(v_listing_code, '') = '' THEN
    SELECT trim(coalesce(p.listing_public_code::text, '')) INTO v_listing_code
    FROM public.listing_requests lr
    JOIN public.properties p ON p.id = lr.preview_property_id
    WHERE lr.id = off.request_id
    LIMIT 1;
  END IF;

  IF coalesce(v_listing_code, '') = '' THEN
    v_listing_code := trim(coalesce(req.listing_request_public_code::text, ''));
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
    workflow_stage = 'contract_signed',
    contract_started_at = coalesce(req.contract_started_at, now()),
    contract_signed_at = coalesce(req.contract_signed_at, now()),
    permit_deadline_at = NULL,
    updated_at = now()
  WHERE id = off.request_id;

  PERFORM public.ensure_signed_listing_contract_for_publish(off.request_id);

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_accepted',
    'تم قبول عرضك',
    'تابع إصدار التصريح من تبويب «إصدار التصريح» في صفحتي.',
    'listing_request',
    off.request_id,
    jsonb_build_object(
      'request_id', off.request_id,
      'deep_route', 'listing_request_status',
      'main_tab', 'my_ads',
      'role', 'marketer',
      'my_ads_sub_tab', '2',
      'hub_tab_schema_v', '4'
    )
  );

  FOR rej IN
    SELECT lo.marketer_id
    FROM public.listing_offers lo
    WHERE lo.request_id = off.request_id
      AND coalesce(lo.round_no, 1) = v_round
      AND lo.id <> p_offer_id
      AND lo.status = 'owner_rejected'
      AND lo.marketer_id IS NOT NULL
  LOOP
    PERFORM public.workflow_create_notification(
      rej.marketer_id,
      'offer_not_selected',
      'عذراً، تم قبول عرض آخر',
      CASE
        WHEN coalesce(v_listing_code, '') <> '' THEN
          'تم قبول عرض آخر للإعلان رقم ' || v_listing_code || '.'
        ELSE
          'تم قبول عرض آخر لطلب التسويق المرتبط.'
      END,
      'listing_request',
      off.request_id,
      jsonb_build_object(
        'request_id', off.request_id,
        'role', 'marketer'
      )
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.marketer_set_request_to_permit_pending(
  p_request_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_due timestamptz;
  v_stage text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT *
    INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.selected_marketer_id IS NULL OR uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_selected_marketer';
  END IF;

  v_stage := lower(trim(coalesce(req.workflow_stage,'')));

  IF v_stage IN
       ('permit_pending','awaiting_permits','pending_permits','permit_issued','published') THEN
    IF req.permit_deadline_at IS NULL AND v_stage IN
         ('permit_pending','awaiting_permits','pending_permits') THEN
      UPDATE public.listing_requests
         SET permit_deadline_at = now() + interval '72 hours',
             updated_at = now()
       WHERE id = p_request_id;
    END IF;
    RETURN coalesce(req.workflow_stage::text, '');
  END IF;

  IF v_stage NOT IN ('contract_signed', 'marketer_selected') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_due := now() + interval '72 hours';

  UPDATE public.listing_requests
     SET workflow_stage      = 'permit_pending',
         permit_deadline_at  = v_due,
         contract_signed_at  = coalesce(contract_signed_at, now()),
         updated_at          = now()
   WHERE id = p_request_id;

  RETURN 'permit_pending';
END;
$$;

REVOKE ALL ON FUNCTION public.accept_listing_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_offer(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.marketer_set_request_to_permit_pending(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_set_request_to_permit_pending(uuid)
  TO authenticated, service_role;

COMMIT;
