-- =============================================================================
-- Development-only backfill: restore previously public listings
--
-- Purpose:
--   Use only during development to make old listings that were already in the
--   public home feed visible again after adding the FAL/REGA requirements.
--   Do not use this to publish listings that are still in the marketing flow.
--
-- Business rule kept:
--   Listings are assigned only to marketer/business accounts, not individual
--   sellers, even if an individual has a license number in development data.
-- =============================================================================

-- Preview: these are the only rows this script is allowed to restore.
SELECT
  p.id,
  p.title,
  p.status,
  p.workflow_stage,
  p.home_feed_suppressed,
  p.published_by_marketer_id,
  public.property_has_listing_media(p.id, p.video_url) AS has_listing_media,
  public.property_public_publish_ready(p) AS public_ready_now
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
  AND public.property_has_listing_media(p.id, p.video_url)
  AND p.status IN (
    'published', 'active', 'available', 'live', 'reserved',
    'approved', 'listed', 'open', 'visible',
    'for_sale', 'for_rent', 'forsale', 'forrent'
  )
  AND COALESCE(p.workflow_stage::text, '') IN ('published', 'reserved')
ORDER BY p.created_at DESC;

BEGIN;

-- 1) Ensure the development publisher accounts carry FAL data.
WITH licensed_publishers AS (
  SELECT *
  FROM (
    VALUES
      (
        '96bad4d0-8463-46b5-9525-575f477b7c88'::uuid,
        '1100001234'::text,
        'marketer'::text
      ),
      (
        '5e5044c7-a2e0-4277-9700-9d4777b66724'::uuid,
        '1200005678'::text,
        'office'::text
      )
  ) AS v(user_id, fal_license_number, account_type_hint)
)
UPDATE public.users_profiles up
SET
  license_no = lp.fal_license_number,
  rega_fal_snapshot = COALESCE(up.rega_fal_snapshot, '{}'::jsonb)
    || jsonb_build_object(
      'fal_license_number', lp.fal_license_number,
      'fal_broker_license_number', lp.fal_license_number,
      'dev_backfill_only', true
    )
FROM licensed_publishers lp
WHERE up.user_id = lp.user_id;

-- 2) Temporarily bypass the edit-limit trigger for this maintenance backfill.
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

-- 3) Restore only listings that were already public-like before hardening.
--    REGA ad numbers are generated as development placeholders and marked as such.
WITH licensed_publishers AS (
  SELECT *
  FROM (
    VALUES
      (
        1,
        '96bad4d0-8463-46b5-9525-575f477b7c88'::uuid,
        '1100001234'::text
      ),
      (
        2,
        '5e5044c7-a2e0-4277-9700-9d4777b66724'::uuid,
        '1200005678'::text
      )
  ) AS v(slot_no, user_id, fal_license_number)
),
publisher_count AS (
  SELECT count(*)::int AS total
  FROM licensed_publishers
),
eligible_properties AS (
  SELECT
    p.id,
    row_number() OVER (ORDER BY p.created_at DESC, p.id) AS rn
  FROM public.properties p
  WHERE p.status IS DISTINCT FROM 'deleted'
    AND public.property_has_listing_media(p.id, p.video_url)
    AND p.status IN (
      'published', 'active', 'available', 'live', 'reserved',
      'approved', 'listed', 'open', 'visible',
      'for_sale', 'for_rent', 'forsale', 'forrent'
    )
    AND COALESCE(p.workflow_stage::text, '') IN ('published', 'reserved')
    AND COALESCE(p.workflow_stage::text, '') NOT IN (
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
),
assignment AS (
  SELECT
    ep.id AS property_id,
    lp.user_id AS publisher_id,
    lp.fal_license_number,
    up.full_name AS publisher_display_name,
    ('71' || lpad((10000000 + ep.rn)::text, 8, '0')) AS dev_rega_ad_license_number
  FROM eligible_properties ep
  CROSS JOIN publisher_count pc
  JOIN licensed_publishers lp
    ON lp.slot_no = ((ep.rn - 1) % pc.total) + 1
  JOIN public.users_profiles up
    ON up.user_id = lp.user_id
)
UPDATE public.properties p
SET
  status = CASE WHEN p.status = 'active' THEN 'active' ELSE 'published' END,
  workflow_stage = CASE WHEN p.workflow_stage = 'reserved' THEN 'reserved' ELSE 'published' END,
  home_feed_suppressed = false,
  published_by_marketer_id = a.publisher_id,
  published_at = COALESCE(p.published_at, now()),
  rega_payload = COALESCE(p.rega_payload, '{}'::jsonb)
    || jsonb_build_object(
      'fal_license_number', a.fal_license_number,
      'fal_broker_license_number', a.fal_license_number,
      'rega_ad_license_number', a.dev_rega_ad_license_number,
      'ad_license_number', a.dev_rega_ad_license_number,
      'marketer_display_name', a.publisher_display_name,
      'marketer_entity_display_name', a.publisher_display_name,
      'dev_backfill_only', true
    )
FROM assignment a
WHERE p.id = a.property_id;

-- 4) Re-enable the edit-limit trigger.
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

-- 5) Verify public visibility and publisher distribution.
SELECT
  'public_ready_visible_count' AS check_name,
  count(*)::bigint AS count
FROM public.properties p
WHERE public.property_public_publish_ready(p);

SELECT
  p.published_by_marketer_id,
  up.full_name,
  up.account_type,
  up.license_no,
  count(*)::bigint AS published_listings
FROM public.properties p
LEFT JOIN public.users_profiles up
  ON up.user_id = p.published_by_marketer_id
WHERE public.property_public_publish_ready(p)
GROUP BY
  p.published_by_marketer_id,
  up.full_name,
  up.account_type,
  up.license_no
ORDER BY published_listings DESC;
