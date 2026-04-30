-- =============================================================================
-- RPC: publish_property_from_contract
-- After contract_signed: create or upgrade a property from listing_requests,
-- set listing_requests + properties workflow to published.
-- Does not start permits, reservations, or change enums.
-- =============================================================================

BEGIN;

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

  -- Idempotent: already published — return linked property if any
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

  -- Prefer upgrading preview row when present
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

  RETURN v_prop;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_property_from_contract(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_from_contract(uuid) TO authenticated;

COMMIT;
