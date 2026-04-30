-- =============================================================================
-- Fix invites visibility/cards:
-- 1) Backfill listing_requests.preview_property_id from linked properties
-- 2) Ensure marketers can SELECT listing_requests that are linked to their
--    invites/offers (without RLS recursion)
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Backfill preview_property_id for existing listing requests
-- ---------------------------------------------------------------------------
WITH latest_prop AS (
  SELECT DISTINCT ON (p.request_id)
    p.request_id,
    p.id AS property_id
  FROM public.properties p
  WHERE p.request_id IS NOT NULL
  ORDER BY p.request_id, p.created_at DESC, p.updated_at DESC
)
UPDATE public.listing_requests r
SET
  preview_property_id = lp.property_id,
  updated_at = now()
FROM latest_prop lp
WHERE r.id = lp.request_id
  AND (r.preview_property_id IS NULL OR r.preview_property_id::text = '');

-- ---------------------------------------------------------------------------
-- 2) RLS helper + policy for marketers linked by invite/offer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketer_can_read_listing_request(req_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.listing_request_invites inv
    WHERE inv.request_id = req_id
      AND inv.marketer_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.listing_offers o
    WHERE o.request_id = req_id
      AND o.marketer_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.marketer_can_read_listing_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_listing_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_listing_request(uuid) TO service_role;

DROP POLICY IF EXISTS "marketer_select_linked_listing_requests"
  ON public.listing_requests;

CREATE POLICY "marketer_select_linked_listing_requests"
  ON public.listing_requests
  FOR SELECT
  TO authenticated
  USING (public.marketer_can_read_listing_request(id));

COMMIT;

