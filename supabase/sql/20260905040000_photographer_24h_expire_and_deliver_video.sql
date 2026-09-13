-- مهلة 24 ساعة لقبول طلب التصوير + ربط فيديو التسليم بعمود الإعلان.
-- مراجعة تسجيل المصور تبقى يدوية في لوحة التشغيل (لا اعتماد تلقائي).

BEGIN;

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

REVOKE ALL ON FUNCTION public.expire_stale_photo_shoot_requests() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.expire_stale_photo_shoot_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.expire_stale_photo_shoot_requests() TO service_role;

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
  v_video text := nullif(trim(coalesce(p_video_path, '')), '');
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

  IF v_video IS NOT NULL THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{video_path}', to_jsonb(v_video), true);
  END IF;

  IF p_in_app_tour IS NOT NULL THEN
    g := jsonb_set(coalesce(g, '{}'::jsonb), '{in_app_tour}', p_in_app_tour, true);
  END IF;

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

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('expire_photo_shoot_24h');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'expire_photo_shoot_24h',
    '*/15 * * * *',
    $job$SELECT public.expire_stale_photo_shoot_requests();$job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not enabled on this project: %', SQLERRM;
END $$;

COMMIT;
