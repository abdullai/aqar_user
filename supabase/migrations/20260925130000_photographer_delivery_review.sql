-- Keep photographer deliveries private to the shoot request until the listing
-- owner or the authorized publisher reviews and approves them.
BEGIN;

ALTER TABLE public.photo_shoot_requests
  ADD COLUMN IF NOT EXISTS property_owner_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS owner_media_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS owner_media_consent_at timestamptz,
  ADD COLUMN IF NOT EXISTS owner_cover_change_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS owner_replace_media_consent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS owner_media_consent_scope jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS delivery_review_status text NOT NULL DEFAULT 'not_submitted',
  ADD COLUMN IF NOT EXISTS delivery_revision_note text;

UPDATE public.photo_shoot_requests r
SET property_owner_id = p.owner_id
FROM public.properties p
WHERE r.property_id = p.id
  AND r.property_owner_id IS NULL;

UPDATE public.photo_shoot_requests
SET owner_media_consent_at = coalesce(created_at, now()),
    owner_media_consent_scope = jsonb_build_object(
      'version', 1,
      'purpose', 'legacy_accepted_property_shoot',
      'cover_change', false,
      'replace_existing_media', false
    )
WHERE owner_media_consent IS TRUE
  AND owner_media_consent_at IS NULL;

UPDATE public.photo_shoot_requests
SET owner_media_consent_scope = jsonb_build_object(
  'version', 1,
  'purpose', 'legacy_request_requires_explicit_owner_consent',
  'cover_change', false,
  'replace_existing_media', false
)
WHERE owner_media_consent IS FALSE
  AND owner_media_consent_scope = '{}'::jsonb;

UPDATE public.photo_shoot_requests
SET delivery_review_status = 'approved'
WHERE status = 'delivered'
  AND delivery_review_status = 'not_submitted';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.photo_shoot_requests'::regclass
      AND conname = 'photo_shoot_delivery_review_status_check'
  ) THEN
    ALTER TABLE public.photo_shoot_requests
      ADD CONSTRAINT photo_shoot_delivery_review_status_check
      CHECK (delivery_review_status IN (
        'not_submitted', 'pending_review', 'revision_requested', 'approved'
      ));
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'photo_shoot_requests'
     ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.photo_shoot_requests;
  END IF;
END;
$$;

DROP POLICY IF EXISTS photo_shoot_select ON public.photo_shoot_requests;
CREATE POLICY photo_shoot_select ON public.photo_shoot_requests
  FOR SELECT TO authenticated
  USING (
    requester_id = auth.uid()
    OR photographer_id = auth.uid()
    OR property_owner_id = auth.uid()
    OR public.is_platform_staff()
  );

DROP FUNCTION IF EXISTS public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz,
  numeric, integer, integer, boolean
);

CREATE OR REPLACE FUNCTION public.create_photo_shoot_request(
  p_photographer_id uuid,
  p_property_id uuid DEFAULT NULL,
  p_listing_request_id uuid DEFAULT NULL,
  p_shoot_kinds text[] DEFAULT ARRAY['photos']::text[],
  p_location_text text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_preferred_at timestamptz DEFAULT NULL,
  p_quoted_amount_sar numeric DEFAULT NULL,
  p_max_photos int DEFAULT 30,
  p_max_videos int DEFAULT 1,
  p_include_tour boolean DEFAULT false,
  p_owner_media_consent boolean DEFAULT false,
  p_owner_cover_change_consent boolean DEFAULT false,
  p_owner_replace_media_consent boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_ok boolean;
  v_owner uuid;
  v_publisher uuid;
  g jsonb;
  kinds text[];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_photographer_id IS NULL THEN RAISE EXCEPTION 'photographer_required'; END IF;
  IF p_property_id IS NULL THEN RAISE EXCEPTION 'property_required'; END IF;
  IF p_photographer_id = uid THEN RAISE EXCEPTION 'cannot_book_self'; END IF;
  IF coalesce(p_owner_media_consent, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'owner_media_consent_required';
  END IF;

  SELECT owner_id, published_by_marketer_id, coalesce(listing_guidance, '{}'::jsonb)
    INTO v_owner, v_publisher, g
  FROM public.properties
  WHERE id = p_property_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;
  IF uid IS DISTINCT FROM v_owner AND uid IS DISTINCT FROM v_publisher THEN
    RAISE EXCEPTION 'not_listing_owner_or_publisher';
  END IF;

  SELECT true INTO v_ok
  FROM public.photographer_profiles
  WHERE user_id = p_photographer_id AND status = 'verified';
  IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'photographer_not_verified'; END IF;
  IF NOT public.user_has_active_photographer_subscription(p_photographer_id) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;

  kinds := coalesce(p_shoot_kinds, ARRAY['photos']::text[]);
  kinds := ARRAY(
    SELECT CASE WHEN x IN ('tour_3d', '3d', 'virtual_tour') THEN 'tour' ELSE x END
    FROM unnest(kinds) x
  );

  INSERT INTO public.photo_shoot_requests (
    listing_request_id, property_id, property_owner_id, requester_id,
    photographer_id, shoot_kinds, location_text, latitude, longitude,
    preferred_at, status, quoted_amount_sar, max_photos, max_videos,
    include_tour, owner_media_consent, owner_cover_change_consent,
    owner_replace_media_consent, owner_media_consent_at,
    owner_media_consent_scope
  ) VALUES (
    p_listing_request_id, p_property_id, v_owner, uid, p_photographer_id,
    kinds, nullif(trim(p_location_text), ''), p_latitude, p_longitude,
    p_preferred_at, 'pending', p_quoted_amount_sar,
    least(greatest(coalesce(p_max_photos, 30), 1), 80),
    least(greatest(coalesce(p_max_videos, 1), 0), 3),
    coalesce(p_include_tour, 'tour' = ANY (kinds)),
    true, coalesce(p_owner_cover_change_consent, false),
    coalesce(p_owner_replace_media_consent, false), now(),
    jsonb_build_object(
      'version', 1,
      'purpose', 'photographer_media_for_this_property',
      'cover_change', coalesce(p_owner_cover_change_consent, false),
      'replace_existing_media', coalesce(p_owner_replace_media_consent, false),
      'granted_by', uid
    )
  )
  RETURNING id INTO v_id;

  g := jsonb_set(g, '{photo_shoot_status}', '"pending"', true);
  g := jsonb_set(g, '{photo_shoot_request_id}', to_jsonb(v_id), true);
  UPDATE public.properties SET listing_guidance = g WHERE id = p_property_id;

  PERFORM public.workflow_create_notification(
    p_photographer_id,
    'photo_shoot_requested',
    'طلب تصوير جديد',
    'وصلك طلب تصوير مرتبط بإعلان. اقبله أو ارفضه مع سبب خلال 24 ساعة.',
    'photo_shoot',
    v_id,
    jsonb_build_object(
      'title_ar', 'طلب تصوير جديد',
      'title_en', 'New photo-shoot request',
      'body_ar', 'وصلك طلب تصوير مرتبط بإعلان. اقبله أو ارفضه مع سبب خلال 24 ساعة.',
      'body_en', 'You have a property shoot request. Accept or decline within 24 hours.',
      'deep_route', 'photographer_hub',
      'shoot_request_id', v_id,
      'property_id', p_property_id,
      'quoted_amount_sar', p_quoted_amount_sar
    )
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz,
  numeric, integer, integer, boolean, boolean, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz,
  numeric, integer, integer, boolean, boolean, boolean, boolean
) TO authenticated;

CREATE OR REPLACE FUNCTION public.owner_grant_photo_shoot_media_consent(
  p_request_id uuid,
  p_allow_cover_change boolean DEFAULT false,
  p_allow_replace_existing_media boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO req
  FROM public.photo_shoot_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF uid IS DISTINCT FROM req.requester_id
     AND uid IS DISTINCT FROM req.property_owner_id THEN
    RAISE EXCEPTION 'not_listing_owner_or_requester';
  END IF;
  IF req.status NOT IN ('accepted', 'in_progress') THEN
    RAISE EXCEPTION 'shoot_not_active';
  END IF;

  UPDATE public.photo_shoot_requests
  SET owner_media_consent = true,
      owner_media_consent_at = now(),
      owner_cover_change_consent = coalesce(p_allow_cover_change, false),
      owner_replace_media_consent = coalesce(p_allow_replace_existing_media, false),
      owner_media_consent_scope = jsonb_build_object(
        'version', 1,
        'purpose', 'photographer_media_for_this_property',
        'property_id', req.property_id,
        'cover_change', coalesce(p_allow_cover_change, false),
        'replace_existing_media', coalesce(p_allow_replace_existing_media, false),
        'granted_by', uid,
        'granted_at', now()
      ),
      updated_at = now()
  WHERE id = p_request_id;

  PERFORM public.workflow_create_notification(
    req.photographer_id,
    'photo_shoot_media_authorized',
    'اكتمل إذن وسائط التصوير',
    'أذن مالك الإعلان بإضافة الوسائط ضمن الشروط المحددة.',
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', 'اكتمل إذن وسائط التصوير',
      'title_en', 'Photographer media consent granted',
      'body_ar', 'أذن مالك الإعلان بإضافة الوسائط ضمن الشروط المحددة.',
      'body_en', 'The listing owner authorized media delivery under the selected terms.',
      'deep_route', 'photographer_hub',
      'property_id', req.property_id,
      'shoot_request_id', p_request_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_grant_photo_shoot_media_consent(
  uuid, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_grant_photo_shoot_media_consent(
  uuid, boolean, boolean
) TO authenticated;

CREATE OR REPLACE FUNCTION public.user_has_active_photographer_subscription(
  p_user_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.user_id = p_user_id
      AND s.service_audience = 'photographer'
      AND coalesce(s.is_trial, false) = false
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.starts_at, now()) <= now()
      AND (
        coalesce(s.is_lifetime, false)
        OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
      )
      AND lower(trim(p.user_type)) = 'photographer'
  );
$$;

REVOKE ALL ON FUNCTION public.user_has_active_photographer_subscription(uuid)
  FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.list_verified_photographers();
CREATE OR REPLACE FUNCTION public.list_verified_photographers()
RETURNS TABLE (
  user_id uuid,
  status text,
  display_name text,
  bio text,
  city text,
  photo_rate_sar numeric,
  video_rate_sar numeric,
  tour_rate_sar numeric,
  rating_avg numeric,
  rating_count int,
  portfolio jsonb,
  latitude double precision,
  longitude double precision
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    p.user_id, p.status, p.display_name, p.bio, p.city,
    p.photo_rate_sar, p.video_rate_sar, p.tour_rate_sar,
    p.rating_avg, p.rating_count, p.portfolio,
    p.latitude, p.longitude
  FROM public.photographer_profiles p
  WHERE p.status = 'verified'
    AND public.user_has_active_photographer_subscription(p.user_id)
  ORDER BY p.rating_avg DESC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.list_verified_photographers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_verified_photographers() TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_photographer_subscription_for_shoot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() = NEW.photographer_id
     AND NEW.status IN ('accepted', 'in_progress', 'delivered')
     AND NOT public.user_has_active_photographer_subscription(NEW.photographer_id) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_photographer_subscription_for_shoot
  ON public.photo_shoot_requests;
CREATE TRIGGER tr_photographer_subscription_for_shoot
  BEFORE INSERT OR UPDATE OF status ON public.photo_shoot_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_photographer_subscription_for_shoot();

CREATE OR REPLACE FUNCTION public.photographer_submit_delivery_for_review(
  p_request_id uuid,
  p_image_paths text[] DEFAULT '{}'::text[],
  p_video_path text DEFAULT NULL,
  p_in_app_tour jsonb DEFAULT NULL,
  p_cover_image_path text DEFAULT NULL,
  p_technical_notes text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_images text[] := coalesce(p_image_paths, '{}'::text[]);
  v_video text := nullif(trim(coalesce(p_video_path, '')), '');
  v_photographer_name text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.user_has_active_photographer_subscription(uid) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;

  SELECT * INTO req
  FROM public.photo_shoot_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF req.photographer_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_photographer'; END IF;
  IF req.status NOT IN ('accepted', 'in_progress') THEN
    RAISE EXCEPTION 'not_accepted';
  END IF;
  IF req.property_id IS NULL THEN RAISE EXCEPTION 'property_required'; END IF;
  IF req.owner_media_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'owner_media_consent_required';
  END IF;
  IF coalesce(array_length(v_images, 1), 0) > coalesce(req.max_photos, 30) THEN
    RAISE EXCEPTION 'photo_limit_exceeded';
  END IF;
  IF v_video IS NOT NULL AND coalesce(req.max_videos, 1) < 1 THEN
    RAISE EXCEPTION 'video_not_allowed';
  END IF;
  IF p_in_app_tour IS NOT NULL AND coalesce(req.include_tour, false) IS NOT TRUE
     AND NOT ('tour' = ANY (coalesce(req.shoot_kinds, ARRAY[]::text[]))) THEN
    RAISE EXCEPTION 'tour_not_requested';
  END IF;

  SELECT coalesce(display_name, '') INTO v_photographer_name
  FROM public.photographer_profiles
  WHERE user_id = uid;

  UPDATE public.photo_shoot_requests
  SET
    delivery_review_status = 'pending_review',
    delivery_revision_note = NULL,
    cover_image_path = coalesce(nullif(trim(p_cover_image_path), ''), v_images[1]),
    technical_notes = nullif(trim(p_technical_notes), ''),
    delivered_media = jsonb_build_object(
      'image_paths', to_jsonb(v_images),
      'video_path', v_video,
      'in_app_tour', p_in_app_tour,
      'photographer_id', uid,
      'photographer_name', v_photographer_name,
      'property_id', req.property_id,
      'submitted_at', now()
    ),
    updated_at = now()
  WHERE id = p_request_id;

  UPDATE public.properties
  SET listing_guidance = jsonb_set(
    jsonb_set(
      coalesce(listing_guidance, '{}'::jsonb),
      '{photo_shoot_status}',
      '"pending_review"',
      true
    ),
    '{photo_shoot_request_id}',
    to_jsonb(p_request_id),
    true
  )
  WHERE id = req.property_id;

  PERFORM public.workflow_create_notification(
    req.requester_id,
    'photo_shoot_delivered',
    'وسائط المصور بانتظار موافقتك',
    'راجع الصور والوسائط ثم وافق على إضافتها للإعلان أو اطلب تعديلها.',
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', 'وسائط المصور بانتظار موافقتك',
      'title_en', 'Photographer media needs your approval',
      'body_ar', 'راجع الصور والوسائط ثم وافق على إضافتها للإعلان أو اطلب تعديلها.',
      'body_en', 'Review the media, then approve it for the listing or request changes.',
      'deep_route', 'property_details',
      'property_id', req.property_id,
      'shoot_request_id', p_request_id
    )
  );
  IF req.property_owner_id IS NOT NULL
     AND req.property_owner_id IS DISTINCT FROM req.requester_id THEN
    PERFORM public.workflow_create_notification(
      req.property_owner_id,
      'photo_shoot_delivered',
      'وسائط المصور بانتظار موافقة مالك الإعلان',
      'راجع الوسائط على الإعلان قبل نشرها.',
      'photo_shoot',
      p_request_id,
      jsonb_build_object(
        'title_ar', 'وسائط المصور بانتظار موافقتك',
        'title_en', 'Photographer media needs owner approval',
        'body_ar', 'راجع الوسائط على الإعلان قبل نشرها.',
        'body_en', 'Review the media on the listing before it is published.',
        'deep_route', 'property_details',
        'property_id', req.property_id,
        'shoot_request_id', p_request_id
      )
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.photographer_submit_delivery_for_review(
  uuid, text[], text, jsonb, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_submit_delivery_for_review(
  uuid, text[], text, jsonb, text, text
) TO authenticated;
REVOKE ALL ON FUNCTION public.photographer_deliver_shoot(
  uuid, text[], text, jsonb, text, text
) FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION public.owner_review_photographer_delivery(
  p_request_id uuid,
  p_approve boolean,
  p_replace_existing_media boolean DEFAULT false,
  p_set_cover boolean DEFAULT false,
  p_revision_note text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  g jsonb;
  v_images text[] := '{}'::text[];
  v_all_images text[] := '{}'::text[];
  v_video text;
  v_existing_video text;
  v_name text;
  v_tour jsonb;
  v_next_order int;
  v_path text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO req
  FROM public.photo_shoot_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF uid IS DISTINCT FROM req.requester_id
     AND uid IS DISTINCT FROM req.property_owner_id THEN
    RAISE EXCEPTION 'not_listing_owner_or_requester';
  END IF;
  IF req.delivery_review_status <> 'pending_review' THEN
    RAISE EXCEPTION 'delivery_not_waiting_review';
  END IF;

  IF NOT coalesce(p_approve, false) THEN
    IF trim(coalesce(p_revision_note, '')) = '' THEN
      RAISE EXCEPTION 'revision_note_required';
    END IF;
    UPDATE public.photo_shoot_requests
    SET delivery_review_status = 'revision_requested',
        delivery_revision_note = trim(p_revision_note),
        updated_at = now()
    WHERE id = p_request_id;
    UPDATE public.properties
    SET listing_guidance = jsonb_set(
      coalesce(listing_guidance, '{}'::jsonb),
      '{photo_shoot_status}',
      '"in_progress"',
      true
    )
    WHERE id = req.property_id;
    PERFORM public.workflow_create_notification(
      req.photographer_id,
      'photo_shoot_revision_requested',
      'طُلب تعديل وسائط التصوير',
      trim(p_revision_note),
      'photo_shoot',
      p_request_id,
      jsonb_build_object(
        'title_ar', 'طُلب تعديل وسائط التصوير',
        'title_en', 'Media changes requested',
        'body_ar', trim(p_revision_note),
        'body_en', trim(p_revision_note),
        'deep_route', 'photographer_hub',
        'property_id', req.property_id,
        'shoot_request_id', p_request_id
      )
    );
    RETURN;
  END IF;

  IF p_replace_existing_media AND req.owner_replace_media_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'replace_media_not_authorized';
  END IF;
  IF p_replace_existing_media AND req.owner_cover_change_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'cover_change_not_authorized';
  END IF;
  IF p_set_cover AND req.owner_cover_change_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'cover_change_not_authorized';
  END IF;

  SELECT coalesce(listing_guidance, '{}'::jsonb), video_url
    INTO g, v_existing_video
  FROM public.properties
  WHERE id = req.property_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;

  SELECT coalesce(array_agg(value), '{}'::text[])
    INTO v_images
  FROM jsonb_array_elements_text(
    coalesce(req.delivered_media->'image_paths', '[]'::jsonb)
  ) AS t(value);
  v_video := nullif(trim(coalesce(req.delivered_media->>'video_path', '')), '');
  v_tour := req.delivered_media->'in_app_tour';
  v_name := coalesce(req.delivered_media->>'photographer_name', '');

  IF p_replace_existing_media THEN
    DELETE FROM public.property_images WHERE property_id = req.property_id;
  END IF;
  IF p_set_cover AND coalesce(array_length(v_images, 1), 0) > 0 THEN
    UPDATE public.property_images
    SET sort_order = sort_order + 1000000
    WHERE property_id = req.property_id;
    v_next_order := 0;
  ELSE
    SELECT coalesce(max(sort_order) + 1, 0) INTO v_next_order
    FROM public.property_images WHERE property_id = req.property_id;
  END IF;
  FOREACH v_path IN ARRAY v_images LOOP
    INSERT INTO public.property_images (property_id, path, file_name, sort_order)
    VALUES (
      req.property_id,
      v_path,
      coalesce(nullif(split_part(v_path, '/', -1), ''), v_path),
      v_next_order
    );
    v_next_order := v_next_order + 1;
  END LOOP;

  SELECT coalesce(array_agg(path ORDER BY sort_order), '{}'::text[])
    INTO v_all_images
  FROM public.property_images
  WHERE property_id = req.property_id;

  g := jsonb_set(g, '{image_paths}', to_jsonb(v_all_images), true);
  g := jsonb_set(g, '{photo_shoot_status}', '"delivered"', true);
  g := jsonb_set(g, '{photo_shoot_request_id}', to_jsonb(p_request_id), true);
  g := jsonb_set(g, '{photographer_attribution}', to_jsonb(v_name), true);
  g := jsonb_set(g, '{photographer_id}', to_jsonb(req.photographer_id), true);
  g := jsonb_set(
    g,
    '{photographer_media_paths}',
    CASE
      WHEN p_replace_existing_media THEN to_jsonb(v_images)
      ELSE coalesce(g->'photographer_media_paths', '[]'::jsonb) || to_jsonb(v_images)
    END,
    true
  );
  g := jsonb_set(
    g,
    '{photographer_media_deliveries}',
    coalesce(g->'photographer_media_deliveries', '[]'::jsonb) || jsonb_build_array(
      jsonb_build_object(
        'shoot_request_id', p_request_id,
        'photographer_id', req.photographer_id,
        'photographer_name', v_name,
        'image_paths', to_jsonb(v_images),
        'video_path', nullif(trim(coalesce(req.delivered_media->>'video_path', '')), ''),
        'in_app_tour', v_tour,
        'approved_at', now()
      )
    ),
    true
  );
  IF v_video IS NOT NULL THEN
    g := jsonb_set(g, '{photographer_video_path}', to_jsonb(v_video), true);
  END IF;
  IF v_tour IS NOT NULL THEN
    IF p_replace_existing_media OR g->'in_app_tour' IS NULL THEN
      g := jsonb_set(g, '{in_app_tour}', v_tour, true);
    ELSE
      g := jsonb_set(
        g,
        '{photographer_tours}',
        coalesce(g->'photographer_tours', '[]'::jsonb) || jsonb_build_array(v_tour),
        true
      );
    END IF;
  END IF;

  IF p_set_cover THEN
    IF v_video IS NOT NULL THEN
      g := jsonb_set(g, '{cover_primary}', '"video"', true);
    ELSIF coalesce(array_length(v_images, 1), 0) > 0 THEN
      g := jsonb_set(g, '{cover_primary}', '"image"', true);
    END IF;
  END IF;

  UPDATE public.properties
  SET listing_guidance = g,
      video_url = CASE
        WHEN v_video IS NOT NULL
          AND (nullif(trim(coalesce(v_existing_video, '')), '') IS NULL OR p_set_cover)
          THEN v_video
        ELSE v_existing_video
      END
  WHERE id = req.property_id;

  UPDATE public.photo_shoot_requests
  SET status = 'delivered',
      delivery_review_status = 'approved',
      delivered_at = now(),
      updated_at = now()
  WHERE id = p_request_id;

  PERFORM public.workflow_create_notification(
    req.photographer_id,
    'photo_shoot_approved',
    'تم اعتماد وسائط التصوير',
    'وافق الناشر على إضافة الوسائط إلى الإعلان.',
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', 'تم اعتماد وسائط التصوير',
      'title_en', 'Photographer media approved',
      'body_ar', 'وافق الناشر على إضافة الوسائط إلى الإعلان.',
      'body_en', 'The publisher approved the media for the listing.',
      'deep_route', 'photographer_hub',
      'property_id', req.property_id,
      'shoot_request_id', p_request_id
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_review_photographer_delivery(
  uuid, boolean, boolean, boolean, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_review_photographer_delivery(
  uuid, boolean, boolean, boolean, text
) TO authenticated;

COMMIT;