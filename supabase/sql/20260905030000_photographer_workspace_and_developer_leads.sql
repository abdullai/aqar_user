-- مصور عقاري (طبقة فوق الحساب الحالي، دون تغيير account_type)
-- طلبات التصوير خارج حدّ 20/10. مسودات سحابية غير مضافة عمداً.

BEGIN;

CREATE TABLE IF NOT EXISTS public.photographer_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'verified', 'rejected', 'suspended')),
  display_name text,
  national_id text,
  commercial_register text,
  bio text,
  city text,
  photo_rate_sar numeric,
  video_rate_sar numeric,
  tour_rate_sar numeric,
  max_accepts_per_day int NOT NULL DEFAULT 5
    CHECK (max_accepts_per_day BETWEEN 1 AND 50),
  portfolio jsonb NOT NULL DEFAULT '[]'::jsonb,
  certificates jsonb NOT NULL DEFAULT '[]'::jsonb,
  service_policy_accepted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  review_note text,
  rating_avg numeric NOT NULL DEFAULT 0,
  rating_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.photo_shoot_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_request_id uuid,
  property_id uuid,
  requester_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  photographer_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  shoot_kinds text[] NOT NULL DEFAULT ARRAY['photos']::text[],
  location_text text,
  latitude double precision,
  longitude double precision,
  preferred_at timestamptz,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN (
      'pending', 'accepted', 'rejected', 'in_progress', 'delivered', 'cancelled'
    )),
  reject_reason text,
  cover_image_path text,
  technical_notes text,
  delivered_media jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
  delivered_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_photo_shoot_photographer_status
  ON public.photo_shoot_requests (photographer_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_photo_shoot_requester
  ON public.photo_shoot_requests (requester_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_photo_shoot_property
  ON public.photo_shoot_requests (property_id)
  WHERE property_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.photographer_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shoot_request_id uuid NOT NULL UNIQUE
    REFERENCES public.photo_shoot_requests (id) ON DELETE CASCADE,
  photographer_id uuid NOT NULL,
  reviewer_id uuid NOT NULL,
  stars int NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.developer_interest_leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  full_name text NOT NULL,
  email text NOT NULL,
  development_type text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.photographer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photo_shoot_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.photographer_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.developer_interest_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS photographer_profiles_select ON public.photographer_profiles;
CREATE POLICY photographer_profiles_select ON public.photographer_profiles
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_platform_staff()
  );

DROP POLICY IF EXISTS photographer_profiles_insert_self ON public.photographer_profiles;
CREATE POLICY photographer_profiles_insert_self ON public.photographer_profiles
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS photographer_profiles_update_self ON public.photographer_profiles;
CREATE POLICY photographer_profiles_update_self ON public.photographer_profiles
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_staff())
  WITH CHECK (user_id = auth.uid() OR public.is_platform_staff());

DROP POLICY IF EXISTS photo_shoot_select ON public.photo_shoot_requests;
CREATE POLICY photo_shoot_select ON public.photo_shoot_requests
  FOR SELECT TO authenticated
  USING (
    requester_id = auth.uid()
    OR photographer_id = auth.uid()
    OR public.is_platform_staff()
  );

DROP POLICY IF EXISTS photo_shoot_insert ON public.photo_shoot_requests;
CREATE POLICY photo_shoot_insert ON public.photo_shoot_requests
  FOR INSERT TO authenticated
  WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS photographer_reviews_select ON public.photographer_reviews;
CREATE POLICY photographer_reviews_select ON public.photographer_reviews
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS photographer_reviews_insert ON public.photographer_reviews;
CREATE POLICY photographer_reviews_insert ON public.photographer_reviews
  FOR INSERT TO authenticated
  WITH CHECK (reviewer_id = auth.uid());

DROP POLICY IF EXISTS developer_leads_insert ON public.developer_interest_leads;
CREATE POLICY developer_leads_insert ON public.developer_interest_leads
  FOR INSERT TO authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS developer_leads_staff ON public.developer_interest_leads;
CREATE POLICY developer_leads_staff ON public.developer_interest_leads
  FOR SELECT TO authenticated
  USING (public.is_platform_staff() OR user_id = auth.uid());

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
  p_accept_policy boolean DEFAULT false
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
    certificates, service_policy_accepted_at, updated_at
  ) VALUES (
    uid, 'pending', trim(p_display_name), nullif(trim(p_national_id), ''),
    nullif(trim(p_commercial_register), ''), nullif(trim(p_bio), ''),
    nullif(trim(p_city), ''), p_photo_rate_sar, p_video_rate_sar, p_tour_rate_sar,
    coalesce(p_certificates, '[]'::jsonb), now(), now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    display_name = excluded.display_name,
    national_id = excluded.national_id,
    commercial_register = excluded.commercial_register,
    bio = excluded.bio,
    city = excluded.city,
    photo_rate_sar = excluded.photo_rate_sar,
    video_rate_sar = excluded.video_rate_sar,
    tour_rate_sar = excluded.tour_rate_sar,
    certificates = excluded.certificates,
    service_policy_accepted_at = now(),
    status = CASE
      WHEN photographer_profiles.status = 'verified' THEN 'verified'
      ELSE 'pending'
    END,
    updated_at = now();

  RETURN uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.staff_review_photographer(
  p_user_id uuid,
  p_approve boolean,
  p_note text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT public.is_platform_staff() THEN RAISE EXCEPTION 'not_staff'; END IF;

  UPDATE public.photographer_profiles
  SET
    status = CASE WHEN p_approve THEN 'verified' ELSE 'rejected' END,
    reviewed_at = now(),
    reviewed_by = uid,
    review_note = nullif(trim(p_note), ''),
    updated_at = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'photographer_not_found'; END IF;

  PERFORM public.workflow_create_notification(
    p_user_id,
    CASE WHEN p_approve THEN 'photographer_verified' ELSE 'photographer_rejected' END,
    CASE WHEN p_approve THEN 'تم توثيق حساب المصور' ELSE 'لم يُقبل طلب المصور' END,
    CASE WHEN p_approve
      THEN 'يمكنك استقبال طلبات التصوير من الملاك والمسوّقين.'
      ELSE coalesce(nullif(trim(p_note), ''), 'راجع بيانات التسجيل وأعد التقديم.')
    END,
    'photographer',
    p_user_id,
    jsonb_build_object(
      'title_ar', CASE WHEN p_approve THEN 'تم توثيق حساب المصور' ELSE 'لم يُقبل طلب المصور' END,
      'title_en', CASE WHEN p_approve THEN 'Photographer verified' ELSE 'Photographer application declined' END,
      'body_ar', CASE WHEN p_approve
        THEN 'يمكنك استقبال طلبات التصوير من الملاك والمسوّقين.'
        ELSE coalesce(nullif(trim(p_note), ''), 'راجع بيانات التسجيل وأعد التقديم.')
      END,
      'body_en', CASE WHEN p_approve
        THEN 'You can now receive shoot requests from owners and marketers.'
        ELSE coalesce(nullif(trim(p_note), ''), 'Review your details and apply again.')
      END,
      'deep_route', 'photographer_hub'
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_photo_shoot_request(
  p_photographer_id uuid,
  p_property_id uuid DEFAULT NULL,
  p_listing_request_id uuid DEFAULT NULL,
  p_shoot_kinds text[] DEFAULT ARRAY['photos']::text[],
  p_location_text text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_preferred_at timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_ok boolean;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_photographer_id IS NULL THEN RAISE EXCEPTION 'photographer_required'; END IF;
  IF p_photographer_id = uid THEN RAISE EXCEPTION 'cannot_book_self'; END IF;

  SELECT true INTO v_ok
  FROM public.photographer_profiles
  WHERE user_id = p_photographer_id AND status = 'verified';
  IF v_ok IS NOT TRUE THEN RAISE EXCEPTION 'photographer_not_verified'; END IF;

  INSERT INTO public.photo_shoot_requests (
    listing_request_id, property_id, requester_id, photographer_id,
    shoot_kinds, location_text, latitude, longitude, preferred_at, status
  ) VALUES (
    p_listing_request_id, p_property_id, uid, p_photographer_id,
    coalesce(p_shoot_kinds, ARRAY['photos']::text[]),
    nullif(trim(p_location_text), ''), p_latitude, p_longitude,
    p_preferred_at, 'pending'
  )
  RETURNING id INTO v_id;

  PERFORM public.workflow_create_notification(
    p_photographer_id,
    'photo_shoot_requested',
    'طلب تصوير جديد',
    'وصلك طلب تصوير. اقبله أو ارفضه مع سبب.',
    'photo_shoot',
    v_id,
    jsonb_build_object(
      'title_ar', 'طلب تصوير جديد',
      'title_en', 'New photo-shoot request',
      'body_ar', 'وصلك طلب تصوير. اقبله أو ارفضه مع سبب.',
      'body_en', 'You have a shoot request. Accept it or decline with a reason.',
      'deep_route', 'photographer_hub',
      'shoot_request_id', v_id
    )
  );

  RETURN v_id;
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

  SELECT * INTO req FROM public.photo_shoot_requests
  WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF req.photographer_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_photographer'; END IF;
  IF req.status <> 'pending' THEN RAISE EXCEPTION 'not_pending'; END IF;

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
  ELSE
    IF trim(coalesce(p_reject_reason, '')) = '' THEN
      RAISE EXCEPTION 'reject_reason_required';
    END IF;
    UPDATE public.photo_shoot_requests
    SET status = 'rejected',
        reject_reason = trim(p_reject_reason),
        updated_at = now()
    WHERE id = p_request_id;
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
      'deep_route', 'photographer_hub',
      'shoot_request_id', p_request_id
    )
  );
END;
$$;

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

  SELECT coalesce(listing_guidance, '{}'::jsonb) INTO g
  FROM public.properties WHERE id = req.property_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;

  IF coalesce(array_length(p_image_paths, 1), 0) > 0 THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{image_paths}', to_jsonb(p_image_paths), true);
    DELETE FROM public.property_images WHERE property_id = req.property_id;
    FOR i IN 1 .. array_length(p_image_paths, 1) LOOP
      INSERT INTO public.property_images (property_id, path, file_name, sort_order)
      VALUES (
        req.property_id,
        p_image_paths[i],
        coalesce(nullif(split_part(p_image_paths[i], '/', -1), ''), p_image_paths[i]),
        i - 1
      );
    END LOOP;
  END IF;

  IF nullif(trim(coalesce(p_video_path, '')), '') IS NOT NULL THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{video_path}', to_jsonb(trim(p_video_path)), true);
  END IF;

  IF p_in_app_tour IS NOT NULL THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{in_app_tour}', p_in_app_tour, true);
  END IF;

  UPDATE public.properties
  SET listing_guidance = g
  WHERE id = req.property_id;

  UPDATE public.photo_shoot_requests
  SET
    status = 'delivered',
    delivered_at = now(),
    cover_image_path = coalesce(nullif(trim(p_cover_image_path), ''), p_image_paths[1]),
    technical_notes = nullif(trim(p_technical_notes), ''),
    delivered_media = jsonb_build_object(
      'image_paths', to_jsonb(coalesce(p_image_paths, '{}'::text[])),
      'video_path', nullif(trim(coalesce(p_video_path, '')), ''),
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

CREATE OR REPLACE FUNCTION public.owner_rate_photographer(
  p_request_id uuid,
  p_stars int,
  p_comment text DEFAULT NULL
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
  IF p_stars < 1 OR p_stars > 5 THEN RAISE EXCEPTION 'invalid_stars'; END IF;

  SELECT * INTO req FROM public.photo_shoot_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF req.requester_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_requester'; END IF;
  IF req.status <> 'delivered' THEN RAISE EXCEPTION 'not_delivered'; END IF;

  INSERT INTO public.photographer_reviews (
    shoot_request_id, photographer_id, reviewer_id, stars, comment
  ) VALUES (
    p_request_id, req.photographer_id, uid, p_stars, nullif(trim(p_comment), '')
  );

  UPDATE public.photographer_profiles p
  SET
    rating_count = s.cnt,
    rating_avg = s.avg_stars,
    updated_at = now()
  FROM (
    SELECT photographer_id, count(*)::int AS cnt, avg(stars)::numeric AS avg_stars
    FROM public.photographer_reviews
    WHERE photographer_id = req.photographer_id
    GROUP BY photographer_id
  ) s
  WHERE p.user_id = s.photographer_id;

  PERFORM public.workflow_create_notification(
    req.photographer_id,
    'photographer_rated',
    'تقييم جديد',
    'وصلك تقييم بعد تسليم جلسة تصوير.',
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', 'تقييم جديد',
      'title_en', 'New rating',
      'body_ar', 'وصلك تقييم بعد تسليم جلسة تصوير.',
      'body_en', 'You received a rating after delivering a shoot.',
      'deep_route', 'photographer_hub',
      'shoot_request_id', p_request_id
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_developer_interest(
  p_full_name text,
  p_email text,
  p_development_type text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF trim(coalesce(p_full_name, '')) = '' THEN RAISE EXCEPTION 'name_required'; END IF;
  IF trim(coalesce(p_email, '')) = '' THEN RAISE EXCEPTION 'email_required'; END IF;
  IF trim(coalesce(p_development_type, '')) = '' THEN RAISE EXCEPTION 'type_required'; END IF;

  INSERT INTO public.developer_interest_leads (
    user_id, full_name, email, development_type
  ) VALUES (
    uid, trim(p_full_name), trim(p_email), trim(p_development_type)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.photographer_set_daily_cap(p_max int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_max < 1 OR p_max > 50 THEN RAISE EXCEPTION 'invalid_cap'; END IF;
  UPDATE public.photographer_profiles
  SET max_accepts_per_day = p_max, updated_at = now()
  WHERE user_id = uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'photographer_not_found'; END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_photographer_join(
  text, text, text, text, text, numeric, numeric, numeric, jsonb, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_photographer_join(
  text, text, text, text, text, numeric, numeric, numeric, jsonb, boolean
) TO authenticated;

REVOKE ALL ON FUNCTION public.staff_review_photographer(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.staff_review_photographer(uuid, boolean, text) TO authenticated;

REVOKE ALL ON FUNCTION public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_photo_shoot_request(
  uuid, uuid, uuid, text[], text, double precision, double precision, timestamptz
) TO authenticated;

REVOKE ALL ON FUNCTION public.photographer_respond_shoot(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_respond_shoot(uuid, boolean, text) TO authenticated;

REVOKE ALL ON FUNCTION public.photographer_deliver_shoot(
  uuid, text[], text, jsonb, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_deliver_shoot(
  uuid, text[], text, jsonb, text, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.owner_rate_photographer(uuid, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_rate_photographer(uuid, int, text) TO authenticated;

REVOKE ALL ON FUNCTION public.submit_developer_interest(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_developer_interest(text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.photographer_set_daily_cap(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.photographer_set_daily_cap(int) TO authenticated;

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
  portfolio jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    p.user_id, p.status, p.display_name, p.bio, p.city,
    p.photo_rate_sar, p.video_rate_sar, p.tour_rate_sar,
    p.rating_avg, p.rating_count, p.portfolio
  FROM public.photographer_profiles p
  WHERE p.status = 'verified'
  ORDER BY p.rating_avg DESC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.list_verified_photographers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_verified_photographers() TO authenticated;

COMMIT;
