BEGIN;

DO $$
DECLARE
  r record;
  v_payload jsonb;
  v_title text;
  v_description text;
  v_city text;
  v_type text;
  v_type_raw text;
  v_area numeric;
  v_price numeric;
  v_latitude double precision;
  v_longitude double precision;
  v_deed_date date;
  v_status text;
  v_stage text;
  v_property_id uuid;
  v_columns text[];
  v_insert_columns text;
  v_insert_values text;
  v_insert_sql text;
  v_has_request_updated_at boolean;
BEGIN
  SELECT coalesce(array_agg(column_name), ARRAY[]::text[])
  INTO v_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'properties';

  IF NOT ARRAY[
    'owner_id',
    'request_id',
    'title',
    'description',
    'city',
    'status',
    'workflow_stage'
  ]::text[] <@ v_columns THEN
    RAISE EXCEPTION 'public.properties is missing required columns for preview repair';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'listing_requests'
      AND column_name = 'updated_at'
  )
  INTO v_has_request_updated_at;

  FOR r IN
    SELECT
      lr.id,
      lr.owner_id,
      lr.title,
      lr.description,
      lr.city,
      lr.status,
      lr.workflow_stage,
      lr.payload_json,
      lr.payload
    FROM public.listing_requests lr
    WHERE lr.preview_property_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.properties p
        WHERE p.request_id = lr.id
      )
    ORDER BY lr.created_at
    FOR UPDATE
  LOOP
    v_payload := coalesce(
      public._jsonb_loose_to_object(r.payload_json),
      public._jsonb_loose_to_object(r.payload),
      '{}'::jsonb
    );
    v_title := coalesce(
      nullif(trim(v_payload ->> 'title'), ''),
      nullif(trim(r.title), ''),
      'عقار'
    );
    v_description := coalesce(
      nullif(trim(v_payload ->> 'description'), ''),
      nullif(trim(r.description), ''),
      v_title
    );
    v_city := coalesce(
      nullif(trim(v_payload ->> 'city'), ''),
      nullif(trim(r.city), ''),
      'غير محدد'
    );

    v_type_raw := lower(coalesce(nullif(trim(v_payload ->> 'type'), ''), 'villa'));
    v_type := CASE
      WHEN v_type_raw LIKE 'ut\_%' ESCAPE '\' THEN
        CASE lower(coalesce(
          v_payload -> 'listing_guidance' ->> 'property_type_group',
          v_payload -> 'listing_guidance' ->> 'group',
          ''
        ))
          WHEN 'land' THEN 'land'
          WHEN 'residential' THEN 'apartment'
          WHEN 'commercial' THEN 'apartment'
          WHEN 'project' THEN 'villa'
          ELSE 'villa'
        END
      WHEN v_type_raw IN ('land', 'land_fenced', 'land_walled', 'farm', 'station')
        THEN 'land'
      WHEN v_type_raw IN (
        'apartment', 'apartment_building', 'floor', 'room', 'suite',
        'residential_tower', 'hotel', 'warehouse', 'commercial_center',
        'commercial_market', 'office_tower', 'building', 'commercial_building',
        'office', 'shop', 'showroom'
      ) THEN 'apartment'
      ELSE 'villa'
    END;
    BEGIN
      v_area := nullif(trim(v_payload ->> 'area'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_area := NULL;
    END;
    BEGIN
      v_price := nullif(trim(v_payload ->> 'price'), '')::numeric;
    EXCEPTION WHEN OTHERS THEN
      v_price := NULL;
    END;
    BEGIN
      v_latitude := coalesce(
        nullif(trim(v_payload ->> 'latitude'), '')::double precision,
        nullif(trim(v_payload ->> 'lat'), '')::double precision
      );
    EXCEPTION WHEN OTHERS THEN
      v_latitude := NULL;
    END;
    BEGIN
      v_longitude := coalesce(
        nullif(trim(v_payload ->> 'longitude'), '')::double precision,
        nullif(trim(v_payload ->> 'lng'), '')::double precision
      );
    EXCEPTION WHEN OTHERS THEN
      v_longitude := NULL;
    END;
    BEGIN
      IF nullif(trim(v_payload ->> 'deed_date'), '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        v_deed_date := (v_payload ->> 'deed_date')::date;
      ELSE
        v_deed_date := NULL;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_deed_date := NULL;
    END;

    v_stage := coalesce(nullif(trim(r.workflow_stage), ''), 'waiting_marketers');
    v_status := 'draft';

    v_insert_columns := 'owner_id, request_id, title, description, city, status, workflow_stage';
    v_insert_values := format(
      '%L::uuid, %L::uuid, %L, %L, %L, %L, %L',
      r.owner_id,
      r.id,
      v_title,
      v_description,
      v_city,
      v_status,
      v_stage
    );

    IF 'type' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', type';
      v_insert_values := v_insert_values || format(', %L', v_type);
    END IF;
    IF 'area' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', area';
      v_insert_values := v_insert_values || CASE
        WHEN v_area IS NULL THEN ', NULL'
        ELSE format(', %L::numeric', v_area)
      END;
    END IF;
    IF 'price' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', price';
      v_insert_values := v_insert_values || CASE
        WHEN v_price IS NULL THEN ', NULL'
        ELSE format(', %L::numeric', v_price)
      END;
    END IF;
    IF 'currency' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', currency';
      v_insert_values := v_insert_values || format(
        ', %L',
        coalesce(nullif(trim(v_payload ->> 'currency'), ''), 'SAR')
      );
    END IF;
    IF 'negotiable' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', negotiable';
      v_insert_values := v_insert_values || format(
        ', %L::boolean',
        coalesce(lower(v_payload ->> 'negotiable') IN ('true', 't', '1', 'yes'), false)
      );
    END IF;
    IF 'is_auction' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', is_auction';
      v_insert_values := v_insert_values || format(
        ', %L::boolean',
        coalesce(lower(v_payload ->> 'is_auction') IN ('true', 't', '1', 'yes'), false)
      );
    END IF;
    IF 'views' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', views';
      v_insert_values := v_insert_values || ', 0';
    END IF;
    IF 'latitude' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', latitude';
      v_insert_values := v_insert_values || CASE
        WHEN v_latitude IS NULL THEN ', NULL'
        ELSE format(', %L::double precision', v_latitude)
      END;
    END IF;
    IF 'longitude' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', longitude';
      v_insert_values := v_insert_values || CASE
        WHEN v_longitude IS NULL THEN ', NULL'
        ELSE format(', %L::double precision', v_longitude)
      END;
    END IF;
    IF 'video_url' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', video_url';
      v_insert_values := v_insert_values || format(
        ', %L',
        coalesce(
          nullif(trim(v_payload ->> 'request_video_path'), ''),
          nullif(trim(v_payload ->> 'video_url'), ''),
          nullif(trim(v_payload ->> 'video_path'), '')
        )
      );
    END IF;
    IF 'virtual_tour_url' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', virtual_tour_url';
      v_insert_values := v_insert_values || format(
        ', %L',
        coalesce(
          nullif(trim(v_payload ->> 'virtual_tour_url'), ''),
          nullif(trim(v_payload ->> 'tour_url'), ''),
          nullif(trim(v_payload ->> 'virtualTourUrl'), '')
        )
      );
    END IF;
    IF 'listing_guidance' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', listing_guidance';
      v_insert_values := v_insert_values || format(
        ', %L::jsonb',
        CASE
          WHEN jsonb_typeof(v_payload -> 'listing_guidance') = 'object'
            THEN v_payload -> 'listing_guidance'
          ELSE '{}'::jsonb
        END
      );
    END IF;
    IF 'deed_number' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', deed_number';
      v_insert_values := v_insert_values || format(', %L', nullif(trim(v_payload ->> 'deed_number'), ''));
    END IF;
    IF 'deed_date' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', deed_date';
      v_insert_values := v_insert_values || CASE
        WHEN v_deed_date IS NULL THEN ', NULL'
        ELSE format(', %L::date', v_deed_date)
      END;
    END IF;
    IF 'deed_issuer' = ANY(v_columns) THEN
      v_insert_columns := v_insert_columns || ', deed_issuer';
      v_insert_values := v_insert_values || format(', %L', nullif(trim(v_payload ->> 'deed_issuer'), ''));
    END IF;

    v_insert_sql := format(
      'INSERT INTO public.properties (%s) VALUES (%s) RETURNING id',
      v_insert_columns,
      v_insert_values
    );
    EXECUTE v_insert_sql INTO v_property_id;

    IF v_has_request_updated_at THEN
      UPDATE public.listing_requests
      SET preview_property_id = v_property_id,
          updated_at = now()
      WHERE id = r.id
        AND preview_property_id IS NULL;
    ELSE
      UPDATE public.listing_requests
      SET preview_property_id = v_property_id
      WHERE id = r.id
        AND preview_property_id IS NULL;
    END IF;
  END LOOP;
END;
$$;

COMMIT;
