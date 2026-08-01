-- =============================================================================
-- Public home feed: restore anon/authenticated EXECUTE on RLS helper functions.
--
-- Symptom (Flutter/web guest + logged-in home): PostgREST 401/42501
--   permission denied for function property_marketer_public_verified
-- when selecting from public.properties (policy calls property_public_publish_ready).
--
-- The policy SQL lived under supabase/sql/20260429_* but was never in migrations;
-- this idempotent patch only (re)applies grants if the functions exist.
-- =============================================================================

BEGIN;

DO $grant_home_feed_helpers$
DECLARE
  fn regprocedure;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'public.property_has_listing_media(uuid,text)',
    'public.property_marketer_public_verified(uuid)',
    'public.property_has_rega_publish_payload(jsonb,jsonb)',
    'public.property_has_rega_publish_payload_for_property(uuid,jsonb)',
    'public.property_license_payload(uuid,jsonb)',
    'public.property_public_publish_ready(public.properties)',
    'public.property_image_public_home_readable(uuid)'
  ]::regprocedure[]
  LOOP
    IF to_regprocedure(fn::text) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', fn);
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role',
        fn
      );
    END IF;
  END LOOP;
END
$grant_home_feed_helpers$;

GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.property_images TO anon, authenticated;
GRANT SELECT ON public.market_property_requests TO anon, authenticated;

COMMIT;
