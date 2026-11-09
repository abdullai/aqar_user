DO $$
BEGIN
  IF to_regprocedure('public.property_has_listing_media(uuid,text)') IS NULL
    OR to_regprocedure('public.property_marketer_public_verified(uuid)') IS NULL
    OR to_regprocedure('public.property_has_rega_publish_payload(jsonb,jsonb)') IS NULL
    OR to_regprocedure('public.property_license_payload(uuid,jsonb)') IS NULL
    OR to_regprocedure(
      'public.property_has_rega_publish_payload_for_property(uuid,jsonb)'
    ) IS NULL
    OR to_regprocedure(
      'public.property_public_publish_ready(public.properties)'
    ) IS NULL THEN
    RAISE EXCEPTION
      'Apply supabase/sql/20260429_public_home_marketer_publish_ready_policy.sql before this migration';
  END IF;
END;
$$;

GRANT SELECT ON public.property_images TO anon, authenticated;

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

REVOKE ALL
  ON FUNCTION public.property_image_public_home_readable(uuid)
  FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION public.property_image_public_home_readable(uuid)
  TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "property_images_public_home_select"
  ON public.property_images;

CREATE POLICY "property_images_public_home_select"
  ON public.property_images
  FOR SELECT
  TO anon, authenticated
  USING (
    public.property_image_public_home_readable(property_id)
  );
