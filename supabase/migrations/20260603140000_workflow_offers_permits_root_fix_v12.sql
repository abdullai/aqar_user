-- =============================================================================
-- 2026-06-03 v12 — إصلاح جذري: تعارض العروض/التصاريح + إعادة تقديم العرض
-- =============================================================================
-- (1) قيد فريد قديم على (request_id, marketer_id) يمنع INSERT عند وجود عرض
--     منتهٍ (expired) → Postgres 23505 offers_unique_request_marketer.
-- (2) submit_listing_offer كان يُدرج صفاً جديداً بدل تحديث العرض القديم.
-- (3) listing_permits_unique_request_marketer_active + سباقات الإدخال من العميل.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A) إزالة القيود/الفهارس الفريدة القديمة على (request_id, marketer_id)
--     ملاحظة: offers_unique_request_marketer قد يكون CONSTRAINT (فهرس مرتبط)
--     — يجب DROP CONSTRAINT قبل DROP INDEX وإلا 2BP01.
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_offers
  DROP CONSTRAINT IF EXISTS offers_unique_request_marketer;

DROP INDEX IF EXISTS public.offers_unique_request_marketer;
DROP INDEX IF EXISTS public.ux_listing_offers_request_marketer;
DROP INDEX IF EXISTS public.listing_offers_request_marketer_key;

DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'listing_offers'
      AND con.contype = 'u'
      AND pg_get_constraintdef(con.oid) ILIKE '%request_id%'
      AND pg_get_constraintdef(con.oid) ILIKE '%marketer_id%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.listing_offers DROP CONSTRAINT IF EXISTS %I',
      c.conname
    );
  END LOOP;
END $$;

-- عرض نشط واحد لكل (طلب، مسوّق، جولة)
CREATE UNIQUE INDEX IF NOT EXISTS listing_offers_unique_live_per_round
  ON public.listing_offers (request_id, marketer_id, coalesce(round_no, 1))
  WHERE status IN ('submitted', 'pending');

-- ---------------------------------------------------------------------------
-- B) submit_listing_offer — تحديث العرض الموجود أو إدراج جديد
-- ---------------------------------------------------------------------------
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

  IF coalesce(req.workflow_stage, '') IN (
    'marketer_selected', 'contract_pending', 'contract_sent', 'contract_returned',
    'contract_signed', 'contract_cancelled', 'cancelled', 'terminated',
    'permit_pending', 'permit_issued', 'published', 'reserved', 'archived'
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

-- ---------------------------------------------------------------------------
-- C) upsert_listing_permit_for_publish — تجاوز RLS/التكرار عند النشر
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.upsert_listing_permit_for_publish(
  p_request_id uuid,
  p_permit_no text,
  p_broker_nid text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_id uuid;
  v_notes text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.selected_marketer_id IS NULL OR uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_selected_marketer';
  END IF;

  v_notes := CASE
    WHEN coalesce(trim(p_broker_nid), '') = '' THEN NULL
    ELSE 'broker_nid:' || trim(p_broker_nid)
  END;

  SELECT p.id
    INTO v_id
  FROM public.listing_permits p
  WHERE p.request_id = p_request_id
    AND p.marketer_id = uid
    AND p.status <> 'rejected'::permit_status
  ORDER BY
    CASE WHEN p.status::text = 'approved' THEN 0 ELSE 1 END,
    p.created_at DESC NULLS LAST,
    p.id DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NOT NULL THEN
    UPDATE public.listing_permits
       SET permit_no = trim(p_permit_no),
           license_no = trim(p_permit_no),
           authority_name = 'REGA',
           status = 'submitted'::permit_status,
           submitted_at = now(),
           notes = v_notes
     WHERE id = v_id;
  ELSE
    INSERT INTO public.listing_permits (
      request_id,
      marketer_id,
      permit_no,
      license_no,
      authority_name,
      status,
      submitted_at,
      notes,
      created_at
    ) VALUES (
      p_request_id,
      uid,
      trim(p_permit_no),
      trim(p_permit_no),
      'REGA',
      'submitted'::permit_status,
      now(),
      v_notes,
      now()
    )
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_listing_permit_for_publish(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_listing_permit_for_publish(uuid, text, text) TO authenticated;

COMMIT;
