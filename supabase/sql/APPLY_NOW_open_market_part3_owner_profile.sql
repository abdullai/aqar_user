-- =============================================================================
-- APPLY NOW جزء 3/3 — قراءة ملف صاحب طلب السوق المفتوح
-- نفّذ بعد نجاح الجزء 2 — بدون كتلة DO (لتجنب انقطاع اللصق)
-- =============================================================================

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
