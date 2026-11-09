BEGIN;

-- يربط غلاف العقار وقائمة صوره بجدول property_images دائماً، مهما كان مصدر
-- التغيير (نشر مباشر، طلب تسويق، اعتماد تسليم المصوّر، أو تعديل لاحق).
CREATE OR REPLACE FUNCTION public.sync_property_cover_from_images()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_pid uuid;
  v_paths text[];
BEGIN
  v_pid := CASE WHEN TG_OP = 'DELETE' THEN OLD.property_id ELSE NEW.property_id END;
  IF v_pid IS NULL THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  SELECT array_agg(pi.path ORDER BY pi.sort_order NULLS LAST, pi.path)
    INTO v_paths
  FROM public.property_images pi
  WHERE pi.property_id = v_pid
    AND nullif(trim(coalesce(pi.path, '')), '') IS NOT NULL
    AND coalesce(to_jsonb(pi) ->> 'media_type', 'image') <> 'video'
    AND lower(pi.path) !~ '\.(mp4|mov|webm|m4v)$';

  IF v_paths IS NOT NULL AND array_length(v_paths, 1) > 0 THEN
    UPDATE public.properties p
    SET image_url = v_paths[1],
        default_cover_used = false,
        listing_guidance = jsonb_set(
          CASE
            WHEN jsonb_typeof(p.listing_guidance) = 'object'
            THEN p.listing_guidance
            ELSE '{}'::jsonb
          END,
          '{image_paths}',
          to_jsonb(v_paths),
          true
        )
    WHERE p.id = v_pid
      AND (
        p.image_url IS DISTINCT FROM v_paths[1]
        OR p.default_cover_used IS DISTINCT FROM false
        OR (p.listing_guidance -> 'image_paths') IS DISTINCT FROM to_jsonb(v_paths)
      );
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_property_cover_from_images()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_property_cover_from_images
  ON public.property_images;
CREATE TRIGGER trg_sync_property_cover_from_images
  AFTER INSERT OR UPDATE OF path, sort_order OR DELETE
  ON public.property_images
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_property_cover_from_images();

-- ترقيع الإعلانات الحالية التي لها صور ولا غلاف محدد.
UPDATE public.properties p
SET image_url = s.first_path,
    default_cover_used = false
FROM (
  SELECT DISTINCT ON (pi.property_id)
    pi.property_id,
    pi.path AS first_path
  FROM public.property_images pi
  WHERE nullif(trim(coalesce(pi.path, '')), '') IS NOT NULL
    AND coalesce(to_jsonb(pi) ->> 'media_type', 'image') <> 'video'
    AND lower(pi.path) !~ '\.(mp4|mov|webm|m4v)$'
  ORDER BY pi.property_id, pi.sort_order NULLS LAST, pi.path
) s
WHERE p.id = s.property_id
  AND nullif(trim(coalesce(p.image_url, '')), '') IS NULL;

COMMIT;
