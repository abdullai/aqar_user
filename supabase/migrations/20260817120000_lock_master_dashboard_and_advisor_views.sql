-- =============================================================================
-- Lock public.master_dashboard + related Security Advisor view errors.
--
-- Why: master_dashboard joined auth.users and selected u.email (and national
-- ID / FAL license). If granted to anon/authenticated, any API client can
-- list every account. Flutter does not use this view.
--
-- Run in Supabase SQL Editor as postgres, then Rerun linter.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Rebuild master_dashboard without auth.users.
--    Email comes from users_profiles.contact_email (not auth.users.email).
-- -----------------------------------------------------------------------------
DROP VIEW IF EXISTS public.master_dashboard;

CREATE VIEW public.master_dashboard
WITH (security_invoker = true) AS
SELECT
  up.full_name_ar AS name_ar,
  up.full_name_en AS name_en,
  up.contact_email::character varying AS email,
  up.office_name,
  up.verification_status,
  up.is_licensed_marketer,
  up.unified_national_number AS unified_number_700,
  up.license_no AS fal_license_number,
  (
    SELECT count(*)::bigint
    FROM public.properties p
    WHERE p.owner_id = up.user_id
  ) AS properties_count,
  (
    SELECT count(*)::bigint
    FROM public.listing_offers lo
    WHERE lo.marketer_id = up.user_id
  ) AS offers_count,
  vh.expiry_date,
  CASE
    WHEN vh.expiry_date IS NULL THEN 'N/A'::text
    ELSE ((vh.expiry_date::date - CURRENT_DATE)::text) || ' days'::text
  END AS days_left
FROM public.users_profiles up
LEFT JOIN (
  SELECT DISTINCT ON (verification_history.user_id)
    verification_history.user_id,
    verification_history.expiry_date
  FROM public.verification_history
  ORDER BY verification_history.user_id, verification_history.verified_at DESC
) vh ON up.user_id = vh.user_id;

COMMENT ON VIEW public.master_dashboard IS
  'Admin-only profile overview. Not in the Data API. Does not read auth.users.';

REVOKE ALL ON public.master_dashboard FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.master_dashboard TO postgres, service_role;

-- -----------------------------------------------------------------------------
-- 2) Security invoker on the 12 Advisor-flagged views (skip missing names).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v text;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    'master_dashboard',
    'users_profiles_with_phone',
    'v_aqar_data_quality_summary',
    'v_aqar_data_quality_users',
    'v_aqar_data_quality_properties',
    'v_aqar_data_quality_listing_requests',
    'v_chat_list',
    'v_marketer_visible_offers',
    'v_property_invoice_breakdown'
  ]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'v' AND c.relname = v
    ) THEN
      EXECUTE format(
        'ALTER VIEW public.%I SET (security_invoker = true)',
        v
      );
    END IF;
  END LOOP;

  FOR v IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'v'
      AND (
        c.relname LIKE 'admin_property_delete_requests%'
        OR c.relname LIKE 'v_aqar_properties_missing_marketer%'
      )
  LOOP
    EXECUTE format(
      'ALTER VIEW public.%I SET (security_invoker = true)',
      v
    );
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 3) Admin / PII views: drop Data API access. Studio SQL (postgres) still works.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v text;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    'master_dashboard',
    'users_profiles_with_phone',
    'v_aqar_data_quality_summary'
  ]
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'v' AND c.relname = v
    ) THEN
      EXECUTE format(
        'REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated',
        v
      );
      EXECUTE format(
        'GRANT SELECT ON public.%I TO postgres, service_role',
        v
      );
    END IF;
  END LOOP;

  FOR v IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'v'
      AND (
        c.relname LIKE 'admin_property_delete_requests%'
        OR c.relname LIKE 'v_aqar_properties_missing_marketer%'
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated',
      v
    );
    EXECUTE format(
      'GRANT SELECT ON public.%I TO postgres, service_role',
      v
    );
  END LOOP;
END $$;

-- App-facing quality/invoice/offer views: keep authenticated SELECT (RLS now applies).
GRANT SELECT ON public.v_aqar_data_quality_users TO authenticated, service_role;
GRANT SELECT ON public.v_aqar_data_quality_properties TO authenticated, service_role;
GRANT SELECT ON public.v_aqar_data_quality_listing_requests TO authenticated, service_role;

DO $$
BEGIN
  IF to_regclass('public.v_marketer_visible_offers') IS NOT NULL THEN
    REVOKE ALL ON public.v_marketer_visible_offers FROM PUBLIC, anon;
    GRANT SELECT ON public.v_marketer_visible_offers TO authenticated, service_role;
  END IF;
  IF to_regclass('public.v_property_invoice_breakdown') IS NOT NULL THEN
    REVOKE ALL ON public.v_property_invoice_breakdown FROM PUBLIC, anon;
    GRANT SELECT ON public.v_property_invoice_breakdown TO authenticated, service_role;
  END IF;
  IF to_regclass('public.v_chat_list') IS NOT NULL THEN
    REVOKE ALL ON public.v_chat_list FROM PUBLIC, anon;
    GRANT SELECT ON public.v_chat_list TO authenticated, service_role;
  END IF;
END $$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Checks (run after commit)
-- -----------------------------------------------------------------------------
SELECT pg_get_viewdef('public.master_dashboard'::regclass, true) AS master_dashboard_def;

SELECT grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name = 'master_dashboard'
ORDER BY 1, 2;
