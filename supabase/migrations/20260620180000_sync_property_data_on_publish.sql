-- مزامنة بيانات العقار (سعر، مساحة، ترخيص، published_at) عند النشر من العقد/المعاينة.
-- يُصلح بطاقات الرئيسية/التفاصيل/صفحتي التي تظهر أصفاراً بعد publish_property_from_contract.

BEGIN;

CREATE OR REPLACE FUNCTION public._map_payload_to_property_type(
  p_type_raw text,
  p_pl jsonb
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_type text := lower(coalesce(nullif(trim(p_type_raw), ''), 'villa'));
BEGIN
  IF v_type LIKE 'ut\_%' ESCAPE '\' THEN
    v_type := case lower(trim(coalesce(
      p_pl -> 'listing_guidance' ->> 'property_type_group',
      p_pl -> 'listing_guidance' ->> 'group'
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
  RETURN v_type;
END;
$$;

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
  v_pl jsonb := '{}'::jsonb;
  v_type text;
  v_type_raw text;
  v_rega jsonb := '{}'::jsonb;
  v_permit record;
  v_offer_price numeric;
  v_preview_price numeric;
  v_preview_area numeric;
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

  v_pl := coalesce(
    public._jsonb_loose_to_object(req.payload_json),
    public._jsonb_loose_to_object(req.payload),
    '{}'::jsonb
  );

  v_type_raw := coalesce(nullif(trim(v_pl ->> 'type'), ''), 'villa');
  v_type := public._map_payload_to_property_type(v_type_raw, v_pl);

  BEGIN
    v_price := nullif(trim(v_pl ->> 'price'), '')::numeric;
  EXCEPTION WHEN OTHERS THEN
    v_price := NULL;
  END;
  v_price := coalesce(
    nullif(v_price, 0),
    nullif(req.price, 0),
    nullif(req.request_price, 0),
    nullif(req.preview_price, 0),
    0
  );

  BEGIN
    v_area := nullif(trim(v_pl ->> 'area'), '')::numeric;
  EXCEPTION WHEN OTHERS THEN
    v_area := NULL;
  END;
  v_area := coalesce(nullif(v_area, 0), 0);

  IF req.selected_offer_id IS NOT NULL THEN
    SELECT coalesce(nullif(lo.offer_amount, 0), nullif(lo.price, 0))
    INTO v_offer_price
    FROM public.listing_offers lo
    WHERE lo.id = req.selected_offer_id
    LIMIT 1;
    v_price := coalesce(nullif(v_offer_price, 0), v_price);
  END IF;

  IF req.preview_property_id IS NOT NULL THEN
    SELECT coalesce(nullif(p.price, 0), 0), coalesce(nullif(p.area, 0), 0)
    INTO v_preview_price, v_preview_area
    FROM public.properties p
    WHERE p.id = req.preview_property_id;
    v_price := coalesce(nullif(v_preview_price, 0), v_price);
    v_area := coalesce(nullif(v_preview_area, 0), v_area);
  END IF;

  v_lat := coalesce(req.lat, nullif(trim(v_pl ->> 'latitude'), '')::double precision);
  v_lng := coalesce(req.lng, nullif(trim(v_pl ->> 'longitude'), '')::double precision);

  SELECT lp.permit_no, lp.license_no, lp.authority_name, lp.broker_nid
  INTO v_permit
  FROM public.listing_permits lp
  WHERE lp.request_id = req.id
    AND lp.marketer_id = c.marketer_id
  ORDER BY lp.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_permit IS NOT NULL THEN
    v_rega := jsonb_strip_nulls(jsonb_build_object(
      'rega_ad_license_number', nullif(trim(v_permit.permit_no), ''),
      'fal_broker_license_number', nullif(trim(v_permit.license_no), ''),
      'authority_name', nullif(trim(v_permit.authority_name), ''),
      'broker_national_id', nullif(trim(v_permit.broker_nid), ''),
      'captured_at', now()
    ));
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
        published_at = coalesce(p.published_at, now()),
        price = CASE WHEN coalesce(p.price, 0) = 0 AND v_price > 0 THEN v_price ELSE p.price END,
        area = CASE WHEN coalesce(p.area, 0) = 0 AND v_area > 0 THEN v_area ELSE p.area END,
        rega_payload = coalesce(p.rega_payload, '{}'::jsonb) || v_rega,
        updated_at = now()
      WHERE p.id = v_prop;

      RETURN v_prop;
    END IF;
  END IF;

  IF req.preview_property_id IS NOT NULL THEN
    UPDATE public.properties p
    SET
      status = coalesce(nullif(trim(p.status::text), ''), 'published'),
      workflow_stage = 'published',
      published_by_marketer_id = coalesce(p.published_by_marketer_id, c.marketer_id),
      published_at = coalesce(p.published_at, now()),
      request_id = coalesce(p.request_id, req.id),
      title = coalesce(nullif(trim(p.title), ''), nullif(trim(req.title), ''), nullif(trim(v_pl ->> 'title'), ''), 'عقار'),
      description = coalesce(
        nullif(trim(p.description), ''),
        nullif(trim(v_pl ->> 'description'), ''),
        nullif(trim(req.title), ''),
        nullif(trim(req.description), ''),
        '—'
      ),
      city = coalesce(nullif(trim(p.city), ''), nullif(trim(req.city), ''), nullif(trim(v_pl ->> 'city'), ''), ''),
      type = CASE
        WHEN p.type IS NULL THEN v_type::property_type
        ELSE p.type
      END,
      price = CASE WHEN coalesce(p.price, 0) = 0 AND v_price > 0 THEN v_price ELSE p.price END,
      area = CASE WHEN coalesce(p.area, 0) = 0 AND v_area > 0 THEN v_area ELSE p.area END,
      currency = coalesce(nullif(trim(p.currency), ''), nullif(trim(v_pl ->> 'currency'), ''), 'SAR'),
      negotiable = coalesce(p.negotiable, (v_pl ->> 'negotiable')::boolean, false),
      is_auction = coalesce(p.is_auction, (v_pl ->> 'is_auction')::boolean, false),
      latitude = coalesce(p.latitude, v_lat),
      longitude = coalesce(p.longitude, v_lng),
      rega_payload = coalesce(p.rega_payload, '{}'::jsonb) || v_rega,
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
      published_at,
      rega_payload,
      created_at,
      updated_at
    )
    VALUES (
      req.owner_id,
      coalesce(nullif(trim(req.title), ''), nullif(trim(v_pl ->> 'title'), ''), 'عقار'),
      coalesce(
        nullif(trim(v_pl ->> 'description'), ''),
        nullif(trim(req.title), ''),
        nullif(trim(req.description), ''),
        '—'
      ),
      coalesce(nullif(trim(req.city), ''), nullif(trim(v_pl ->> 'city'), ''), ''),
      v_type::property_type,
      v_area,
      v_price,
      coalesce(nullif(trim(v_pl ->> 'currency'), ''), 'SAR'),
      coalesce((v_pl ->> 'negotiable')::boolean, false),
      coalesce((v_pl ->> 'is_auction')::boolean, false),
      0,
      'published',
      'published',
      v_lat,
      v_lng,
      req.id,
      c.marketer_id,
      now(),
      v_rega,
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
    published_at = coalesce(p.published_at, now()),
    price = CASE WHEN coalesce(p.price, 0) = 0 AND v_price > 0 THEN v_price ELSE p.price END,
    area = CASE WHEN coalesce(p.area, 0) = 0 AND v_area > 0 THEN v_area ELSE p.area END,
    rega_payload = coalesce(p.rega_payload, '{}'::jsonb) || v_rega,
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

-- إصلاح الإعلانات المنشورة سابقاً ببيانات ناقصة.
UPDATE public.properties p
SET
  price = CASE
    WHEN coalesce(p.price, 0) = 0 AND coalesce(src.resolved_price, 0) > 0
    THEN src.resolved_price
    ELSE p.price
  END,
  area = CASE
    WHEN coalesce(p.area, 0) = 0 AND coalesce(src.resolved_area, 0) > 0
    THEN src.resolved_area
    ELSE p.area
  END,
  published_at = coalesce(p.published_at, p.updated_at, now()),
  rega_payload = coalesce(p.rega_payload, '{}'::jsonb) || coalesce(src.rega_patch, '{}'::jsonb),
  updated_at = now()
FROM (
  SELECT
    p2.id AS property_id,
    coalesce(
      nullif(p2.price, 0),
      nullif(lr.preview_price, 0),
      nullif(lr.request_price, 0),
      nullif(lr.price, 0),
      nullif((coalesce(
        public._jsonb_loose_to_object(lr.payload_json),
        public._jsonb_loose_to_object(lr.payload),
        '{}'::jsonb
      ) ->> 'price')::numeric, 0),
      nullif(lo.offer_amount, 0),
      nullif(lo.price, 0),
      0
    ) AS resolved_price,
    coalesce(
      nullif(p2.area, 0),
      nullif((coalesce(
        public._jsonb_loose_to_object(lr.payload_json),
        public._jsonb_loose_to_object(lr.payload),
        '{}'::jsonb
      ) ->> 'area')::numeric, 0),
      0
    ) AS resolved_area,
    jsonb_strip_nulls(jsonb_build_object(
      'rega_ad_license_number', nullif(trim(lp.permit_no), ''),
      'fal_broker_license_number', nullif(trim(lp.license_no), ''),
      'authority_name', nullif(trim(lp.authority_name), '')
    )) AS rega_patch
  FROM public.properties p2
  LEFT JOIN public.listing_requests lr
    ON lr.id = p2.request_id OR lr.preview_property_id = p2.id
  LEFT JOIN public.listing_offers lo ON lo.id = lr.selected_offer_id
  LEFT JOIN LATERAL (
    SELECT lp.permit_no, lp.license_no, lp.authority_name
    FROM public.listing_permits lp
    WHERE lp.request_id = lr.id
    ORDER BY lp.created_at DESC NULLS LAST
    LIMIT 1
  ) lp ON true
  WHERE lower(trim(coalesce(p2.workflow_stage, p2.status::text, ''))) IN ('published', 'reserved')
     OR p2.published_by_marketer_id IS NOT NULL
) src
WHERE p.id = src.property_id
  AND (
    coalesce(p.price, 0) = 0
    OR coalesce(p.area, 0) = 0
    OR p.published_at IS NULL
    OR coalesce(p.rega_payload, '{}'::jsonb) = '{}'::jsonb
  );

REVOKE ALL ON FUNCTION public._map_payload_to_property_type(text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_property_from_contract(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_from_contract(uuid) TO authenticated;

COMMIT;
