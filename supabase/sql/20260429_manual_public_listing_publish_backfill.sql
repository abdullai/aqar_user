-- =============================================================================
-- Manual backfill: make old development listings eligible for public home feed
--
-- Use after:
--   1) 20260429_public_home_marketer_publish_ready_policy.sql
--   2) diagnostics_public_listing_publish_readiness.sql
--
-- This file is intentionally safe by default. The input CTE uses NULL values,
-- so it will not update anything until you fill real property/license values.
-- =============================================================================

-- 1) Show rows that are closest to being public-ready.
SELECT
  p.id,
  p.title,
  p.status,
  p.workflow_stage,
  p.home_feed_suppressed,
  p.published_by_marketer_id,
  marketer.full_name AS marketer_name,
  marketer.account_type AS marketer_account_type,
  marketer.verification_status AS marketer_verification_status,
  marketer.license_no AS marketer_license_no,
  public.property_has_listing_media(p.id, p.video_url) AS has_listing_media,
  public.property_marketer_public_verified(p.published_by_marketer_id) AS marketer_public_verified,
  public.property_has_rega_publish_payload_for_property(
    p.id,
    COALESCE(p.rega_payload::jsonb, '{}'::jsonb)
  ) AS has_rega_fal_payload,
  public.property_public_publish_ready(p) AS public_ready,
  public.property_license_payload(
    p.id,
    COALESCE(p.rega_payload::jsonb, '{}'::jsonb)
  ) AS current_license_payload
FROM public.properties p
LEFT JOIN public.users_profiles marketer
  ON marketer.user_id = p.published_by_marketer_id
WHERE p.status IS DISTINCT FROM 'deleted'
  AND public.property_has_listing_media(p.id, p.video_url)
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
ORDER BY p.created_at DESC;

-- 2) Show marketer/business accounts that still need FAL data.
SELECT
  up.user_id,
  up.full_name,
  up.account_type,
  up.verification_status,
  up.license_no,
  up.rega_fal_snapshot,
  public.property_marketer_public_verified(up.user_id) AS marketer_public_verified
FROM public.users_profiles up
WHERE COALESCE(up.account_type::text, '') IN (
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
ORDER BY marketer_public_verified ASC, up.created_at DESC NULLS LAST;

-- 3) Fill real values here, then run this transaction.
--    Do not put fake license numbers. These must match the official REGA/FAL data.
BEGIN;

WITH input AS (
  SELECT
    NULL::uuid AS property_id,
    NULL::uuid AS marketer_id,
    NULL::text AS fal_license_number,
    NULL::text AS rega_ad_license_number
),
valid_input AS (
  SELECT *
  FROM input
  WHERE property_id IS NOT NULL
    AND marketer_id IS NOT NULL
    AND NULLIF(TRIM(fal_license_number), '') IS NOT NULL
    AND NULLIF(TRIM(rega_ad_license_number), '') IS NOT NULL
)
UPDATE public.users_profiles up
SET
  license_no = COALESCE(NULLIF(TRIM(up.license_no::text), ''), vi.fal_license_number),
  rega_fal_snapshot = COALESCE(up.rega_fal_snapshot, '{}'::jsonb)
    || jsonb_build_object(
      'fal_license_number', vi.fal_license_number,
      'updated_from_manual_public_listing_backfill', true
    )
FROM valid_input vi
WHERE up.user_id = vi.marketer_id;

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

WITH input AS (
  SELECT
    NULL::uuid AS property_id,
    NULL::uuid AS marketer_id,
    NULL::text AS fal_license_number,
    NULL::text AS rega_ad_license_number
),
valid_input AS (
  SELECT *
  FROM input
  WHERE property_id IS NOT NULL
    AND marketer_id IS NOT NULL
    AND NULLIF(TRIM(fal_license_number), '') IS NOT NULL
    AND NULLIF(TRIM(rega_ad_license_number), '') IS NOT NULL
)
UPDATE public.properties p
SET
  published_by_marketer_id = vi.marketer_id,
  status = CASE WHEN p.status = 'draft' THEN 'active' ELSE p.status END,
  workflow_stage = 'published',
  home_feed_suppressed = false,
  published_at = COALESCE(p.published_at, now()),
  rega_payload = COALESCE(p.rega_payload, '{}'::jsonb)
    || jsonb_build_object(
      'fal_license_number', vi.fal_license_number,
      'fal_broker_license_number', vi.fal_license_number,
      'rega_ad_license_number', vi.rega_ad_license_number,
      'ad_license_number', vi.rega_ad_license_number
    )
FROM valid_input vi
WHERE p.id = vi.property_id;

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

-- 4) Re-check after filling input values and running the transaction.
SELECT
  'public_ready_visible_count' AS check_name,
  count(*)::bigint AS count
FROM public.properties p
WHERE public.property_public_publish_ready(p);
