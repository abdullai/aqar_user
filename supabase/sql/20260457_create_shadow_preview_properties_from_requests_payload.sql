-- =============================================================================
-- Create shadow preview properties for legacy listing_requests with no linked
-- property at all (no preview_property_id and no properties.request_id).
--
-- Goal:
--   - Enable cards/details image-video-data rendering for old requests.
--   - Keep these rows out of public home feed by setting non-public status/stage.
--
-- Notes:
--   - Requires public._jsonb_loose_to_object(...) from 20260456.
--   - Some Supabase projects do not have every optional properties column
--     (e.g. purpose). This script only inserts columns that actually exist.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  r record;

  v_has_owner_id boolean;
  v_has_request_id boolean;
  v_has_title boolean;
  v_has_description boolean;
  v_has_city boolean;
  v_has_status boolean;
  v_has_workflow_stage boolean;

  v_has_location boolean;
  v_has_address_line boolean;
  v_has_type boolean;
  v_has_purpose boolean;
  v_has_area boolean;
  v_has_price boolean;
  v_has_currency boolean;
  v_has_negotiable boolean;
  v_has_is_auction boolean;
  v_has_current_bid boolean;
  v_has_latitude boolean;
  v_has_longitude boolean;
  v_has_video_url boolean;
  v_has_listing_guidance boolean;
  v_lg_not_null boolean;
  v_lg_has_default boolean;

  v_has_lr_preview boolean;
  v_has_lr_updated_at boolean;

  v_cols text := '';
  v_vals text := '';
  v_sql text;

  v_new_id uuid;

  v_title text;
  v_description text;
  v_city text;
  v_location text;
  v_address_line text;
  v_type text;
  v_type_raw text;
  v_purpose text;
  v_area numeric;
  v_price numeric;
  v_currency text;
  v_negotiable boolean;
  v_is_auction boolean;
  v_current_bid numeric;
  v_latitude double precision;
  v_longitude double precision;
  v_video_url text;
  v_listing_guidance jsonb;
  v_workflow_stage text;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'owner_id'
  ) INTO v_has_owner_id;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'request_id'
  ) INTO v_has_request_id;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'title'
  ) INTO v_has_title;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'description'
  ) INTO v_has_description;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'city'
  ) INTO v_has_city;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'status'
  ) INTO v_has_status;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'workflow_stage'
  ) INTO v_has_workflow_stage;

  IF NOT (v_has_owner_id AND v_has_request_id AND v_has_title AND v_has_description AND v_has_city AND v_has_status AND v_has_workflow_stage) THEN
    RAISE EXCEPTION 'public.properties is missing required columns for shadow inserts (need owner_id, request_id, title, description, city, status, workflow_stage)';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'location'
  ) INTO v_has_location;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'address_line'
  ) INTO v_has_address_line;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'type'
  ) INTO v_has_type;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'purpose'
  ) INTO v_has_purpose;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'area'
  ) INTO v_has_area;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'price'
  ) INTO v_has_price;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'currency'
  ) INTO v_has_currency;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'negotiable'
  ) INTO v_has_negotiable;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'is_auction'
  ) INTO v_has_is_auction;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'current_bid'
  ) INTO v_has_current_bid;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'latitude'
  ) INTO v_has_latitude;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'longitude'
  ) INTO v_has_longitude;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'video_url'
  ) INTO v_has_video_url;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'properties' AND c.column_name = 'listing_guidance'
  ) INTO v_has_listing_guidance;

  IF v_has_listing_guidance THEN
    SELECT c.is_nullable = 'NO'
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = 'properties'
      AND c.column_name = 'listing_guidance'
    INTO v_lg_not_null;

    SELECT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_attribute a
      JOIN pg_catalog.pg_class rel ON rel.oid = a.attrelid
      JOIN pg_catalog.pg_namespace nsp ON nsp.oid = rel.relnamespace
      LEFT JOIN pg_catalog.pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
      WHERE nsp.nspname = 'public'
        AND rel.relname = 'properties'
        AND a.attname = 'listing_guidance'
        AND NOT a.attisdropped
        AND a.attnum > 0
        AND ad.adbin IS NOT NULL
    ) INTO v_lg_has_default;
  ELSE
    v_lg_not_null := false;
    v_lg_has_default := false;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'listing_requests' AND c.column_name = 'preview_property_id'
  ) INTO v_has_lr_preview;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_schema = 'public' AND c.table_name = 'listing_requests' AND c.column_name = 'updated_at'
  ) INTO v_has_lr_updated_at;

  IF NOT v_has_lr_preview THEN
    RAISE EXCEPTION 'public.listing_requests.preview_property_id is missing';
  END IF;

  FOR r IN
    SELECT
      lr.id AS request_id,
      lr.owner_id,
      lr.title AS req_title,
      lr.description AS req_description,
      lr.city AS req_city,
      lr.workflow_stage AS req_workflow_stage,
      coalesce(
        public._jsonb_loose_to_object(lr.payload_json),
        public._jsonb_loose_to_object(lr.payload),
        '{}'::jsonb
      ) AS pl
    FROM public.listing_requests lr
    WHERE lr.preview_property_id IS NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.properties p
        WHERE p.request_id = lr.id
      )
  LOOP
    v_title := coalesce(nullif(trim(r.pl ->> 'title'), ''), nullif(trim(r.req_title), ''), 'طلب بدون عنوان');
    v_description := coalesce(nullif(trim(r.pl ->> 'description'), ''), r.req_description);
    v_city := coalesce(nullif(trim(r.pl ->> 'city'), ''), nullif(trim(r.req_city), ''), 'غير محدد');
    v_location := nullif(trim(r.pl ->> 'location'), '');
    v_address_line := nullif(trim(r.pl ->> 'address_line'), '');
    v_type_raw := coalesce(nullif(trim(r.pl ->> 'type'), ''), 'villa');
    v_type := lower(v_type_raw);

    -- `properties.type` is often a legacy enum with only a small set of labels.
    -- The app can store richer catalog codes (e.g. `floor`) which must be mapped
    -- down to a DB-safe value for shadow preview inserts.
    IF v_type LIKE 'ut\_%' ESCAPE '\' THEN
      v_type := case lower(trim(coalesce(r.pl -> 'listing_guidance' ->> 'property_type_group', r.pl -> 'listing_guidance' ->> 'group')))
        when 'land' then 'land'
        when 'commercial' then 'apartment'
        when 'project' then 'villa'
        when 'residential' then 'apartment'
        else 'villa'
      end;
    ELSIF v_type in (
      'land','land_fenced','land_walled','farm','station'
    ) THEN
      v_type := 'land';
    ELSIF v_type in (
      'villa','rest_house','chalet','traditional_house','palace'
    ) THEN
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
    v_purpose := coalesce(nullif(trim(r.pl ->> 'purpose'), ''), 'sale');

    BEGIN
      v_area := nullif(trim(r.pl ->> 'area'), '')::numeric;
    EXCEPTION WHEN others THEN
      v_area := NULL;
    END;

    BEGIN
      v_price := nullif(trim(r.pl ->> 'price'), '')::numeric;
    EXCEPTION WHEN others THEN
      v_price := NULL;
    END;

    v_currency := coalesce(nullif(trim(r.pl ->> 'currency'), ''), 'SAR');

    BEGIN
      v_negotiable := coalesce((r.pl ->> 'negotiable')::boolean, false);
    EXCEPTION WHEN others THEN
      v_negotiable := false;
    END;

    BEGIN
      v_is_auction := coalesce((r.pl ->> 'is_auction')::boolean, false);
    EXCEPTION WHEN others THEN
      v_is_auction := false;
    END;

    BEGIN
      v_current_bid := nullif(trim(r.pl ->> 'current_bid'), '')::numeric;
    EXCEPTION WHEN others THEN
      v_current_bid := NULL;
    END;

    BEGIN
      v_latitude := nullif(trim(r.pl ->> 'latitude'), '')::double precision;
    EXCEPTION WHEN others THEN
      v_latitude := NULL;
    END;

    BEGIN
      v_longitude := nullif(trim(r.pl ->> 'longitude'), '')::double precision;
    EXCEPTION WHEN others THEN
      v_longitude := NULL;
    END;

    v_video_url := nullif(trim(r.pl ->> 'video_url'), '');

    IF jsonb_typeof(r.pl -> 'listing_guidance') = 'object' THEN
      v_listing_guidance := r.pl -> 'listing_guidance';
    ELSE
      v_listing_guidance := NULL;
    END IF;

    IF v_has_listing_guidance AND v_lg_not_null AND v_listing_guidance IS NULL THEN
      v_listing_guidance := '{}'::jsonb;
    END IF;

    v_workflow_stage := coalesce(nullif(trim(r.req_workflow_stage), ''), 'waiting_marketers');

    v_cols := 'owner_id, request_id, title, description, city';
    v_vals := format(
      '%s::uuid, %s::uuid, %s, %s, %s',
      quote_literal(r.owner_id::text),
      quote_literal(r.request_id::text),
      quote_literal(v_title),
      quote_literal(v_description),
      quote_literal(v_city)
    );

    IF v_has_location THEN
      v_cols := v_cols || ', location';
      v_vals := v_vals || ', ' || coalesce(quote_literal(v_location), 'NULL');
    END IF;

    IF v_has_address_line THEN
      v_cols := v_cols || ', address_line';
      v_vals := v_vals || ', ' || coalesce(quote_literal(v_address_line), 'NULL');
    END IF;

    IF v_has_type THEN
      v_cols := v_cols || ', type';
      v_vals := v_vals || ', ' || quote_literal(v_type);
    END IF;

    IF v_has_purpose THEN
      v_cols := v_cols || ', purpose';
      v_vals := v_vals || ', ' || quote_literal(v_purpose);
    END IF;

    IF v_has_area THEN
      v_cols := v_cols || ', area';
      v_vals := v_vals || ', ' || CASE
        WHEN v_area IS NULL THEN 'NULL'
        ELSE quote_literal(v_area::text) || '::numeric'
      END;
    END IF;

    IF v_has_price THEN
      v_cols := v_cols || ', price';
      v_vals := v_vals || ', ' || CASE
        WHEN v_price IS NULL THEN 'NULL'
        ELSE quote_literal(v_price::text) || '::numeric'
      END;
    END IF;

    IF v_has_currency THEN
      v_cols := v_cols || ', currency';
      v_vals := v_vals || ', ' || quote_literal(v_currency);
    END IF;

    IF v_has_negotiable THEN
      v_cols := v_cols || ', negotiable';
      v_vals := v_vals || ', ' || quote_literal(v_negotiable::text) || '::boolean';
    END IF;

    IF v_has_is_auction THEN
      v_cols := v_cols || ', is_auction';
      v_vals := v_vals || ', ' || quote_literal(v_is_auction::text) || '::boolean';
    END IF;

    IF v_has_current_bid THEN
      v_cols := v_cols || ', current_bid';
      v_vals := v_vals || ', ' || CASE
        WHEN v_current_bid IS NULL THEN 'NULL'
        ELSE quote_literal(v_current_bid::text) || '::numeric'
      END;
    END IF;

    IF v_has_latitude THEN
      v_cols := v_cols || ', latitude';
      v_vals := v_vals || ', ' || CASE
        WHEN v_latitude IS NULL THEN 'NULL'
        ELSE quote_literal(v_latitude::text) || '::double precision'
      END;
    END IF;

    IF v_has_longitude THEN
      v_cols := v_cols || ', longitude';
      v_vals := v_vals || ', ' || CASE
        WHEN v_longitude IS NULL THEN 'NULL'
        ELSE quote_literal(v_longitude::text) || '::double precision'
      END;
    END IF;

    IF v_has_video_url THEN
      v_cols := v_cols || ', video_url';
      v_vals := v_vals || ', ' || coalesce(quote_literal(v_video_url), 'NULL');
    END IF;

    IF v_has_listing_guidance THEN
      v_cols := v_cols || ', listing_guidance';
      v_vals := v_vals || ', ' || CASE
        WHEN v_listing_guidance IS NULL THEN 'NULL'
        ELSE quote_literal(v_listing_guidance::text) || '::jsonb'
      END;
    END IF;

    v_cols := v_cols || ', status, workflow_stage';
    v_vals := v_vals || ', ' || quote_literal('draft') || ', ' || quote_literal(v_workflow_stage);

    v_sql := 'insert into public.properties (' || v_cols || ') values (' || v_vals || ') returning id';
    EXECUTE v_sql INTO v_new_id;

    IF v_has_lr_updated_at THEN
      EXECUTE
        'update public.listing_requests set preview_property_id = $1, updated_at = now() where id = $2 and preview_property_id is null'
      USING v_new_id, r.request_id;
    ELSE
      EXECUTE
        'update public.listing_requests set preview_property_id = $1 where id = $2 and preview_property_id is null'
      USING v_new_id, r.request_id;
    END IF;
  END LOOP;
END $$;

COMMIT;

-- Optional check:
-- select count(*) as linked_after_shadow from public.listing_requests where preview_property_id is not null;
