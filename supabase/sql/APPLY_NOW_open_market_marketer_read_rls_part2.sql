-- =============================================================================
-- تكملة إصلاح السوق المفتوح — نفّذ هذا بعد نجاح الجزء الأول
-- (الدوال + سياسة listing_requests + marketer_can_read_property_for_marketing)
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "marketer_select_linked_preview_properties" ON public.properties;
DROP POLICY IF EXISTS "marketer_select_linked_preview_properties_v2" ON public.properties;

CREATE POLICY "marketer_select_linked_preview_properties_v2"
  ON public.properties
  FOR SELECT
  TO authenticated
  USING (public.marketer_can_read_property_for_marketing(id));

DROP POLICY IF EXISTS "marketer_select_linked_property_images" ON public.property_images;
DROP POLICY IF EXISTS "marketer_select_linked_property_images_v2" ON public.property_images;

CREATE POLICY "marketer_select_linked_property_images_v2"
  ON public.property_images
  FOR SELECT
  TO authenticated
  USING (public.marketer_can_read_property_for_marketing(property_images.property_id));

CREATE OR REPLACE FUNCTION public.marketer_can_read_open_market_request_owner(p_owner_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
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
$$;

COMMENT ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) IS
  'RLS: قراءة ملف صاحب طلب سوق مفتوح للحسابات التسويقية.';

REVOKE ALL ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marketer_can_read_open_market_request_owner(uuid) TO service_role;

DROP POLICY IF EXISTS "Marketers read open-market owner users_profiles" ON public.users_profiles;

CREATE POLICY "Marketers read open-market owner users_profiles"
  ON public.users_profiles
  FOR SELECT
  TO authenticated
  USING (public.marketer_can_read_open_market_request_owner(users_profiles.user_id));

DO $$
BEGIN
  IF to_regclass('public.profiles') IS NOT NULL THEN
    EXECUTE $p$
      DROP POLICY IF EXISTS "Marketers read open-market owner profiles" ON public.profiles;
      CREATE POLICY "Marketers read open-market owner profiles"
        ON public.profiles
        FOR SELECT
        TO authenticated
        USING (public.marketer_can_read_open_market_request_owner(profiles.id));
    $p$;
  END IF;
END $$;

COMMIT;
