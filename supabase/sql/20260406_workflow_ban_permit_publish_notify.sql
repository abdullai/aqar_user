-- =============================================================================
-- Owner cancel ban (>3), permit 72h owner notify + contract cancel, REGA package
-- gate for issue/publish-after-permit, dual-party publish + sign notifications,
-- buyer sale notification.
-- Apply after 20260418_reg_lifecycle_sale_review.sql and permit/workflow core.
-- Then apply 20260407_submit_listing_offer_offers_received_status.sql so
-- submit_listing_offer sets listing_requests.status = offers_received immediately
-- (instant hub tab moves; pair with send_push + in_app_notifications webhook for FCM).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- listing_requests — owner-driven contract cancels (reject broker contract)
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS owner_contract_cancel_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS banned_under_review boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.listing_requests.owner_contract_cancel_count IS
  'Increments when the owner cancels/rejects a listing contract (cancel_listing_contract).';
COMMENT ON COLUMN public.listing_requests.banned_under_review IS
  'True when owner_contract_cancel_count exceeds 3 — ad under manual review.';

-- ---------------------------------------------------------------------------
-- cancel_listing_contract — bump + ban flag when OWNER cancels
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_listing_contract(
  p_contract_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  v_other uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contract_not_found'; END IF;

  IF c.owner_id IS DISTINCT FROM uid AND c.marketer_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF c.status::text = 'signed' THEN
    RAISE EXCEPTION 'contract_already_signed';
  END IF;

  IF c.status::text = 'cancelled' THEN
    RETURN;
  END IF;

  v_other := CASE
    WHEN c.owner_id = uid THEN c.marketer_id
    ELSE c.owner_id
  END;

  UPDATE public.listing_contracts
  SET
    status = 'cancelled'::contract_status,
    cancelled_at = now(),
    cancelled_reason = coalesce(v_reason, cancelled_reason),
    updated_at = now()
  WHERE id = p_contract_id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_cancelled',
    updated_at = now(),
    owner_contract_cancel_count = CASE
      WHEN c.owner_id = uid THEN COALESCE(lr.owner_contract_cancel_count, 0) + 1
      ELSE COALESCE(lr.owner_contract_cancel_count, 0)
    END,
    banned_under_review = CASE
      WHEN c.owner_id = uid THEN
        (COALESCE(lr.owner_contract_cancel_count, 0) + 1) > 3
      ELSE lr.banned_under_review
    END,
    needs_manual_review = CASE
      WHEN c.owner_id = uid THEN
        lr.needs_manual_review OR (COALESCE(lr.owner_contract_cancel_count, 0) + 1) > 3
      ELSE lr.needs_manual_review
    END
  WHERE lr.id = c.request_id;

  IF v_other IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      v_other,
      'contract_cancelled',
      'تم إلغاء عقد التسويق',
      coalesce('سبب الإلغاء: ' || v_reason, 'تم إلغاء عقد التسويق.'),
      'listing_contract',
      p_contract_id,
      jsonb_build_object(
        'request_id', c.request_id,
        'contract_id', p_contract_id,
        'reason', v_reason
      )
    );
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- cron_expire_permit_pending_72h — notify owner + cancel unsigned contract
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_expire_permit_pending_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
BEGIN
  FOR r IN
    UPDATE public.listing_requests lr
    SET
      workflow_stage = 'inactive_72h',
      inactive_72h_at = now(),
      updated_at = now()
    WHERE coalesce(lr.workflow_stage, '') IN ('permit_pending', 'awaiting_permits', 'pending_permits')
      AND lr.permit_deadline_at IS NOT NULL
      AND lr.permit_deadline_at < now()
    RETURNING lr.id, lr.owner_id, lr.contract_id
  LOOP
    n := n + 1;

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'permit_deadline_expired',
        'انتهت مهلة التصريح',
        'لم يُكمل المسوّق إدخال بيانات تصريح الإعلان خلال المهلة. أُنهي انتظار التصريح — راجع الطلب أو تواصل مع الدعم.',
        'listing_request',
        r.id,
        jsonb_build_object('request_id', r.id, 'contract_id', r.contract_id)
      );
    END IF;

    IF r.contract_id IS NOT NULL THEN
      UPDATE public.listing_contracts lc
      SET
        status = 'cancelled'::contract_status,
        cancelled_at = COALESCE(lc.cancelled_at, now()),
        cancelled_reason = COALESCE(
          nullif(trim(lc.cancelled_reason), ''),
          'permit_deadline_expired_72h'
        ),
        updated_at = now()
      WHERE lc.id = r.contract_id
        AND lc.status::text IS DISTINCT FROM 'signed';
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_permit_pending_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_permit_pending_72h() TO service_role;

-- ---------------------------------------------------------------------------
-- owner_sign_listing_contract — notify owner (waiting permit) + marketer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_sign_listing_contract(p_contract_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  req record;
  v_mk uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contract_not_found'; END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = c.request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;

  IF c.offer_id IS NULL OR req.selected_offer_id IS DISTINCT FROM c.offer_id THEN
    RAISE EXCEPTION 'contract_offer_mismatch';
  END IF;

  IF c.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF c.status::text IS DISTINCT FROM 'pending_owner' THEN
    RAISE EXCEPTION 'contract_not_pending_owner';
  END IF;

  v_mk := c.marketer_id;

  UPDATE public.listing_contracts
  SET
    owner_signed_at = now(),
    status = 'signed'::contract_status,
    updated_at = now()
  WHERE id = p_contract_id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_signed',
    contract_signed_at = now(),
    updated_at = now()
  WHERE lr.id = c.request_id;

  PERFORM public.workflow_create_notification(
    c.owner_id,
    'contract_signed_waiting_permit',
    'تم توقيع العقد',
    'تم توقيع عقد التسويق. بانتظار إكمال المسوّق لرقم تصريح الإعلان والمستندات خلال المهلة المحددة.',
    'listing_contract',
    p_contract_id,
    jsonb_build_object('request_id', c.request_id, 'contract_id', p_contract_id)
  );

  IF v_mk IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      v_mk,
      'contract_signed_waiting_permit',
      'وقع المالك العقد',
      'وقع المالك عقد التسويق. أكمل رقم تصريح الإعلان ورفع مستندات REGA من إدارتي.',
      'listing_contract',
      p_contract_id,
      jsonb_build_object('request_id', c.request_id, 'contract_id', p_contract_id)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.owner_sign_listing_contract(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_sign_listing_contract(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- issue_listing_permit — require REGA proof path in permit payload
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_listing_permit(
  p_request_id uuid,
  p_permit_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_target_marketer_id uuid;
  v_id uuid;
  v_status public.permit_status;
  v_has_proof boolean;
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

  IF uid IS DISTINCT FROM req.owner_id THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN ('permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_target_marketer_id := req.selected_marketer_id;
  IF v_target_marketer_id IS NULL THEN
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  IF p_permit_id IS NOT NULL THEN
    SELECT lp.id, lp.status
    INTO v_id, v_status
    FROM public.listing_permits lp
    WHERE lp.id = p_permit_id
      AND lp.request_id = p_request_id
      AND lp.marketer_id = v_target_marketer_id
    FOR UPDATE
    LIMIT 1;
  ELSE
    SELECT lp.id, lp.status
    INTO v_id, v_status
    FROM public.listing_permits lp
    WHERE lp.request_id = p_request_id
      AND lp.marketer_id = v_target_marketer_id
    ORDER BY lp.created_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'permit_not_found';
  END IF;

  IF v_status NOT IN ('pending'::permit_status, 'submitted'::permit_status) THEN
    RAISE EXCEPTION 'permit_not_pending';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.listing_permits lp
    WHERE lp.id = v_id
      AND coalesce(nullif(trim(lp.permit_no), ''), '') <> ''
      AND coalesce(nullif(trim(lp.authority_name), ''), '') <> ''
      AND coalesce(nullif(trim(lp.license_no), ''), '') <> ''
  ) THEN
    RAISE EXCEPTION 'permit_data_incomplete';
  END IF;

  SELECT
    coalesce(nullif(trim(lp.payload->>'ad_qr_storage_path'), ''), '') <> ''
    OR coalesce(nullif(trim(lp.payload->>'rega_pdf_storage_path'), ''), '') <> ''
  INTO v_has_proof
  FROM public.listing_permits lp
  WHERE lp.id = v_id;

  IF NOT coalesce(v_has_proof, false) THEN
    RAISE EXCEPTION 'permit_rega_package_incomplete';
  END IF;

  UPDATE public.listing_permits
  SET
    status = 'approved'::permit_status,
    issued_at = COALESCE(issued_at, now()),
    reviewed_at = now(),
    updated_at = now()
  WHERE id = v_id;

  UPDATE public.listing_requests
  SET
    workflow_stage = 'permit_issued',
    updated_at = now()
  WHERE id = p_request_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_listing_permit(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_listing_permit(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- publish_property_after_permit — same REGA proof gate
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_property_after_permit(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_contract_id uuid;
  v_permit_status public.permit_status;
  v_issued_at timestamptz;
  v_prop_id uuid;
  v_has_proof boolean;
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

  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN ('permit_issued', 'permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_contract_id := req.contract_id;
  IF v_contract_id IS NULL THEN
    RAISE EXCEPTION 'contract_not_found';
  END IF;

  IF req.selected_marketer_id IS NULL THEN
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  SELECT lp.status, lp.issued_at
  INTO v_permit_status, v_issued_at
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = req.selected_marketer_id
  ORDER BY lp.created_at DESC
  LIMIT 1;

  IF v_permit_status IS NULL OR v_permit_status <> 'approved'::permit_status THEN
    RAISE EXCEPTION 'permit_not_approved';
  END IF;

  SELECT
    coalesce(nullif(trim(lp.payload->>'ad_qr_storage_path'), ''), '') <> ''
    OR coalesce(nullif(trim(lp.payload->>'rega_pdf_storage_path'), ''), '') <> ''
  INTO v_has_proof
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = req.selected_marketer_id
  ORDER BY lp.created_at DESC
  LIMIT 1;

  IF NOT coalesce(v_has_proof, false) THEN
    RAISE EXCEPTION 'permit_rega_package_incomplete';
  END IF;

  IF uid IS DISTINCT FROM req.owner_id AND uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  v_prop_id := public.publish_property_from_contract(v_contract_id);
  RETURN v_prop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_property_after_permit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_after_permit(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- publish_property_from_contract — in-app: ad live (owner + marketer)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_property_from_contract(p_contract_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  req record;
  v_prop uuid;
  v_lat double precision;
  v_lng double precision;
  v_price numeric := 0;
  v_area numeric := 0;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'contract_not_found';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = c.request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF c.owner_id IS DISTINCT FROM uid AND c.marketer_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF c.status::text IS DISTINCT FROM 'signed' THEN
    RAISE EXCEPTION 'contract_not_signed';
  END IF;

  IF c.offer_id IS NULL OR req.selected_offer_id IS DISTINCT FROM c.offer_id THEN
    RAISE EXCEPTION 'contract_offer_mismatch';
  END IF;

  IF coalesce(req.workflow_stage, '') = 'published' THEN
    SELECT p.id INTO v_prop
    FROM public.properties p
    WHERE p.request_id = req.id
    ORDER BY p.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_prop IS NULL AND req.preview_property_id IS NOT NULL THEN
      v_prop := req.preview_property_id;
    END IF;

    IF v_prop IS NOT NULL THEN
      UPDATE public.properties p
      SET
        workflow_stage = 'published',
        status = 'published',
        published_by_marketer_id = coalesce(p.published_by_marketer_id, c.marketer_id),
        updated_at = now()
      WHERE p.id = v_prop;

      RETURN v_prop;
    END IF;
  END IF;

  v_lat := req.lat;
  v_lng := req.lng;

  BEGIN
    v_price := (nullif(trim(req.payload_json->>'price'), ''))::numeric;
  EXCEPTION WHEN OTHERS THEN
    v_price := 0;
  END;

  BEGIN
    v_area := (nullif(trim(req.payload_json->>'area'), ''))::numeric;
  EXCEPTION WHEN OTHERS THEN
    v_area := 0;
  END;

  IF req.preview_property_id IS NOT NULL THEN
    UPDATE public.properties p
    SET
      status = coalesce(nullif(trim(p.status::text), ''), 'published'),
      workflow_stage = 'published',
      published_by_marketer_id = coalesce(p.published_by_marketer_id, c.marketer_id),
      request_id = coalesce(p.request_id, req.id),
      updated_at = now()
    WHERE p.id = req.preview_property_id
    RETURNING p.id INTO v_prop;
  END IF;

  IF v_prop IS NULL THEN
    INSERT INTO public.properties (
      owner_id,
      title,
      description,
      city,
      type,
      purpose,
      area,
      price,
      currency,
      negotiable,
      is_auction,
      views,
      status,
      workflow_stage,
      latitude,
      longitude,
      request_id,
      published_by_marketer_id,
      created_at,
      updated_at
    )
    VALUES (
      req.owner_id,
      coalesce(nullif(trim(req.title), ''), 'عقار'),
      coalesce(
        nullif(trim(req.payload_json->>'description'), ''),
        nullif(trim(req.title), ''),
        '—'
      ),
      coalesce(nullif(trim(req.city), ''), ''),
      coalesce(nullif(trim(req.payload_json->>'type'), ''), 'apartment'),
      coalesce(nullif(trim(req.payload_json->>'purpose'), ''), 'sale'),
      v_area,
      v_price,
      coalesce(nullif(trim(req.payload_json->>'currency'), ''), 'SAR'),
      coalesce((req.payload_json->>'negotiable')::boolean, false),
      coalesce((req.payload_json->>'is_auction')::boolean, false),
      0,
      'published',
      'published',
      v_lat,
      v_lng,
      req.id,
      c.marketer_id,
      now(),
      now()
    )
    RETURNING id INTO v_prop;
  END IF;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'published',
    preview_property_id = coalesce(lr.preview_property_id, v_prop),
    updated_at = now()
  WHERE lr.id = req.id;

  UPDATE public.properties p
  SET
    workflow_stage = 'published',
    status = 'published',
    published_by_marketer_id = coalesce(p.published_by_marketer_id, c.marketer_id),
    updated_at = now()
  WHERE p.id = v_prop;

  IF req.owner_id IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      req.owner_id,
      'property_published_live',
      'الإعلان أصبح ظاهراً',
      'أصبح إعلانك متاحاً على الرئيسية.',
      'property',
      v_prop,
      jsonb_build_object('property_id', v_prop, 'request_id', req.id, 'contract_id', p_contract_id)
    );
  END IF;

  IF c.marketer_id IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      c.marketer_id,
      'property_published_live',
      'الإعلان أصبح ظاهراً',
      'تم نشر الإعلان وهو متاح الآن على الرئيسية.',
      'property',
      v_prop,
      jsonb_build_object('property_id', v_prop, 'request_id', req.id, 'contract_id', p_contract_id)
    );
  END IF;

  RETURN v_prop;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_property_from_contract(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_from_contract(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- complete_property_sale — notify buyer as well
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_property_sale(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  r record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO prop FROM public.properties WHERE id = p_property_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  SELECT * INTO r
  FROM public.reservations
  WHERE property_id = p_property_id
    AND status IN ('pending', 'paid')
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_active_reservation';
  END IF;

  IF NOT (
    uid = r.user_id
    OR uid = prop.owner_id
    OR (prop.published_by_marketer_id IS NOT NULL AND uid = prop.published_by_marketer_id)
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF lower(trim(coalesce(prop.workflow_stage, ''))) IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'property_not_reserved';
  END IF;

  UPDATE public.properties p
  SET
    status = 'sold',
    workflow_stage = 'archived',
    sold_at = now(),
    sold_to_user_id = r.user_id,
    reservation_expires_at = NULL,
    updated_at = now()
  WHERE p.id = p_property_id;

  UPDATE public.reservations
  SET status = 'paid', updated_at = now()
  WHERE id = r.id;

  UPDATE public.reservations
  SET status = 'cancelled', updated_at = now()
  WHERE property_id = p_property_id
    AND id IS DISTINCT FROM r.id
    AND status IN ('pending', 'paid');

  PERFORM public.workflow_create_notification(
    prop.owner_id,
    'property_sale_completed',
    'تم إتمام البيع',
    'تم تسجيل إتمام البيع على إعلانك.',
    'property',
    p_property_id,
    jsonb_build_object('property_id', p_property_id, 'reservation_id', r.id)
  );

  IF r.user_id IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      r.user_id,
      'property_sale_completed',
      'تم إتمام البيع',
      'تم تسجيل إتمام البيع على العقار الذي في سلتك.',
      'property',
      p_property_id,
      jsonb_build_object('property_id', p_property_id, 'reservation_id', r.id)
    );
  END IF;

  IF prop.published_by_marketer_id IS NOT NULL
     AND prop.published_by_marketer_id IS DISTINCT FROM prop.owner_id THEN
    PERFORM public.workflow_create_notification(
      prop.published_by_marketer_id,
      'property_sale_completed',
      'تم إتمام البيع',
      'تم تسجيل إتمام البيع لإعلان منشور من جهتك.',
      'property',
      p_property_id,
      jsonb_build_object('property_id', p_property_id, 'reservation_id', r.id)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_property_sale(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid) TO authenticated;

COMMIT;
