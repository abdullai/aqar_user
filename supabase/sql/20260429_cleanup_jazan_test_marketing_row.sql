-- =============================================================================
-- Cleanup the incomplete "جديد - جازان" marketing test row
--
-- Confirmed by diagnostics_find_jazan_pending_marketing_card.sql:
--   listing_requests.id        = afd27763-9bba-479f-a9dd-85fce8181a06
--   listing_request_invites.id = 4abcc6e6-2317-4f3e-b4c3-ece4ecbb7c8b
--
-- This row has no preview_property_id / related property, so it renders as an
-- incomplete pending invite card. Run this only if you want to remove that test
-- card from the database.
-- =============================================================================

BEGIN;

DELETE FROM public.listing_request_invites
WHERE id = '4abcc6e6-2317-4f3e-b4c3-ece4ecbb7c8b'::uuid;

DELETE FROM public.listing_requests
WHERE id = 'afd27763-9bba-479f-a9dd-85fce8181a06'::uuid;

COMMIT;

-- Verify it is gone:
SELECT
  'jazan_test_listing_request_remaining' AS check_name,
  count(*)::bigint AS count
FROM public.listing_requests
WHERE id = 'afd27763-9bba-479f-a9dd-85fce8181a06'::uuid
UNION ALL
SELECT
  'jazan_test_invite_remaining' AS check_name,
  count(*)::bigint AS count
FROM public.listing_request_invites
WHERE id = '4abcc6e6-2317-4f3e-b4c3-ece4ecbb7c8b'::uuid;

-- Optional manual audit for incomplete marketing rows before editing/deleting:
SELECT
  lr.id,
  lr.title,
  lr.city,
  lr.status,
  lr.workflow_stage,
  lr.preview_property_id,
  lr.created_at
FROM public.listing_requests lr
WHERE lr.preview_property_id IS NULL
   OR NULLIF(TRIM(COALESCE(lr.title::text, '')), '') IS NULL
   OR NULLIF(TRIM(COALESCE(lr.city::text, '')), '') IS NULL
ORDER BY lr.created_at DESC
LIMIT 50;
