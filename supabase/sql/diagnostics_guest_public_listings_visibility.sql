-- =============================================================================
-- Guest public listings visibility diagnostics
--
-- Run in Supabase SQL Editor. This confirms whether real-estate listings should
-- appear for guest users, and why any listing is excluded from public home.
-- =============================================================================

-- 1) Final answer: rows visible to the guest/public home policy.
SELECT
  'guest_public_ready_properties' AS check_name,
  count(*)::bigint AS count
FROM public.properties p
WHERE public.property_public_publish_ready(p);

-- 2) Public listings that also have readable embedded images.
SELECT
  'guest_public_ready_properties_with_images' AS check_name,
  count(DISTINCT p.id)::bigint AS count
FROM public.properties p
WHERE public.property_public_publish_ready(p)
  AND EXISTS (
    SELECT 1
    FROM public.property_images pi
    WHERE pi.property_id = p.id
      AND public.property_image_public_home_readable(pi.property_id)
  );

-- 3) Grants required for PostgREST anon reads.
SELECT
  'anon_select_grants' AS check_name,
  table_name,
  bool_or(privilege_type = 'SELECT') AS has_select
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee = 'anon'
  AND table_name IN ('properties', 'property_images', 'market_property_requests')
GROUP BY table_name
ORDER BY table_name;

-- 4) RLS policies currently attached to the two tables used by the Flutter query.
SELECT
  'public_home_policies' AS check_name,
  schemaname,
  tablename,
  policyname,
  cmd,
  roles,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('properties', 'property_images')
ORDER BY tablename, policyname;

-- 5) Per-listing exclusion reasons for manual fixing.
SELECT
  p.id,
  p.title,
  p.city,
  p.status,
  p.workflow_stage,
  p.home_feed_suppressed,
  p.published_by_marketer_id,
  public.property_has_listing_media(p.id, p.video_url) AS has_media,
  CASE
    WHEN p.status = 'deleted' THEN 'deleted'
    WHEN coalesce(p.home_feed_suppressed, false) THEN 'home_feed_suppressed'
    WHEN NOT public.property_has_listing_media(p.id, p.video_url) THEN 'missing_media'
    WHEN nullif(trim(coalesce(p.published_by_marketer_id::text, '')), '') IS NULL THEN 'missing_published_by_marketer_id'
    WHEN NOT public.property_marketer_public_verified(p.published_by_marketer_id) THEN 'marketer_not_public_verified'
    WHEN NOT public.property_has_rega_publish_payload_for_property(p.id, coalesce(p.rega_payload::jsonb, '{}'::jsonb)) THEN 'missing_rega_or_fal_payload'
    WHEN coalesce(p.workflow_stage::text, '') IN (
      'waiting_marketers',
      'marketer_selected',
      'contract_pending',
      'contract_sent',
      'contract_returned',
      'contract_signed',
      'permit_pending',
      'permit_issued',
      'inactive_72h'
    ) THEN 'internal_workflow_stage'
    WHEN NOT (
      p.status IN (
        'published', 'active', 'available', 'live', 'reserved',
        'approved', 'listed', 'open', 'visible',
        'for_sale', 'for_rent', 'forsale', 'forrent'
      )
      OR (
        p.status = 'draft'
        AND p.workflow_stage IN ('published', 'reserved')
      )
    ) THEN 'status_not_public'
    ELSE 'public_ready'
  END AS public_home_reason,
  p.created_at
FROM public.properties p
WHERE p.status IS DISTINCT FROM 'deleted'
ORDER BY
  (public.property_public_publish_ready(p)) DESC,
  p.created_at DESC NULLS LAST
LIMIT 100;
