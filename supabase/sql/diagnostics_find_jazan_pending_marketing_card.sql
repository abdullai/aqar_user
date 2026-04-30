-- =============================================================================
-- Find the Jazan pending marketing card shown in "My page"
--
-- The card labels in the UI ("دعوة", "قيد الانتظار", "المعلن (المالك)") are
-- rendered from marketing workflow rows, not from hard-coded demo data.
-- Run this SELECT first, then delete by the exact id you confirm.
-- =============================================================================

WITH listing_request_candidates AS (
  SELECT
    'listing_requests' AS source_table,
    lr.id::text AS row_id,
    lr.preview_property_id::text AS related_property_id,
    lr.owner_id::text AS owner_id,
    NULL::text AS marketer_id,
    lr.title::text AS title,
    lr.city::text AS city,
    lr.status::text AS status,
    lr.workflow_stage::text AS workflow_stage,
    lr.created_at
  FROM public.listing_requests lr
  WHERE lower(coalesce(lr.city::text, '')) IN ('جازان', 'jazan', 'jizan')
     OR lower(coalesce(lr.title::text, '')) IN ('جديد', 'new')
     OR lower(coalesce(lr.status::text, '')) IN ('pending', 'new', 'invited')
),
invite_candidates AS (
  SELECT
    'listing_request_invites' AS source_table,
    inv.id::text AS row_id,
    coalesce(
      to_jsonb(inv) ->> 'request_id',
      to_jsonb(inv) ->> 'listing_request_id'
    ) AS related_property_id,
    NULL::text AS owner_id,
    inv.marketer_id::text AS marketer_id,
    NULL::text AS title,
    NULL::text AS city,
    inv.status::text AS status,
    NULL::text AS workflow_stage,
    inv.created_at
  FROM public.listing_request_invites inv
  WHERE lower(coalesce(inv.status::text, '')) IN ('pending', 'new', 'invited')
),
property_candidates AS (
  SELECT
    'properties' AS source_table,
    p.id::text AS row_id,
    p.request_id::text AS related_property_id,
    p.owner_id::text AS owner_id,
    p.published_by_marketer_id::text AS marketer_id,
    p.title::text AS title,
    p.city::text AS city,
    p.status::text AS status,
    p.workflow_stage::text AS workflow_stage,
    p.created_at
  FROM public.properties p
  WHERE lower(coalesce(p.city::text, '')) IN ('جازان', 'jazan', 'jizan')
     OR lower(coalesce(p.title::text, '')) IN ('جديد', 'new')
     OR lower(coalesce(p.status::text, '')) IN ('pending', 'new', 'invited')
)
SELECT *
FROM (
  SELECT * FROM listing_request_candidates
  UNION ALL
  SELECT * FROM invite_candidates
  UNION ALL
  SELECT * FROM property_candidates
) q
ORDER BY created_at DESC NULLS LAST
LIMIT 50;

-- After confirming the exact row_id/source_table, delete explicitly, for example:
--
-- BEGIN;
-- DELETE FROM public.listing_request_invites WHERE id = '<confirmed_invite_id>';
-- DELETE FROM public.listing_requests WHERE id = '<confirmed_request_id>';
-- DELETE FROM public.properties WHERE id = '<confirmed_property_id>';
-- COMMIT;
