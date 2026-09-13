-- سعر متفق عليه لطلب التصوير + حدود الوسائط + إحداثيات المصور للترتيب حسب القرب.

BEGIN;

ALTER TABLE public.photographer_profiles
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision;

ALTER TABLE public.photo_shoot_requests
  ADD COLUMN IF NOT EXISTS quoted_amount_sar numeric,
  ADD COLUMN IF NOT EXISTS max_photos int NOT NULL DEFAULT 30
    CHECK (max_photos BETWEEN 1 AND 80),
  ADD COLUMN IF NOT EXISTS max_videos int NOT NULL DEFAULT 1
    CHECK (max_videos BETWEEN 0 AND 3),
  ADD COLUMN IF NOT EXISTS include_tour boolean NOT NULL DEFAULT false;

DROP FUNCTION IF EXISTS public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz
);
DROP FUNCTION IF EXISTS public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz,
  numeric, int, int, boolean
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
  p_include_tour boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_ok boolean;
  g jsonb;
  kinds text[];
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_photographer_id IS NULL THEN RAISE EXCEPTION 'photographer_required'; END IF;
  IF p_photographer_id = uid THEN RAISE EXCEPTION 'cannot_book_self'; END IF;

  SELECT true INTO v_ok
  FROM public.photographer_profiles
  WHERE user_id = p_photographer_id AND status = 'verified';
  IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'photographer_not_verified'; END IF;

  kinds := coalesce(p_shoot_kinds, ARRAY['photos']::text[]);
  -- توحيد مفتاح الجولة
  kinds := ARRAY(
    SELECT CASE WHEN x IN ('tour_3d', '3d', 'virtual_tour') THEN 'tour' ELSE x END
    FROM unnest(kinds) x
  );

  INSERT INTO public.photo_shoot_requests (
    listing_request_id, property_id, requester_id, photographer_id,
    shoot_kinds, location_text, latitude, longitude, preferred_at, status,
    quoted_amount_sar, max_photos, max_videos, include_tour
  ) VALUES (
    p_listing_request_id, p_property_id, uid, p_photographer_id,
    kinds,
    nullif(trim(p_location_text), ''), p_latitude, p_longitude,
    p_preferred_at, 'pending',
    p_quoted_amount_sar,
    least(greatest(coalesce(p_max_photos, 30), 1), 80),
    least(greatest(coalesce(p_max_videos, 1), 0), 3),
    coalesce(p_include_tour, 'tour' = ANY (kinds))
  )
  RETURNING id INTO v_id;

  IF p_property_id IS NOT NULL THEN
    SELECT coalesce(listing_guidance, '{}'::jsonb) INTO g
    FROM public.properties WHERE id = p_property_id;
    IF FOUND THEN
      g := jsonb_set(coalesce(g, '{}'::jsonb), '{photo_shoot_status}', '"pending"', true);
      g := jsonb_set(g, '{photo_shoot_request_id}', to_jsonb(v_id), true);
      UPDATE public.properties SET listing_guidance = g WHERE id = p_property_id;
    END IF;
  END IF;

  PERFORM public.workflow_create_notification(
    p_photographer_id,
    'photo_shoot_requested',
    'طلب تصوير جديد',
    'وصلك طلب تصوير. اقبله أو ارفضه مع سبب خلال 24 ساعة. القبول يعني الاتفاق على السعر المعروض.',
    'photo_shoot',
    v_id,
    jsonb_build_object(
      'title_ar', 'طلب تصوير جديد',
      'title_en', 'New photo-shoot request',
      'body_ar', 'وصلك طلب تصوير. اقبله أو ارفضه مع سبب خلال 24 ساعة. القبول يعني الاتفاق على السعر المعروض.',
      'body_en', 'You have a shoot request. Accept or decline with a reason within 24 hours. Accepting agrees the quoted price.',
      'deep_route', 'photographer_hub',
      'shoot_request_id', v_id,
      'quoted_amount_sar', p_quoted_amount_sar
    )
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz,
  numeric, int, int, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz,
  numeric, int, int, boolean
) TO authenticated;

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
  ORDER BY p.rating_avg DESC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.list_verified_photographers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_verified_photographers() TO authenticated;

DROP FUNCTION IF EXISTS public.submit_photographer_join(
  text, text, text, text, text, numeric, numeric, numeric, jsonb, boolean
);
DROP FUNCTION IF EXISTS public.submit_photographer_join(
  text, text, text, text, text, numeric, numeric, numeric, jsonb, boolean,
  double precision, double precision
);

CREATE OR REPLACE FUNCTION public.submit_photographer_join(
  p_display_name text,
  p_national_id text,
  p_commercial_register text DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_photo_rate_sar numeric DEFAULT NULL,
  p_video_rate_sar numeric DEFAULT NULL,
  p_tour_rate_sar numeric DEFAULT NULL,
  p_certificates jsonb DEFAULT '[]'::jsonb,
  p_accept_policy boolean DEFAULT false,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF coalesce(p_accept_policy, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'policy_not_accepted';
  END IF;
  IF trim(coalesce(p_display_name, '')) = '' THEN
    RAISE EXCEPTION 'display_name_required';
  END IF;
  IF trim(coalesce(p_national_id, '')) = ''
     AND trim(coalesce(p_commercial_register, '')) = '' THEN
    RAISE EXCEPTION 'identity_required';
  END IF;

  INSERT INTO public.photographer_profiles (
    user_id, status, display_name, national_id, commercial_register,
    bio, city, photo_rate_sar, video_rate_sar, tour_rate_sar,
    certificates, service_policy_accepted_at, latitude, longitude, updated_at
  ) VALUES (
    uid, 'pending', trim(p_display_name), nullif(trim(p_national_id), ''),
    nullif(trim(p_commercial_register), ''), nullif(trim(p_bio), ''),
    nullif(trim(p_city), ''), p_photo_rate_sar, p_video_rate_sar, p_tour_rate_sar,
    coalesce(p_certificates, '[]'::jsonb), now(), p_latitude, p_longitude, now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    status = 'pending',
    display_name = excluded.display_name,
    national_id = excluded.national_id,
    commercial_register = excluded.commercial_register,
    bio = excluded.bio,
    city = excluded.city,
    photo_rate_sar = excluded.photo_rate_sar,
    video_rate_sar = excluded.video_rate_sar,
    tour_rate_sar = excluded.tour_rate_sar,
    certificates = excluded.certificates,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    reviewed_at = NULL,
    reviewed_by = NULL,
    review_note = NULL,
    updated_at = now();

  RETURN uid;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_photographer_join(
  text, text, text, text, text, numeric, numeric, numeric, jsonb, boolean,
  double precision, double precision
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_photographer_join(
  text, text, text, text, text, numeric, numeric, numeric, jsonb, boolean,
  double precision, double precision
) TO authenticated;

CREATE OR REPLACE FUNCTION public.photographer_deliver_shoot(
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
  g jsonb;
  i int;
  v_video text := nullif(trim(coalesce(p_video_path, '')), '');
  n_photos int;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO req FROM public.photo_shoot_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF req.photographer_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_photographer'; END IF;
  IF req.status NOT IN ('accepted', 'in_progress') THEN
    RAISE EXCEPTION 'not_accepted';
  END IF;
  IF req.property_id IS NULL THEN RAISE EXCEPTION 'property_required'; END IF;

  n_photos := coalesce(array_length(p_image_paths, 1), 0);
  IF n_photos > coalesce(req.max_photos, 30) THEN
    RAISE EXCEPTION 'photo_limit_exceeded';
  END IF;
  IF v_video IS NOT NULL AND coalesce(req.max_videos, 1) < 1 THEN
    RAISE EXCEPTION 'video_not_allowed';
  END IF;
  IF p_in_app_tour IS NOT NULL AND coalesce(req.include_tour, false) IS NOT TRUE
     AND NOT ('tour' = ANY (coalesce(req.shoot_kinds, ARRAY[]::text[]))) THEN
    RAISE EXCEPTION 'tour_not_requested';
  END IF;

  SELECT coalesce(listing_guidance, '{}'::jsonb) INTO g
  FROM public.properties WHERE id = req.property_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;

  IF n_photos > 0 THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{image_paths}', to_jsonb(p_image_paths), true);
    DELETE FROM public.property_images WHERE property_id = req.property_id;
    FOR i IN 1 .. n_photos LOOP
      INSERT INTO public.property_images (property_id, path, file_name, sort_order)
      VALUES (
        req.property_id,
        p_image_paths[i],
        coalesce(nullif(split_part(p_image_paths[i], '/', -1), ''), p_image_paths[i]),
        i - 1
      );
    END LOOP;
  END IF;

  IF v_video IS NOT NULL THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{video_path}', to_jsonb(v_video), true);
  END IF;

  IF p_in_app_tour IS NOT NULL THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{in_app_tour}', p_in_app_tour, true);
  END IF;

  g := jsonb_set(coalesce(g, '{}'::jsonb), '{photo_shoot_status}', '"delivered"', true);

  UPDATE public.properties
  SET
    listing_guidance = g,
    video_url = CASE WHEN v_video IS NOT NULL THEN v_video ELSE video_url END
  WHERE id = req.property_id;

  UPDATE public.photo_shoot_requests
  SET
    status = 'delivered',
    delivered_at = now(),
    cover_image_path = coalesce(nullif(trim(p_cover_image_path), ''), p_image_paths[1]),
    technical_notes = nullif(trim(p_technical_notes), ''),
    delivered_media = jsonb_build_object(
      'image_paths', to_jsonb(coalesce(p_image_paths, '{}'::text[])),
      'video_path', v_video,
      'in_app_tour', p_in_app_tour
    ),
    updated_at = now()
  WHERE id = p_request_id;

  UPDATE public.photographer_profiles
  SET portfolio = (
        SELECT coalesce(jsonb_agg(x), '[]'::jsonb)
        FROM (
          SELECT e AS x
          FROM jsonb_array_elements(coalesce(portfolio, '[]'::jsonb)) e
          UNION ALL
          SELECT jsonb_build_object(
            'property_id', req.property_id,
            'cover', coalesce(nullif(trim(p_cover_image_path), ''), p_image_paths[1]),
            'delivered_at', now()
          )
        ) s
      ),
      updated_at = now()
  WHERE user_id = uid;

  PERFORM public.workflow_create_notification(
    req.requester_id,
    'photo_shoot_delivered',
    'الوسائط جاهزة',
    'رفع المصور الوسائط إلى إعلانك. يمكنك تقييم العمل.',
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', 'الوسائط جاهزة',
      'title_en', 'Shoot media is ready',
      'body_ar', 'رفع المصور الوسائط إلى إعلانك. يمكنك تقييم العمل.',
      'body_en', 'The photographer uploaded media to your listing. You can rate the work.',
      'deep_route', 'property_details',
      'property_id', req.property_id,
      'shoot_request_id', p_request_id
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.photo_shoot_set_listing_status(
  p_property_id uuid,
  p_status text,
  p_request_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g jsonb;
BEGIN
  IF p_property_id IS NULL THEN RETURN; END IF;
  SELECT coalesce(listing_guidance, '{}'::jsonb) INTO g
  FROM public.properties WHERE id = p_property_id;
  IF NOT FOUND THEN RETURN; END IF;
  g := jsonb_set(coalesce(g, '{}'::jsonb), '{photo_shoot_status}', to_jsonb(p_status), true);
  IF p_request_id IS NOT NULL THEN
    g := jsonb_set(g, '{photo_shoot_request_id}', to_jsonb(p_request_id), true);
  END IF;
  UPDATE public.properties SET listing_guidance = g WHERE id = p_property_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_stale_photo_shoot_requests()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN
    SELECT *
    FROM public.photo_shoot_requests
    WHERE status = 'pending'
      AND created_at < now() - interval '24 hours'
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.photo_shoot_requests
    SET
      status = 'cancelled',
      reject_reason = 'expired_24h',
      updated_at = now()
    WHERE id = r.id;

    PERFORM public.photo_shoot_set_listing_status(r.property_id, 'expired', r.id);

    PERFORM public.workflow_create_notification(
      r.requester_id,
      'photo_shoot_expired',
      'انتهت مهلة قبول التصوير',
      'لم يُقبل الطلب خلال 24 ساعة فأُلغي تلقائياً.',
      'photo_shoot',
      r.id,
      jsonb_build_object(
        'title_ar', 'انتهت مهلة قبول التصوير',
        'title_en', 'Photo-shoot request expired',
        'body_ar', 'لم يُقبل الطلب خلال 24 ساعة فأُلغي تلقائياً.',
        'body_en', 'The photographer did not respond within 24 hours, so the request was cancelled.',
        'deep_route', CASE
          WHEN r.property_id IS NOT NULL THEN 'property_details'
          ELSE 'user_dashboard'
        END,
        'property_id', r.property_id,
        'shoot_request_id', r.id
      )
    );

    PERFORM public.workflow_create_notification(
      r.photographer_id,
      'photo_shoot_expired',
      'انتهت مهلة طلب تصوير',
      'طلب وارد لم يُجب خلال 24 ساعة وأُلغي تلقائياً.',
      'photo_shoot',
      r.id,
      jsonb_build_object(
        'title_ar', 'انتهت مهلة طلب تصوير',
        'title_en', 'A shoot request expired',
        'body_ar', 'طلب وارد لم يُجب خلال 24 ساعة وأُلغي تلقائياً.',
        'body_en', 'An incoming shoot request was cancelled after 24 hours without a response.',
        'deep_route', 'photographer_hub',
        'shoot_request_id', r.id
      )
    );

    n := n + 1;
  END LOOP;

  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.photographer_respond_shoot(
  p_request_id uuid,
  p_accept boolean,
  p_reject_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_cap int;
  v_today int;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  PERFORM public.expire_stale_photo_shoot_requests();

  SELECT * INTO req FROM public.photo_shoot_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF req.photographer_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_photographer'; END IF;
  IF req.status <> 'pending' THEN RAISE EXCEPTION 'shoot_accept_expired'; END IF;
  IF req.created_at < now() - interval '24 hours' THEN
    RAISE EXCEPTION 'shoot_accept_expired';
  END IF;

  IF p_accept THEN
    SELECT coalesce(max_accepts_per_day, 5) INTO v_cap
    FROM public.photographer_profiles WHERE user_id = uid;
    SELECT count(*)::int INTO v_today
    FROM public.photo_shoot_requests
    WHERE photographer_id = uid
      AND accepted_at IS NOT NULL
      AND accepted_at::date = current_date;
    IF v_today >= coalesce(v_cap, 5) THEN
      RAISE EXCEPTION 'daily_accept_cap';
    END IF;

    UPDATE public.photo_shoot_requests
    SET status = 'accepted', accepted_at = now(), updated_at = now()
    WHERE id = p_request_id;

    PERFORM public.photo_shoot_set_listing_status(req.property_id, 'accepted', p_request_id);
  ELSE
    IF trim(coalesce(p_reject_reason, '')) = '' THEN
      RAISE EXCEPTION 'reject_reason_required';
    END IF;
    UPDATE public.photo_shoot_requests
    SET status = 'rejected',
        reject_reason = trim(p_reject_reason),
        updated_at = now()
    WHERE id = p_request_id;

    PERFORM public.photo_shoot_set_listing_status(req.property_id, 'rejected', p_request_id);
  END IF;

  PERFORM public.workflow_create_notification(
    req.requester_id,
    CASE WHEN p_accept THEN 'photo_shoot_accepted' ELSE 'photo_shoot_rejected' END,
    CASE WHEN p_accept THEN 'قبل المصور طلب التصوير' ELSE 'رفض المصور طلب التصوير' END,
    CASE WHEN p_accept
      THEN 'سيبدأ المصور العمل ويرفع الوسائط عند الجاهزية.'
      ELSE trim(p_reject_reason)
    END,
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', CASE WHEN p_accept THEN 'قبل المصور طلب التصوير' ELSE 'رفض المصور طلب التصوير' END,
      'title_en', CASE WHEN p_accept THEN 'Photographer accepted' ELSE 'Photographer declined' END,
      'body_ar', CASE WHEN p_accept
        THEN 'سيبدأ المصور العمل ويرفع الوسائط عند الجاهزية.'
        ELSE trim(p_reject_reason)
      END,
      'body_en', CASE WHEN p_accept
        THEN 'The photographer will upload media when ready.'
        ELSE trim(p_reject_reason)
      END,
      'deep_route', 'property_details',
      'property_id', req.property_id,
      'shoot_request_id', p_request_id,
      'quoted_amount_sar', req.quoted_amount_sar
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.photo_shoot_set_listing_status(uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_stale_photo_shoot_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_photo_shoot_requests() TO service_role;
GRANT EXECUTE ON FUNCTION public.photographer_respond_shoot(uuid, boolean, text) TO authenticated;

COMMIT;
