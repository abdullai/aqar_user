-- =============================================================================
-- Public home feed policy: marketer/office publish readiness
--
-- Correct business rule:
--   - The owner/individual does NOT need business verification to be shown.
--   - The public listing must be published by a verified/qualified marketer,
--     office, organization, or real-estate company.
--   - The listing must have REGA/FAL ad payload and real media.
--
-- Run in Supabase SQL Editor as project owner/postgres.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.property_has_listing_media(
  p_property_id uuid,
  p_video_url text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    NULLIF(TRIM(COALESCE(p_video_url, '')), '') IS NOT NULL
    OR EXISTS (
      SELECT 1
      FROM public.property_images pi
      WHERE pi.property_id = p_property_id
        AND NULLIF(TRIM(COALESCE(pi.path::text, pi.file_name::text, '')), '') IS NOT NULL
    );
$$;

REVOKE ALL ON FUNCTION public.property_has_listing_media(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_has_listing_media(uuid, text)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.property_marketer_public_verified(
  p_marketer_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE up.user_id = p_marketer_id
      AND (
        COALESCE(up.account_type::text, '') IN (
          'marketer',
          'broker',
          'office',
          'agency',
          'company',
          'organization',
          'real_estate_office',
          'real_estate_company',
          'verified_business',
          'business'
        )
        OR COALESCE(up.verification_status::text, '') IN (
          'verified_business',
          'approved'
        )
      )
      AND (
        NULLIF(TRIM(COALESCE(up.license_no::text, '')), '') IS NOT NULL
        OR up.rega_fal_snapshot IS NOT NULL
      )
  );
$$;

REVOKE ALL ON FUNCTION public.property_marketer_public_verified(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_marketer_public_verified(uuid)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.property_has_rega_publish_payload(
  p_rega_payload jsonb,
  p_marketing_license_snapshot jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH snap AS (
    SELECT COALESCE(p_rega_payload, '{}'::jsonb)
           || COALESCE(p_marketing_license_snapshot, '{}'::jsonb) AS j
  )
  SELECT EXISTS (
    SELECT 1
    FROM snap
    WHERE NULLIF(TRIM(COALESCE(
        j ->> 'rega_ad_license_number',
        j ->> 'ad_license_number',
        j ->> 'advertisement_license_number',
        j ->> 'advertising_license_number',
        j ->> 'license_number',
        ''
      )), '') IS NOT NULL
      AND NULLIF(TRIM(COALESCE(
        j ->> 'fal_broker_license_number',
        j ->> 'fal_license_number',
        j ->> 'broker_license_number',
        j ->> 'brokerage_license_number',
        ''
      )), '') IS NOT NULL
  );
$$;

REVOKE ALL ON FUNCTION public.property_has_rega_publish_payload(jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_has_rega_publish_payload(jsonb, jsonb)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.property_license_payload(
  p_property_id uuid,
  p_rega_payload jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  out_payload jsonb := COALESCE(p_rega_payload, '{}'::jsonb);
  legacy_payload jsonb := '{}'::jsonb;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'properties'
      AND column_name = 'marketing_license_snapshot'
  ) THEN
    EXECUTE
      'SELECT COALESCE(marketing_license_snapshot::jsonb, ''{}''::jsonb)
       FROM public.properties
       WHERE id = $1'
      INTO legacy_payload
      USING p_property_id;
  END IF;

  RETURN out_payload || COALESCE(legacy_payload, '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.property_license_payload(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_license_payload(uuid, jsonb)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.property_has_rega_publish_payload_for_property(
  p_property_id uuid,
  p_rega_payload jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.property_has_rega_publish_payload(
    public.property_license_payload(p_property_id, p_rega_payload),
    '{}'::jsonb
  );
$$;

REVOKE ALL ON FUNCTION public.property_has_rega_publish_payload_for_property(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_has_rega_publish_payload_for_property(uuid, jsonb)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.property_public_publish_ready(
  p_property public.properties
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    (p_property).status IS DISTINCT FROM 'deleted'
    AND COALESCE((p_property).home_feed_suppressed, false) = false
    AND public.property_has_listing_media((p_property).id, (p_property).video_url)
    AND NULLIF(TRIM(COALESCE((p_property).published_by_marketer_id::text, '')), '') IS NOT NULL
    AND public.property_marketer_public_verified((p_property).published_by_marketer_id)
    AND public.property_has_rega_publish_payload_for_property(
      (p_property).id,
      COALESCE((p_property).rega_payload::jsonb, '{}'::jsonb)
    )
    AND COALESCE((p_property).workflow_stage::text, '') NOT IN (
      'waiting_marketers',
      'marketer_selected',
      'contract_pending',
      'contract_sent',
      'contract_returned',
      'contract_signed',
      'permit_pending',
      'permit_issued',
      'inactive_72h'
    )
    AND (
      (p_property).status IN (
        'published', 'active', 'available', 'live', 'reserved',
        'approved', 'listed', 'open', 'visible',
        'for_sale', 'for_rent', 'forsale', 'forrent'
      )
      OR (
        (p_property).status = 'draft'
        AND (p_property).workflow_stage IN ('published', 'reserved')
      )
    );
$$;

REVOKE ALL ON FUNCTION public.property_public_publish_ready(public.properties) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.property_public_publish_ready(public.properties)
  TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;

CREATE POLICY "properties_public_home_select"
ON public.properties
FOR SELECT
TO anon, authenticated
USING (public.property_public_publish_ready(properties));

COMMENT ON POLICY "properties_public_home_select" ON public.properties IS
  'Public home feed: owner may be individual; listing must be published by verified/FAL-backed marketer or business with REGA ad payload and media.';

COMMIT;

SELECT
  'public_ready_visible_count' AS check_name,
  count(*)::bigint AS count
FROM public.properties p
WHERE public.property_public_publish_ready(p);
