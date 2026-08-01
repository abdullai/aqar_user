-- =============================================================================
-- إصلاح: invalid input value for enum offer_status: ""
-- عند قبول العرض يُحدَّث selected_marketer_id → trigger يستدعي
-- _mark_losing_offers_for_request التي كانت تستخدم coalesce(status,'') على enum.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._mark_losing_offers_for_request(
  p_request_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req record;
  v_n int := 0;
BEGIN
  SELECT * INTO v_req FROM public.listing_requests WHERE id = p_request_id;
  IF NOT FOUND OR v_req.selected_marketer_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.listing_offers
     SET status = 'owner_rejected',
         lost_at = coalesce(lost_at, now()),
         lost_reason = coalesce(nullif(trim(lost_reason), ''), 'owner_selected_other_marketer'),
         updated_at = now()
   WHERE request_id = p_request_id
     AND marketer_id IS DISTINCT FROM v_req.selected_marketer_id
     AND lower(status::text) IN ('submitted', 'pending');

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public._mark_losing_offers_for_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._mark_losing_offers_for_request(uuid)
  TO authenticated, service_role;

-- توحيد مقارنات enum في accept_listing_offer (بدون coalesce على العمود enum)
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

  IF lower(off.status::text) NOT IN ('submitted', 'pending') THEN
    RAISE EXCEPTION 'offer_not_active';
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
    AND status::text IN ('submitted', 'pending');

  UPDATE public.listing_requests
  SET
    selected_offer_id = p_offer_id,
    selected_marketer_id = off.marketer_id,
    workflow_stage = 'contract_signed',
    contract_started_at = coalesce(req.contract_started_at, now()),
    contract_signed_at = coalesce(req.contract_signed_at, now()),
    permit_deadline_at = coalesce(req.permit_deadline_at, now() + interval '72 hours'),
    updated_at = now()
  WHERE id = off.request_id;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_accepted',
    'تم قبول عرضك',
    'يمكنك متابعة إصدار التصاريح والنشر من تبويب «تم الموافقة» في صفحتي.',
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
      AND lo.status::text = 'owner_rejected'
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

REVOKE ALL ON FUNCTION public.accept_listing_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_offer(uuid) TO authenticated;

COMMIT;
