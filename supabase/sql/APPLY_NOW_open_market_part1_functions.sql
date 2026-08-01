-- =============================================================================
-- APPLY NOW جزء 1/3 — دوال قراءة السوق المفتوح
-- نفّذ هذا وحده أولاً. المتوقع: Success
-- =============================================================================

CREATE OR REPLACE FUNCTION public.auth_is_marketing_account()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $fn$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE up.user_id = auth.uid()
      AND lower(trim(coalesce(up.account_type::text, ''))) IN (
        'marketer', 'office', 'company', 'institution', 'agency'
      )
  );
$fn$;

REVOKE ALL ON FUNCTION public.auth_is_marketing_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_is_marketing_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_is_marketing_account() TO service_role;

CREATE OR REPLACE FUNCTION public.marketer_can_read_open_market_listing_request(req_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $fn$
  SELECT req_id IS NOT NULL
  AND public.auth_is_marketing_account()
  AND EXISTS (
    SELECT 1
    FROM public.listing_requests lr
    WHERE lr.id = req_id
      AND lr.owner_id IS DISTINCT FROM auth.uid()
      AND lr.selected_marketer_id IS NULL
      AND lower(trim(coalesce(lr.workflow_stage, ''))) = 'waiting_marketers'
  );
$fn$;

REVOKE ALL ON FUNCTION public.marketer_can_read_open_market_listing_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_open_market_listing_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_open_market_listing_request(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.marketer_can_read_listing_request(req_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $fn$
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
  )
  OR public.marketer_can_read_open_market_listing_request(req_id);
$fn$;

REVOKE ALL ON FUNCTION public.marketer_can_read_listing_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_listing_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_listing_request(uuid) TO service_role;
