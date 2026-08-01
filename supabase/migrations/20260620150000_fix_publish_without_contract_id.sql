-- =============================================================================
-- إصلاح نشر الإعلان بعد التصريح عندما لا يوجد contract_id على الطلب
-- (مسار التعاقد المبسّط: accept_listing_offer → contract_signed بدون عقد فعلي).
-- الخطأ السابق: PostgrestException(contract_not_found, P0001)
-- =============================================================================

BEGIN;

-- يُنشئ أو يُحدّث عقداً موقّعاً مرتبطاً بالعرض المقبول ثم يعيد contract_id.
CREATE OR REPLACE FUNCTION public.ensure_signed_listing_contract_for_publish(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req record;
  off record;
  v_contract_id uuid;
  v_round int;
BEGIN
  SELECT *
    INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.selected_offer_id IS NULL THEN
    RAISE EXCEPTION 'offer_not_selected';
  END IF;

  SELECT *
    INTO off
  FROM public.listing_offers
  WHERE id = req.selected_offer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  v_round := coalesce(off.round_no, req.marketing_round, 1);

  IF req.contract_id IS NOT NULL THEN
    SELECT c.id
      INTO v_contract_id
    FROM public.listing_contracts c
    WHERE c.id = req.contract_id
      AND c.request_id = p_request_id
    LIMIT 1;
  END IF;

  IF v_contract_id IS NULL THEN
    SELECT c.id
      INTO v_contract_id
    FROM public.listing_contracts c
    WHERE c.offer_id = req.selected_offer_id
    LIMIT 1;
  END IF;

  IF v_contract_id IS NULL AND req.selected_marketer_id IS NOT NULL THEN
    SELECT c.id
      INTO v_contract_id
    FROM public.listing_contracts c
    WHERE c.request_id = p_request_id
      AND c.marketer_id = req.selected_marketer_id
    ORDER BY c.created_at DESC
    LIMIT 1;
  END IF;

  IF v_contract_id IS NULL THEN
    INSERT INTO public.listing_contracts (
      request_id,
      owner_id,
      marketer_id,
      offer_id,
      round_no,
      status,
      owner_signed_at,
      marketer_signed_at,
      created_at,
      updated_at
    )
    VALUES (
      p_request_id,
      req.owner_id,
      off.marketer_id,
      req.selected_offer_id,
      v_round,
      'signed'::contract_status,
      now(),
      now(),
      now(),
      now()
    )
    RETURNING id INTO v_contract_id;
  ELSE
    UPDATE public.listing_contracts
       SET offer_id = coalesce(offer_id, req.selected_offer_id),
           status = 'signed'::contract_status,
           owner_signed_at = coalesce(owner_signed_at, now()),
           marketer_signed_at = coalesce(marketer_signed_at, now()),
           updated_at = now()
     WHERE id = v_contract_id;
  END IF;

  UPDATE public.listing_requests
     SET contract_id = v_contract_id,
         updated_at = now()
   WHERE id = p_request_id
     AND contract_id IS DISTINCT FROM v_contract_id;

  RETURN v_contract_id;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_signed_listing_contract_for_publish(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_signed_listing_contract_for_publish(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.ensure_signed_listing_contract_for_publish(uuid) IS
  'يضمن وجود عقد موقّع مرتبط بالعرض المقبول قبل النشر — للمسار المبسّط بدون توقيع داخل التطبيق.';

-- ---------------------------------------------------------------------------
-- publish_property_after_permit — لا يفشل عند contract_id = NULL
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
  v_permit_no text;
  v_auth text;
  v_lic text;
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

  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN
       ('permit_issued', 'permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  IF req.selected_marketer_id IS NULL THEN
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  v_contract_id := req.contract_id;
  IF v_contract_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.listing_contracts c WHERE c.id = v_contract_id
  ) THEN
    v_contract_id := public.ensure_signed_listing_contract_for_publish(p_request_id);
  ELSE
  UPDATE public.listing_contracts
     SET status = 'signed'::contract_status,
         offer_id = coalesce(offer_id, req.selected_offer_id),
         owner_signed_at = coalesce(owner_signed_at, now()),
         marketer_signed_at = coalesce(marketer_signed_at, now()),
         updated_at = now()
   WHERE id = v_contract_id
     AND status::text IS DISTINCT FROM 'signed';
  END IF;

  SELECT lp.status,
         lp.issued_at,
         coalesce(nullif(trim(lp.permit_no), ''),       ''),
         coalesce(nullif(trim(lp.authority_name), ''),  ''),
         coalesce(nullif(trim(lp.license_no), ''),      '')
  INTO v_permit_status,
       v_issued_at,
       v_permit_no,
       v_auth,
       v_lic
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = req.selected_marketer_id
  ORDER BY lp.created_at DESC
  LIMIT 1;

  IF v_permit_status IS NULL THEN
    RAISE EXCEPTION 'permit_not_found';
  END IF;

  IF v_permit_no = '' OR v_auth = '' OR v_lic = '' THEN
    RAISE EXCEPTION 'permit_rega_package_incomplete';
  END IF;

  IF v_permit_status::text NOT IN ('approved') THEN
    UPDATE public.listing_permits
       SET status      = 'approved'::permit_status,
           issued_at   = COALESCE(issued_at, now()),
           reviewed_at = now(),
           updated_at  = now()
     WHERE request_id = p_request_id
       AND marketer_id = req.selected_marketer_id;
  END IF;

  IF uid IS DISTINCT FROM req.owner_id AND uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  v_prop_id := public.publish_property_from_contract(v_contract_id);

  UPDATE public.listing_requests
     SET workflow_stage = 'published',
         updated_at     = now()
   WHERE id = p_request_id
     AND lower(trim(coalesce(workflow_stage, ''))) <> 'published';

  RETURN v_prop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_property_after_permit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_after_permit(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- قبول العرض: إنشاء عقد موقّع تلقائياً للمسار المبسّط
-- ---------------------------------------------------------------------------
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
    permit_deadline_at = coalesce(req.permit_deadline_at, now() + interval '72 hours'),
    updated_at = now()
  WHERE id = off.request_id;

  PERFORM public.ensure_signed_listing_contract_for_publish(off.request_id);

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

-- ترحيل الطلبات العالقة بدون عقد
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT lr.id
    FROM public.listing_requests lr
    WHERE lr.selected_offer_id IS NOT NULL
      AND (
        lr.contract_id IS NULL
        OR NOT EXISTS (
          SELECT 1 FROM public.listing_contracts c WHERE c.id = lr.contract_id
        )
      )
      AND lower(trim(coalesce(lr.workflow_stage, ''))) IN (
        'marketer_selected',
        'contract_signed',
        'permit_pending',
        'awaiting_permits',
        'pending_permits',
        'permit_issued'
      )
  LOOP
    BEGIN
      PERFORM public.ensure_signed_listing_contract_for_publish(r.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'ensure_signed_listing_contract_for_publish skipped %: %', r.id, SQLERRM;
    END;
  END LOOP;
END $$;

COMMIT;
