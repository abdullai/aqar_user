BEGIN;

CREATE OR REPLACE FUNCTION public.sync_listing_request_data_to_property()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request public.listing_requests%ROWTYPE;
  v_payload jsonb := '{}'::jsonb;
  v_request_guidance jsonb := '{}'::jsonb;
  v_guidance jsonb := '{}'::jsonb;
  v_images jsonb := '[]'::jsonb;
  v_item jsonb;
  v_path text;
  v_first_image text;
  v_video text;
  v_tour text;
  v_deed_date date;
  v_sort_order bigint;
BEGIN
  SELECT lr.*
  INTO v_request
  FROM public.listing_requests lr
  WHERE (NEW.request_id IS NOT NULL AND lr.id = NEW.request_id)
     OR lr.preview_property_id = NEW.id
  ORDER BY CASE WHEN lr.id = NEW.request_id THEN 0 ELSE 1 END
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  v_payload := coalesce(
    public._jsonb_loose_to_object(v_request.payload_json),
    public._jsonb_loose_to_object(v_request.payload),
    '{}'::jsonb
  );
  v_request_guidance := CASE
    WHEN jsonb_typeof(v_payload -> 'listing_guidance') = 'object'
    THEN v_payload -> 'listing_guidance'
    ELSE '{}'::jsonb
  END;
  v_guidance := CASE
    WHEN jsonb_typeof(NEW.listing_guidance) = 'object'
    THEN NEW.listing_guidance
    ELSE '{}'::jsonb
  END || v_request_guidance;

  v_images := coalesce(
    nullif(v_payload -> 'request_image_paths', '[]'::jsonb),
    nullif(v_payload -> 'image_paths', '[]'::jsonb),
    nullif(v_payload -> 'image_urls', '[]'::jsonb),
    nullif(v_payload -> 'images', '[]'::jsonb),
    nullif(v_payload -> 'photos', '[]'::jsonb),
    nullif(v_payload -> 'gallery', '[]'::jsonb),
    nullif(v_request_guidance -> 'image_paths', '[]'::jsonb),
    '[]'::jsonb
  );
  IF jsonb_typeof(v_images) = 'string' THEN
    BEGIN
      v_images := (v_images #>> '{}')::jsonb;
    EXCEPTION WHEN OTHERS THEN
      v_images := '[]'::jsonb;
    END;
  END IF;
  IF jsonb_typeof(v_images) <> 'array' THEN
    v_images := '[]'::jsonb;
  END IF;

  v_video := coalesce(
    nullif(trim(v_payload ->> 'request_video_path'), ''),
    nullif(trim(v_payload ->> 'video_url'), ''),
    nullif(trim(v_payload ->> 'video_path'), ''),
    nullif(trim(v_request_guidance ->> 'video_path'), ''),
    nullif(trim(v_request_guidance ->> 'video_url'), '')
  );
  v_tour := coalesce(
    nullif(trim(v_payload ->> 'virtual_tour_url'), ''),
    nullif(trim(v_payload ->> 'tour_url'), ''),
    nullif(trim(v_payload ->> 'virtualTourUrl'), ''),
    nullif(trim(v_request_guidance ->> 'virtual_tour_url'), '')
  );

  IF nullif(trim(v_payload ->> 'deed_date'), '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    BEGIN
      v_deed_date := (v_payload ->> 'deed_date')::date;
    EXCEPTION WHEN OTHERS THEN
      v_deed_date := NULL;
    END;
  END IF;

  FOR v_item, v_sort_order IN
    SELECT item.value, item.ordinality
    FROM jsonb_array_elements(v_images) WITH ORDINALITY AS item(value, ordinality)
  LOOP
    v_path := CASE
      WHEN jsonb_typeof(v_item) = 'object'
      THEN coalesce(
        v_item ->> 'path',
        v_item ->> 'url',
        v_item ->> 'file_name',
        ''
      )
      ELSE coalesce(v_item #>> '{}', '')
    END;
    v_path := nullif(trim(v_path), '');
    IF v_path IS NULL THEN
      CONTINUE;
    END IF;

    IF v_first_image IS NULL THEN
      v_first_image := v_path;
    END IF;

    INSERT INTO public.property_images (
      property_id,
      path,
      file_name,
      sort_order
    )
    SELECT
      NEW.id,
      v_path,
      regexp_replace(v_path, '^.*/', ''),
      (v_sort_order - 1)::integer
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.property_images pi
      WHERE pi.property_id = NEW.id
        AND lower(trim(coalesce(pi.path, pi.file_name, ''))) =
            lower(trim(v_path))
    );
  END LOOP;

  UPDATE public.properties p
  SET
    deed_number = coalesce(
      nullif(trim(p.deed_number), ''),
      nullif(trim(v_payload ->> 'deed_number'), '')
    ),
    deed_date = coalesce(p.deed_date, v_deed_date),
    deed_issuer = coalesce(
      nullif(trim(p.deed_issuer), ''),
      nullif(trim(v_payload ->> 'deed_issuer'), '')
    ),
    image_url = coalesce(v_first_image, nullif(trim(p.image_url), '')),
    video_url = coalesce(nullif(trim(p.video_url), ''), v_video),
    virtual_tour_url = coalesce(
      nullif(trim(p.virtual_tour_url), ''),
      v_tour
    ),
    listing_guidance = CASE
      WHEN v_first_image IS NOT NULL
      THEN jsonb_set(v_guidance, '{image_paths}', v_images, true)
      ELSE v_guidance
    END,
    default_cover_used = CASE
      WHEN v_first_image IS NOT NULL
        OR v_video IS NOT NULL
        OR v_tour IS NOT NULL
      THEN false
      ELSE p.default_cover_used
    END,
    updated_at = now()
  WHERE p.id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_listing_request_data_to_property
  ON public.properties;

CREATE TRIGGER trg_sync_listing_request_data_to_property
AFTER INSERT OR UPDATE OF request_id, status, workflow_stage
ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.sync_listing_request_data_to_property();

-- Repair existing preview and published properties linked to a request.
UPDATE public.properties p
SET request_id = coalesce(p.request_id, lr.id)
FROM public.listing_requests lr
WHERE lr.id = p.request_id
   OR lr.preview_property_id = p.id;

REVOKE ALL ON FUNCTION public.sync_listing_request_data_to_property() FROM PUBLIC;

COMMIT;
