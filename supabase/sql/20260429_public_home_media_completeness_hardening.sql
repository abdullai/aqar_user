-- =============================================================================
-- Public home feed media completeness hardening
--
-- Run after 20260429_public_home_marketer_publish_ready_policy.sql.
--
-- Goal:
--   - Public listings must have real listing media: property_images row or video.
--   - Old published rows without media are suppressed from the public home feed.
--   - Internal marketing stages remain available only through owner/marketer flows.
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

DROP POLICY IF EXISTS "properties_public_home_select" ON public.properties;

CREATE POLICY "properties_public_home_select"
ON public.properties
FOR SELECT
TO anon, authenticated
USING (
  status IS DISTINCT FROM 'deleted'
  AND COALESCE(home_feed_suppressed, false) = false
  AND NULLIF(TRIM(COALESCE(published_by_marketer_id::text, '')), '') IS NOT NULL
  AND public.property_marketer_public_verified(published_by_marketer_id)
  AND public.property_has_rega_publish_payload_for_property(
    id,
    COALESCE(rega_payload::jsonb, '{}'::jsonb)
  )
  AND public.property_has_listing_media(id, video_url)
  AND COALESCE(workflow_stage::text, '') NOT IN (
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
    status IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      status = 'draft'
      AND workflow_stage IN ('published', 'reserved')
    )
  )
);

COMMENT ON POLICY "properties_public_home_select" ON public.properties IS
  'Public home feed: marketer/business verified + REGA/FAL payload + real media; internal marketing stages stay private.';

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND c.relname = 'properties'
      AND p.proname = 'enforce_property_edit_limit'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format('ALTER TABLE public.properties DISABLE TRIGGER %I', r.tgname);
  END LOOP;
END $$;

UPDATE public.properties p
SET home_feed_suppressed = true
WHERE p.status IN (
    'published', 'active', 'available', 'live', 'reserved',
    'approved', 'listed', 'open', 'visible',
    'for_sale', 'for_rent', 'forsale', 'forrent'
  )
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND NOT public.property_has_listing_media(p.id, p.video_url);

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname = 'public'
      AND c.relname = 'properties'
      AND p.proname = 'enforce_property_edit_limit'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format('ALTER TABLE public.properties ENABLE TRIGGER %I', r.tgname);
  END LOOP;
END $$;

COMMIT;

SELECT
  'public_visible_without_media_remaining' AS check_name,
  count(*)::bigint AS count
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND COALESCE(p.home_feed_suppressed, false) = false
  AND (
    p.status IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    OR (
      p.status = 'draft'
      AND p.workflow_stage IN ('published', 'reserved')
    )
  )
  AND NOT public.property_has_listing_media(p.id, p.video_url);

SELECT
  p.id,
  p.title,
  p.status,
  p.workflow_stage,
  p.home_feed_suppressed,
  public.property_has_listing_media(p.id, p.video_url) AS has_listing_media
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
ORDER BY p.created_at DESC;
