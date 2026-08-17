-- إصلاح: column "type" is of type property_type but expression is of type text (42804)
-- عند INSERT من publish_property_from_contract نُ normalizes نوع العقار ثم نُ cast إلى property_type.

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
  v_type_raw text;
  v_type text;
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

  -- Map app catalog codes → property_type enum (villa | apartment | land).
  v_type_raw := coalesce(nullif(trim(req.payload_json->>'type'), ''), 'villa');
  v_type := lower(v_type_raw);

  IF v_type LIKE 'ut\_%' ESCAPE '\' THEN
    v_type := case lower(trim(coalesce(
      req.payload_json->'listing_guidance'->>'property_type_group',
      req.payload_json->'listing_guidance'->>'group'
    )))
      when 'land' then 'land'
      when 'commercial' then 'apartment'
      when 'project' then 'villa'
      when 'residential' then 'apartment'
      else 'villa'
    end;
  ELSIF v_type in ('land','land_fenced','land_walled','farm','station') THEN
    v_type := 'land';
  ELSIF v_type in ('villa','rest_house','chalet','traditional_house','palace') THEN
    v_type := 'villa';
  ELSIF v_type in (
    'apartment','apartment_building','floor','room','suite','residential_tower'
  ) THEN
    v_type := 'apartment';
  ELSIF v_type in (
    'hotel','warehouse','commercial_center','commercial_market','office_tower',
    'building','commercial_building','office','shop','showroom'
  ) THEN
    v_type := 'apartment';
  ELSIF v_type in ('project','other') THEN
    v_type := 'villa';
  ELSIF v_type in ('villa','apartment','land') THEN
    v_type := v_type;
  ELSE
    v_type := 'villa';
  END IF;

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
      v_type::property_type,
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

COMMIT;
