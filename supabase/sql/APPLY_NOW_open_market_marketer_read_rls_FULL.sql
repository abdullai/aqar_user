-- =============================================================================
-- APPLY NOW: سوق مفتوح كامل — بدون DO $$ وبدون BEGIN (نسخة مستقرة للصق)
-- افتح الملف من القرص وانسخه كاملاً؛ لا تنسخ من الشات.
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

DROP POLICY IF EXISTS "marketer_select_linked_listing_requests" ON public.listing_requests;
CREATE POLICY "marketer_select_linked_listing_requests"
  ON public.listing_requests FOR SELECT TO authenticated
  USING (public.marketer_can_read_listing_request(id));

CREATE OR REPLACE FUNCTION public.marketer_can_read_property_for_marketing(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $fn$
  SELECT p_property_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.listing_requests lr
    WHERE (
        lr.preview_property_id = p_property_id
        OR EXISTS (
          SELECT 1 FROM public.properties p
          WHERE p.id = p_property_id
            AND p.request_id IS NOT NULL
            AND p.request_id = lr.id
        )
      )
      AND (
        EXISTS (
          SELECT 1 FROM public.listing_request_invites inv
          WHERE inv.request_id = lr.id AND inv.marketer_id = auth.uid()
        )
        OR EXISTS (
          SELECT 1 FROM public.listing_offers o
          WHERE o.request_id = lr.id AND o.marketer_id = auth.uid()
        )
        OR (
          public.auth_is_marketing_account()
          AND lr.owner_id IS DISTINCT FROM auth.uid()
          AND lr.selected_marketer_id IS NULL
          AND lower(trim(coalesce(lr.workflow_stage, ''))) = 'waiting_marketers'
        )
      )
  );
$fn$;

REVOKE ALL ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_property_for_marketing(uuid) TO service_role;

DROP POLICY IF EXISTS "marketer_select_linked_preview_properties" ON public.properties;
DROP POLICY IF EXISTS "marketer_select_linked_preview_properties_v2" ON public.properties;
CREATE POLICY "marketer_select_linked_preview_properties_v2"
  ON public.properties FOR SELECT TO authenticated
  USING (public.marketer_can_read_property_for_marketing(id));

DROP POLICY IF EXISTS "marketer_select_linked_property_images" ON public.property_images;
DROP POLICY IF EXISTS "marketer_select_linked_property_images_v2" ON public.property_images;
CREATE POLICY "marketer_select_linked_property_images_v2"
  ON public.property_images FOR SELECT TO authenticated
  USING (public.marketer_can_read_property_for_marketing(property_images.property_id));

CREATE OR REPLACE FUNCTION public.marketer_can_read_open_market_request_owner(p_owner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $fn$
  SELECT p_owner_id IS NOT NULL
  AND public.auth_is_marketing_account()
  AND p_owner_id IS DISTINCT FROM auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.listing_requests lr
    WHERE lr.owner_id = p_owner_id
      AND lr.selected_marketer_id IS NULL
      AND lower(trim(coalesce(lr.workflow_stage, ''))) = 'waiting_marketers'
  );
$fn$;

REVOKE ALL ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) TO service_role;

DROP POLICY IF EXISTS "Marketers read open-market owner users_profiles" ON public.users_profiles;
CREATE POLICY "Marketers read open-market owner users_profiles"
  ON public.users_profiles FOR SELECT TO authenticated
  USING (public.marketer_can_read_open_market_request_owner(users_profiles.user_id));
