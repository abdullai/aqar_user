-- =============================================================================
-- 1) عند قبول عرض: إشعار لكل مسوّق رُفض عرضه (owner_rejected) بنص يتضمن رقم الإعلان.
-- 2) إذا لم يُنشَأ عقد خلال 72 ساعة بعد القبول: إرجاع الطلب لـ waiting_marketers + إشعارات.
-- =============================================================================

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
        'listing_public_code', v_listing_code,
        'deep_route', 'my_ads',
        'main_tab', 'my_ads',
        'role', 'marketer'
      )
    );
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_listing_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_offer(uuid) TO authenticated;


CREATE OR REPLACE FUNCTION public.sync_expired_accepted_offer_contract_windows()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
  v_next int;
  v_offer uuid;
BEGIN
  FOR r IN
    SELECT lr.*
    FROM public.listing_requests lr
    WHERE coalesce(lr.workflow_stage, '') = 'marketer_selected'
      AND lr.contract_id IS NULL
      AND lr.contract_started_at IS NOT NULL
      AND lr.contract_started_at + interval '72 hours' < now()
      AND coalesce(lr.banned_under_review, false) = false
      AND lr.selected_offer_id IS NOT NULL
  LOOP
    v_next := coalesce(r.marketing_round, 1) + 1;
    v_offer := r.selected_offer_id;

    PERFORM public.workflow_create_notification(
      r.owner_id,
      'contract_creation_deadline_missed',
      'انتهت مهلة إنشاء العقد',
      'لم ينشئ المسوّق المختار العقد خلال ٧٢ ساعة من قبول عرضه. أُعيد طلبك إلى مرحلة انتظار عروض المسوقين.',
      'listing_request',
      r.id,
      jsonb_build_object(
        'request_id', r.id,
        'main_tab', 'my_ads',
        'deep_route', 'my_ads',
        'role', 'owner'
      )
    );

    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'contract_creation_deadline_missed',
        'انتهت مهلة إنشاء العقد',
        'لم يُنشَأ العقد خلال ٧٢ ساعة من قبول عرضك. يمكنك تقديم عرض جديد عند توفر الطلب.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'request_id', r.id,
          'main_tab', 'my_ads',
          'deep_route', 'my_ads',
          'role', 'marketer'
        )
      );
    END IF;

    IF v_offer IS NOT NULL THEN
      UPDATE public.listing_offers
      SET status = 'expired',
          updated_at = now()
      WHERE id = v_offer;
    END IF;

    UPDATE public.listing_offers
    SET status = 'cancelled',
        updated_at = now()
    WHERE request_id = r.id
      AND status = 'owner_rejected';

    UPDATE public.listing_requests
    SET
      workflow_stage = 'waiting_marketers',
      status = 'waiting_marketers',
      marketing_round = v_next,
      relist_count = coalesce(relist_count, 0) + 1,
      selected_offer_id = NULL,
      selected_marketer_id = NULL,
      contract_id = NULL,
      contract_started_at = NULL,
      contract_sent_at = NULL,
      contract_signed_at = NULL,
      permit_deadline_at = NULL,
      inactive_72h_at = NULL,
      waiting_marketers_since = now(),
      owner_distinct_marketer_declines = 0,
      updated_at = now()
    WHERE id = r.id;

    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_expired_accepted_offer_contract_windows() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_expired_accepted_offer_contract_windows() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_expired_accepted_offer_contract_windows() TO service_role;

COMMIT;
