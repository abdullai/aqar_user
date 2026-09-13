-- قبول صفقة دون إتمام فوري:
-- - طلب السوق: قبول عرض = اختيار الشريك فقط (الباقي معلّق حتى الإتمام أو الإلغاء).
-- - الإعلان: قبول حجز = فتح المراسلة لذلك المستخدم فقط.
-- عند إتمام الصفقة تُلغى بقية العروض/الحجوزات فتختفي من «صفقاتي» الخاصة بهم.

BEGIN;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS deal_completed_at timestamptz;

DO $$
DECLARE cname text;
BEGIN
  FOR cname IN
    SELECT con.conname
    FROM pg_constraint con
    WHERE con.conrelid = 'public.reservations'::regclass
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.reservations DROP CONSTRAINT IF EXISTS %I', cname);
  END LOOP;
  ALTER TABLE public.reservations
    ADD CONSTRAINT reservations_status_check
    CHECK (status IN ('pending', 'accepted', 'paid', 'cancelled', 'expired', 'completed'));
EXCEPTION WHEN others THEN
  RAISE NOTICE 'reservations status check: %', SQLERRM;
END $$;

CREATE OR REPLACE FUNCTION public.respond_market_request_offer(
  p_offer_id uuid,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer public.market_request_offers%ROWTYPE;
  v_action text := lower(trim(coalesce(p_action, '')));
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT o.* INTO v_offer
  FROM public.market_request_offers o
  JOIN public.market_property_requests r ON r.id = o.market_request_id
  WHERE o.id = p_offer_id
    AND r.requester_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found_or_not_owner';
  END IF;

  IF v_action IN ('accept', 'accepted', 'approve', 'approved') THEN
    IF EXISTS (
      SELECT 1
      FROM public.market_request_offers o2
      WHERE o2.market_request_id = v_offer.market_request_id
        AND o2.id <> p_offer_id
        AND lower(trim(coalesce(o2.status, ''))) IN ('accepted', 'approved', 'selected')
    ) THEN
      RAISE EXCEPTION 'another_offer_already_selected';
    END IF;

    UPDATE public.market_request_offers
    SET status = 'accepted', updated_at = now()
    WHERE id = p_offer_id;

    UPDATE public.market_property_requests
    SET
      selected_offer_id = p_offer_id,
      updated_at = now()
    WHERE id = v_offer.market_request_id
      AND requester_id = v_uid;
  ELSIF v_action IN ('reject', 'rejected', 'decline', 'declined') THEN
    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_market_property_request(
  p_request_id uuid,
  p_offer_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_offer_id IS NOT NULL THEN
    SELECT o.id INTO v_offer_id
    FROM public.market_request_offers o
    JOIN public.market_property_requests r ON r.id = o.market_request_id
    WHERE o.id = p_offer_id
      AND o.market_request_id = p_request_id
      AND r.requester_id = v_uid
    LIMIT 1;

    IF v_offer_id IS NULL THEN
      RAISE EXCEPTION 'offer_not_found_for_request';
    END IF;

    UPDATE public.market_request_offers
    SET status = 'accepted', updated_at = now()
    WHERE id = v_offer_id;

    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE market_request_id = p_request_id
      AND id <> v_offer_id
      AND coalesce(status, '') IN ('submitted', 'pending', 'accepted', 'approved', 'selected');
  ELSE
    SELECT selected_offer_id INTO v_offer_id
    FROM public.market_property_requests
    WHERE id = p_request_id AND requester_id = v_uid;

    IF v_offer_id IS NOT NULL THEN
      UPDATE public.market_request_offers
      SET status = 'rejected', updated_at = now()
      WHERE market_request_id = p_request_id
        AND id <> v_offer_id
        AND coalesce(status, '') IN ('submitted', 'pending', 'accepted', 'approved', 'selected');
    END IF;
  END IF;

  UPDATE public.market_property_requests
  SET
    status = 'completed',
    selected_offer_id = coalesce(v_offer_id, selected_offer_id),
    completed_at = now(),
    completed_by = v_uid,
    updated_at = now()
  WHERE id = p_request_id
    AND requester_id = v_uid
  RETURNING selected_offer_id INTO v_offer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', 'completed', 'selected_offer_id', v_offer_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_listing_reservation(
  p_reservation_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  rsrv record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT
    res.id,
    res.property_id,
    res.user_id,
    res.status,
    p.owner_id,
    p.published_by_marketer_id
  INTO rsrv
  FROM public.reservations res
  JOIN public.properties p ON p.id = res.property_id
  WHERE res.id = p_reservation_id
  FOR UPDATE OF res, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;

  IF NOT (
    uid = rsrv.owner_id
    OR (rsrv.published_by_marketer_id IS NOT NULL AND uid = rsrv.published_by_marketer_id)
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF lower(trim(coalesce(rsrv.status, ''))) NOT IN ('pending', 'paid') THEN
    RAISE EXCEPTION 'reservation_not_pending';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.reservations r2
    WHERE r2.property_id = rsrv.property_id
      AND r2.id <> p_reservation_id
      AND lower(trim(coalesce(r2.status, ''))) = 'accepted'
  ) THEN
    RAISE EXCEPTION 'another_buyer_already_selected';
  END IF;

  UPDATE public.reservations
  SET status = 'accepted', updated_at = now()
  WHERE id = p_reservation_id;

  BEGIN
    PERFORM public.workflow_create_notification(
      rsrv.user_id,
      'reservation_accepted',
      'تمت الموافقة على صفقتك',
      'وافق المالك على إتمام الصفقة. يمكنك الآن المراسلة ومتابعة الإتمام من صفقاتك.',
      'property',
      rsrv.property_id,
      jsonb_build_object('reservation_id', p_reservation_id, 'property_id', rsrv.property_id)
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN p_reservation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_property_sale(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  rsrv record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO prop FROM public.properties WHERE id = p_property_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF lower(trim(coalesce(prop.status, ''))) = 'sold' THEN
    RETURN;
  END IF;

  SELECT * INTO rsrv
  FROM public.reservations res
  WHERE res.property_id = p_property_id
    AND res.status = 'accepted'
    AND (res.expires_at IS NULL OR res.expires_at > now())
  ORDER BY res.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_accepted_reservation';
  END IF;

  IF NOT (
    uid = rsrv.user_id
    OR uid = prop.owner_id
    OR (prop.published_by_marketer_id IS NOT NULL AND uid = prop.published_by_marketer_id)
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  UPDATE public.properties p
  SET
    status = 'sold',
    workflow_stage = 'archived',
    sold_at = now(),
    sold_to_user_id = rsrv.user_id,
    reservation_expires_at = NULL,
    updated_at = now()
  WHERE p.id = p_property_id;

  UPDATE public.reservations
  SET
    status = 'completed',
    deal_completed_at = now(),
    updated_at = now()
  WHERE id = rsrv.id;

  UPDATE public.reservations
  SET status = 'cancelled', updated_at = now()
  WHERE property_id = p_property_id
    AND id IS DISTINCT FROM rsrv.id
    AND status IN ('pending', 'accepted', 'paid');
END;
$$;

REVOKE ALL ON FUNCTION public.respond_market_request_offer(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_market_property_request(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_listing_reservation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_property_sale(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_market_property_request(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_listing_reservation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid) TO authenticated;

COMMIT;
