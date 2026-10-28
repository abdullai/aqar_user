BEGIN;

CREATE OR REPLACE FUNCTION public.create_listing_request_preview_property()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payload jsonb;
  v_columns text[];
  v_title text;
  v_description text;
  v_city text;
  v_type text;
  v_type_sql text;
  v_status text;
  v_status_sql text;
  v_stage text;
  v_area numeric;
  v_price numeric;
  v_deed_date date;
  v_property_id uuid;
  v_insert_columns text;
  v_insert_values text;
  v_sql text;
BEGIN
  IF NEW.preview_property_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.id
  INTO v_property_id
  FROM public.properties p
  WHERE p.request_id = NEW.id
  ORDER BY p.created_at DESC
  LIMIT 1;

  IF v_property_id IS NOT NULL THEN
    UPDATE public.listing_requests
    SET preview_property_id = v_property_id
    WHERE id = NEW.id
      AND preview_property_id IS NULL;
    RETURN NEW;
  END IF;

  v_payload := coalesce(
    public._jsonb_loose_to_object(NEW.payload_json),
    public._jsonb_loose_to_object(NEW.payload),
    '{}'::jsonb
  );
  v_title := coalesce(
    nullif(trim(v_payload ->> 'title'), ''),
    nullif(trim(NEW.title), ''),
    'عقار'
  );
  v_description := coalesce(
    nullif(trim(v_payload ->> 'description'), ''),
    nullif(trim(NEW.description), ''),
    v_title
  );
  v_city := coalesce(
    nullif(trim(v_payload ->> 'city'), ''),
    nullif(trim(NEW.city), ''),
    'غير محدد'
  );
  v_stage := coalesce(nullif(trim(NEW.workflow_stage), ''), 'waiting_marketers');
  v_status := CASE WHEN lower(v_stage) = 'published' THEN 'published' ELSE 'draft' END;

  v_type := CASE
    WHEN lower(coalesce(v_payload ->> 'type', '')) LIKE 'ut\_%' ESCAPE '\' THEN
      CASE lower(coalesce(
        v_payload -> 'listing_guidance' ->> 'property_type_group',
        v_payload -> 'listing_guidance' ->> 'group',
        ''
      ))
        WHEN 'land' THEN 'land'
        WHEN 'residential' THEN 'apartment'
        WHEN 'commercial' THEN 'apartment'
        ELSE 'villa'
      END
    WHEN lower(coalesce(v_payload ->> 'type', '')) IN (
      'land', 'land_fenced', 'land_walled', 'farm', 'station'
    ) THEN 'land'
    WHEN lower(coalesce(v_payload ->> 'type', '')) IN (
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
    IF nullif(trim(v_payload ->> 'deed_date'), '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
      v_deed_date := (v_payload ->> 'deed_date')::date;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_deed_date := NULL;
  END;

  SELECT coalesce(array_agg(column_name), ARRAY[]::text[])
  INTO v_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'properties';

  IF NOT ARRAY[
    'owner_id', 'request_id', 'title', 'description',
    'city', 'status', 'workflow_stage'
  ]::text[] <@ v_columns THEN
    RAISE EXCEPTION 'public.properties is missing required preview columns';
  END IF;

  SELECT format_type(a.atttypid, a.atttypmod)
  INTO v_type_sql
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = 'public.properties'::regclass
    AND a.attname = 'type'
    AND NOT a.attisdropped;
  SELECT format_type(a.atttypid, a.atttypmod)
  INTO v_status_sql
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = 'public.properties'::regclass
    AND a.attname = 'status'
    AND NOT a.attisdropped;

  v_insert_columns :=
    'owner_id, request_id, title, description, city, status, workflow_stage';
  v_insert_values := format(
    '%L::uuid, %L::uuid, %L, %L, %L, %L::%s, %L',
    NEW.owner_id,
    NEW.id,
    v_title,
    v_description,
    v_city,
    v_status,
    v_status_sql,
    v_stage
  );

  IF 'type' = ANY(v_columns) THEN
    v_insert_columns := v_insert_columns || ', type';
    v_insert_values := v_insert_values || format(', %L::%s', v_type, v_type_sql);
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

  v_sql := format(
    'INSERT INTO public.properties (%s) VALUES (%s) RETURNING id',
    v_insert_columns,
    v_insert_values
  );
  EXECUTE v_sql INTO v_property_id;

  UPDATE public.listing_requests
  SET preview_property_id = v_property_id
  WHERE id = NEW.id
    AND preview_property_id IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_listing_request_preview_property
  ON public.listing_requests;

CREATE TRIGGER trg_create_listing_request_preview_property
AFTER INSERT ON public.listing_requests
FOR EACH ROW
EXECUTE FUNCTION public.create_listing_request_preview_property();

REVOKE ALL ON FUNCTION public.create_listing_request_preview_property() FROM PUBLIC;

COMMIT;
