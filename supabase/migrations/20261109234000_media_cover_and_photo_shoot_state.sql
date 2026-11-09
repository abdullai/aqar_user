BEGIN;

-- 1) حالة الغلاف تُشتق دائماً من الوسائط الفعلية: صورة أو فيديو أو جولة => غلاف حقيقي،
--    وإلا يُستخدم الغلاف الذكي للمشروع. بذلك لا يعتمد أي مسار (نشر/طلب/مصوّر/تعديل)
--    على ضبط العلامة يدوياً.
CREATE OR REPLACE FUNCTION public.derive_property_default_cover_flag()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  g jsonb := CASE
    WHEN jsonb_typeof(NEW.listing_guidance) = 'object' THEN NEW.listing_guidance
    ELSE '{}'::jsonb
  END;
  has_image boolean;
  has_video boolean;
  has_tour boolean;
BEGIN
  has_image := coalesce(
    (nullif(trim(coalesce(NEW.image_url, '')), '') IS NOT NULL
       AND trim(NEW.image_url) <> '__smart_branding_cover__')
    OR (jsonb_typeof(g -> 'image_paths') = 'array'
        AND jsonb_array_length(g -> 'image_paths') > 0),
    false);
  has_video := coalesce(
    nullif(trim(coalesce(NEW.video_url, '')), '') IS NOT NULL
    OR nullif(trim(coalesce(g ->> 'video_path', '')), '') IS NOT NULL
    OR nullif(trim(coalesce(g ->> 'photographer_video_path', '')), '') IS NOT NULL,
    false);
  has_tour := coalesce(
    nullif(trim(coalesce(NEW.virtual_tour_url, '')), '') IS NOT NULL
    OR (jsonb_typeof(g -> 'in_app_tour') = 'object' AND g -> 'in_app_tour' <> '{}'::jsonb),
    false);

  NEW.default_cover_used := NOT (has_image OR has_video OR has_tour);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_derive_property_default_cover_flag ON public.properties;
CREATE TRIGGER trg_derive_property_default_cover_flag
  BEFORE INSERT OR UPDATE OF image_url, video_url, virtual_tour_url, listing_guidance
  ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.derive_property_default_cover_flag();

-- 2) حالة طلب المصوّر على العقار تُشتق من جدول الطلبات نفسه (مصدر الحقيقة)،
--    فتظهر «يحتاج مصوّراً» في البطاقة والتفاصيل وتختفي تلقائياً بعد اعتماد التسليم.
CREATE OR REPLACE FUNCTION public.recompute_property_photo_shoot_state(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  r record;
  v_status text;
BEGIN
  IF p_property_id IS NULL THEN RETURN; END IF;

  SELECT s.id, s.status, s.delivery_review_status
    INTO r
  FROM public.photo_shoot_requests s
  WHERE s.property_id = p_property_id
  ORDER BY (s.status IN ('open', 'pending', 'accepted', 'in_progress')) DESC,
           s.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    v_status := NULL;
  ELSIF r.status = 'delivered' THEN
    v_status := 'delivered';
  ELSIF r.status IN ('rejected', 'cancelled') THEN
    v_status := NULL;
  ELSIF r.delivery_review_status = 'pending_review' THEN
    v_status := 'pending_review';
  ELSIF r.delivery_review_status = 'revision_requested' THEN
    v_status := 'in_progress';
  ELSE
    v_status := r.status;
  END IF;

  UPDATE public.properties p
  SET listing_guidance = CASE
    WHEN v_status IS NULL THEN
      coalesce(p.listing_guidance, '{}'::jsonb) - 'photo_shoot_status'
    ELSE
      jsonb_set(
        jsonb_set(
          coalesce(p.listing_guidance, '{}'::jsonb),
          '{photo_shoot_status}', to_jsonb(v_status), true
        ),
        '{photo_shoot_request_id}', to_jsonb(r.id), true
      )
  END
  WHERE p.id = p_property_id
    AND (p.listing_guidance ->> 'photo_shoot_status') IS DISTINCT FROM v_status;
END;
$$;

REVOKE ALL ON FUNCTION public.recompute_property_photo_shoot_state(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.tr_photo_shoot_sync_property_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.property_id IS NOT NULL THEN
    PERFORM public.recompute_property_photo_shoot_state(OLD.property_id);
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') AND NEW.property_id IS NOT NULL THEN
    PERFORM public.recompute_property_photo_shoot_state(NEW.property_id);
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

REVOKE ALL ON FUNCTION public.tr_photo_shoot_sync_property_state()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_photo_shoot_sync_property_state
  ON public.photo_shoot_requests;
CREATE TRIGGER trg_photo_shoot_sync_property_state
  AFTER INSERT OR DELETE
    OR UPDATE OF status, delivery_review_status, property_id
  ON public.photo_shoot_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_photo_shoot_sync_property_state();

-- 3) ترقيع تلقائي للإعلانات الحالية (بلا أي تدخل يدوي).
UPDATE public.properties p
SET default_cover_used = NOT coalesce(
  (nullif(trim(coalesce(p.image_url, '')), '') IS NOT NULL
     AND trim(p.image_url) <> '__smart_branding_cover__')
  OR nullif(trim(coalesce(p.video_url, '')), '') IS NOT NULL
  OR nullif(trim(coalesce(p.virtual_tour_url, '')), '') IS NOT NULL
  OR (jsonb_typeof(p.listing_guidance -> 'image_paths') = 'array'
      AND jsonb_array_length(p.listing_guidance -> 'image_paths') > 0)
  OR (jsonb_typeof(p.listing_guidance -> 'in_app_tour') = 'object'
      AND p.listing_guidance -> 'in_app_tour' <> '{}'::jsonb),
  false
);

DO $$
DECLARE pid uuid;
BEGIN
  FOR pid IN
    SELECT DISTINCT property_id FROM public.photo_shoot_requests
    WHERE property_id IS NOT NULL
  LOOP
    PERFORM public.recompute_property_photo_shoot_state(pid);
  END LOOP;
END;
$$;

COMMIT;
