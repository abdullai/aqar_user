-- شفافية متقدّمي إتمام الصفقة: ملاحظة النافذة + وقت موافقة المالك.
-- الطابور يبقى سرّياً للمتقدمين الآخرين حتى مرور 72 ساعة دون إتمام
-- (cron_reactivate_parked_deals_after_72h).

BEGIN;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS applicant_note text,
  ADD COLUMN IF NOT EXISTS owner_accepted_at timestamptz;

ALTER TABLE public.market_request_offers
  ADD COLUMN IF NOT EXISTS owner_accepted_at timestamptz;

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
  SET
    status = 'accepted',
    owner_accepted_at = coalesce(owner_accepted_at, now()),
    updated_at = now()
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
    SET
      status = 'accepted',
      owner_accepted_at = coalesce(owner_accepted_at, now()),
      updated_at = now()
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

REVOKE ALL ON FUNCTION public.accept_listing_reservation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_reservation(uuid)
  TO authenticated;

REVOKE ALL ON FUNCTION public.respond_market_request_offer(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.respond_market_request_offer(uuid, text)
  TO authenticated;

COMMIT;
