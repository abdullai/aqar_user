-- =============================================================================
-- إصلاح فوري: 401 على الرئيسية عند select=*,property_images(...)
-- نفّذ في Supabase → SQL Editor (مشروع czfvqhepsqkgsrfnknwm)
-- =============================================================================
-- نفس محتوى: 20260429_guest_public_home_images_read_policy.sql

BEGIN;

GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.property_images TO anon, authenticated;
GRANT SELECT ON public.market_property_requests TO anon, authenticated;

ALTER TABLE public.property_images ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.property_image_public_home_readable(
  p_property_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT p_property_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = p_property_id
        AND public.property_public_publish_ready(p)
    );
$$;

REVOKE ALL ON FUNCTION public.property_image_public_home_readable(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_image_public_home_readable(uuid)
  TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "property_images_public_home_select"
  ON public.property_images;

CREATE POLICY "property_images_public_home_select"
  ON public.property_images
  FOR SELECT
  TO anon, authenticated
  USING (public.property_image_public_home_readable(property_id));

COMMENT ON POLICY "property_images_public_home_select"
  ON public.property_images IS
  'Guest/home-feed image embed — requires property_public_publish_ready on parent row.';

COMMIT;

SELECT count(*)::bigint AS sample_images_readable
FROM public.property_images pi
WHERE public.property_image_public_home_readable(pi.property_id);
