-- تأكيد إتمام الصفقة خارج التطبيق + حدود البطاقات + ملاحظة الإتمام.

BEGIN;

ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS deal_completion_note text;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS deal_completion_note text;

CREATE OR REPLACE FUNCTION public.open_accepted_deals_for_me()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_out jsonb := '[]'::jsonb;
BEGIN
  IF uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_out
  FROM (
    SELECT jsonb_build_object(
      'kind', 'listing',
      'id', res.id,
      'property_id', res.property_id,
      'title', coalesce(nullif(trim(p.title), ''), '—'),
      'role', CASE WHEN res.user_id = uid THEN 'partner' ELSE 'owner' END
    ) AS obj
    FROM public.reservations res
    JOIN public.properties p ON p.id = res.property_id
    WHERE lower(trim(coalesce(res.status, ''))) = 'accepted'
      AND (
        res.user_id = uid
        OR p.owner_id = uid
        OR (p.published_by_marketer_id IS NOT NULL AND p.published_by_marketer_id = uid)
      )

    UNION ALL

    SELECT jsonb_build_object(
      'kind', 'market_request',
      'id', o.id,
      'offer_id', o.id,
      'request_id', r.id,
      'market_request_id', r.id,
      'title', coalesce(nullif(trim(r.title), ''), '—'),
      'role', CASE WHEN o.offerer_id = uid THEN 'partner' ELSE 'owner' END
    ) AS obj
    FROM public.market_request_offers o
    JOIN public.market_property_requests r ON r.id = o.market_request_id
    WHERE lower(trim(coalesce(o.status, ''))) IN ('accepted', 'approved', 'selected')
      AND lower(trim(coalesce(r.status, ''))) NOT IN ('completed', 'cancelled', 'canceled', 'closed')
      AND (
        o.offerer_id = uid
        OR r.requester_id = uid
      )
  ) x;

  RETURN coalesce(v_out, '[]'::jsonb);
END;
$$;

DROP FUNCTION IF EXISTS public.complete_property_sale(uuid);

CREATE OR REPLACE FUNCTION public.complete_property_sale(
  p_property_id uuid,
  p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  rsrv record;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
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
    deal_completion_note = coalesce(v_note, deal_completion_note),
    updated_at = now()
  WHERE id = rsrv.id;

  UPDATE public.reservations
  SET status = 'cancelled', updated_at = now()
  WHERE property_id = p_property_id
    AND id IS DISTINCT FROM rsrv.id
    AND status IN ('pending', 'accepted', 'paid');
END;
$$;

DROP FUNCTION IF EXISTS public.complete_market_property_request(uuid, uuid);

CREATE OR REPLACE FUNCTION public.complete_market_property_request(
  p_request_id uuid,
  p_offer_id uuid,
  p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer_id uuid;
  v_req public.market_property_requests%ROWTYPE;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO v_req
  FROM public.market_property_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found_or_not_owner';
  END IF;

  IF p_offer_id IS NOT NULL THEN
    SELECT o.id INTO v_offer_id
    FROM public.market_request_offers o
    WHERE o.id = p_offer_id
      AND o.market_request_id = p_request_id
    LIMIT 1;
    IF v_offer_id IS NULL THEN
      RAISE EXCEPTION 'offer_not_found_for_request';
    END IF;
  ELSE
    v_offer_id := v_req.selected_offer_id;
  END IF;

  IF NOT (
    v_req.requester_id = v_uid
    OR EXISTS (
      SELECT 1
      FROM public.market_request_offers o
      WHERE o.id = v_offer_id
        AND o.offerer_id = v_uid
        AND lower(trim(coalesce(o.status, ''))) IN ('accepted', 'approved', 'selected')
    )
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF v_offer_id IS NOT NULL THEN
    UPDATE public.market_request_offers
    SET status = 'accepted', updated_at = now()
    WHERE id = v_offer_id;

    UPDATE public.market_request_offers
    SET status = 'rejected', updated_at = now()
    WHERE market_request_id = p_request_id
      AND id <> v_offer_id
      AND coalesce(status, '') IN ('submitted', 'pending', 'accepted', 'approved', 'selected');
  END IF;

  UPDATE public.market_property_requests
  SET
    status = 'completed',
    selected_offer_id = coalesce(v_offer_id, selected_offer_id),
    completed_at = now(),
    completed_by = v_uid,
    deal_completion_note = coalesce(v_note, deal_completion_note),
    updated_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', true, 'status', 'completed', 'selected_offer_id', v_offer_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_active_deal_slot_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  uid uuid;
  n int;
BEGIN
  IF TG_TABLE_NAME = 'reservations' THEN
    uid := NEW.user_id;
  ELSE
    uid := NEW.offerer_id;
  END IF;
  IF uid IS NULL THEN
    RETURN NEW;
  END IF;
  -- إعادة إرسال نفس الصفقة (قيد فريد) لا يستهلك خانة إضافية.
  IF TG_TABLE_NAME = 'reservations' THEN
    IF EXISTS (
      SELECT 1 FROM public.reservations r
      WHERE r.user_id = uid
        AND r.property_id = NEW.property_id
        AND lower(trim(coalesce(r.status, ''))) IN ('pending', 'paid', 'accepted')
    ) THEN
      RETURN NEW;
    END IF;
  ELSIF TG_TABLE_NAME = 'market_request_offers' THEN
    IF EXISTS (
      SELECT 1 FROM public.market_request_offers o
      WHERE o.offerer_id = uid
        AND o.market_request_id = NEW.market_request_id
    ) THEN
      RETURN NEW;
    END IF;
  END IF;
  SELECT
    (SELECT count(*)::int FROM public.reservations r
      WHERE r.user_id = uid
        AND lower(trim(coalesce(r.status, ''))) IN ('pending', 'paid', 'accepted'))
    +
    (SELECT count(*)::int FROM public.market_request_offers o
      WHERE o.offerer_id = uid
        AND lower(trim(coalesce(o.status, ''))) IN ('submitted', 'pending', 'accepted', 'approved', 'selected'))
  INTO n;
  IF n >= 10 THEN
    RAISE EXCEPTION 'deal_slot_limit'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reservations_deal_slot ON public.reservations;
CREATE TRIGGER trg_reservations_deal_slot
BEFORE INSERT ON public.reservations
FOR EACH ROW
EXECUTE FUNCTION public.enforce_active_deal_slot_limit();

DROP TRIGGER IF EXISTS trg_offers_deal_slot ON public.market_request_offers;
CREATE TRIGGER trg_offers_deal_slot
BEFORE INSERT ON public.market_request_offers
FOR EACH ROW
EXECUTE FUNCTION public.enforce_active_deal_slot_limit();

CREATE OR REPLACE FUNCTION public.enforce_inventory_slot_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  uid uuid;
  n int;
BEGIN
  IF TG_TABLE_NAME = 'properties' THEN
    uid := COALESCE(NEW.owner_id, NEW.published_by_marketer_id);
  ELSE
    uid := NEW.requester_id;
  END IF;
  IF uid IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT
    (SELECT count(*)::int FROM public.properties p
      WHERE (p.owner_id = uid OR p.published_by_marketer_id = uid)
        AND lower(trim(coalesce(p.status, ''))) NOT IN ('sold', 'deleted', 'removed', 'archived')
        AND lower(trim(coalesce(p.workflow_stage, ''))) NOT IN ('archived'))
    +
    (SELECT count(*)::int FROM public.market_property_requests r
      WHERE r.requester_id = uid
        AND lower(trim(coalesce(r.status, ''))) NOT IN ('completed', 'cancelled', 'canceled', 'closed'))
  INTO n;
  IF n >= 20 THEN
    RAISE EXCEPTION 'inventory_slot_limit'
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_properties_inventory_slot ON public.properties;
CREATE TRIGGER trg_properties_inventory_slot
BEFORE INSERT ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.enforce_inventory_slot_limit();

DROP TRIGGER IF EXISTS trg_requests_inventory_slot ON public.market_property_requests;
CREATE TRIGGER trg_requests_inventory_slot
BEFORE INSERT ON public.market_property_requests
FOR EACH ROW
EXECUTE FUNCTION public.enforce_inventory_slot_limit();

REVOKE ALL ON FUNCTION public.open_accepted_deals_for_me() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_property_sale(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_market_property_request(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.open_accepted_deals_for_me() TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_market_property_request(uuid, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_property_sale(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.complete_property_sale(p_property_id, NULL::text);
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_market_property_request(
  p_request_id uuid,
  p_offer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.complete_market_property_request(p_request_id, p_offer_id, NULL::text);
END;
$$;

GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_market_property_request(uuid, uuid) TO authenticated;

COMMIT;
