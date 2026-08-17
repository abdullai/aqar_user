-- =============================================================================
-- Security Advisor remaining WARN hardening (idempotent).
--
-- Run in Supabase → SQL Editor as postgres, then Rerun linter.
-- Paste this entire file (do not truncate).
--
-- Clears / reduces:
--   0011 function_search_path_mutable
--   0025 public_bucket_allows_listing (property-images / property-videos)
--   0028 anon_security_definer_function_executable  (keep login + guest helpers)
--   0029 authenticated_security_definer_function_executable
--         only for server-only RPCs (dev_/debug_/cron_/one-shot). App RPCs and
--         trigger functions stay executable by authenticated — revoking those
--         would break Flutter and row triggers.
--
-- Does NOT change (Dashboard, not SQL):
--   auth_leaked_password_protection
--   → Authentication → Attack protection → Enable leaked password protection
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Pin search_path on public functions that lack it (lint 0011).
--    public + extensions covers pgcrypto/uuid helpers; pg_temp blocks
--    search_path hijacking via a user-created temp object.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
  n int := 0;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prokind IN ('f', 'p')
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
        WHERE cfg LIKE 'search_path=%'
      )
  LOOP
    BEGIN
      EXECUTE format(
        'ALTER FUNCTION %s SET search_path = public, extensions, pg_temp',
        f.signature
      );
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'search_path skip %: %', f.signature, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE 'search_path pinned on % public functions', n;
END $$;

-- -----------------------------------------------------------------------------
-- 2) Public buckets: drop broad SELECT on storage.objects (lint 0025).
--    Flutter uses getPublicUrl / uploadBinary, not storage.list().
--    Public URL access does not need a SELECT policy on storage.objects.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS "public read property images" ON storage.objects;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'storage policy public read property images: %', SQLERRM;
  END;
  BEGIN
    DROP POLICY IF EXISTS "public read property videos" ON storage.objects;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'storage policy public read property videos: %', SQLERRM;
  END;
END $$;

-- -----------------------------------------------------------------------------
-- 3) Revoke PUBLIC/anon from every public SECURITY DEFINER function.
--    Default GRANT EXECUTE TO PUBLIC is what made admin/dev/cron callable
--    at /rest/v1/rpc without signing in.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prosecdef
      AND p.prokind IN ('f', 'p')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f.signature);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres, service_role', f.signature);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 4) Server-only SECURITY DEFINER RPCs: not callable by Data API clients.
--    Bodies still run when postgres/service_role / pg_cron invoke them.
--    Trigger functions are NOT in this list — authenticated DML needs EXECUTE.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature, p.proname
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prosecdef
      AND p.prokind IN ('f', 'p')
      AND (
        p.proname LIKE 'cron\_%' ESCAPE '\'
        OR p.proname LIKE 'dev\_%' ESCAPE '\'
        OR p.proname LIKE 'debug\_%' ESCAPE '\'
        OR p.proname IN (
          'apply_listing_media_link_round3',
          'apply_listing_media_link_round4',
          'listing_media_diag_after_round3',
          'heal_orphan_auth_profile',
          'fn_resync_listing_pricing',
          'archive_stale_messaging',
          'cleanup_old_user_sessions',
          'cleanup_stale_property_chats',
          'auto_approve_old_delete_requests',
          'auto_terminate_expired_permit_contracts',
          'expire_overdue_permits',
          'expire_reservations',
          'flag_old_delete_requests_for_admin',
          'run_document_expiry_checks',
          'check_expired_licenses',
          'login_with_national_id'
        )
      )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, authenticated, PUBLIC', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres, service_role', f.signature);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 5) App + trigger SECURITY DEFINER functions: authenticated + service_role.
--    Function bodies must still check auth.uid() / is_admin() / staff.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prosecdef
      AND p.prokind IN ('f', 'p')
      AND NOT (
        p.proname LIKE 'cron\_%' ESCAPE '\'
        OR p.proname LIKE 'dev\_%' ESCAPE '\'
        OR p.proname LIKE 'debug\_%' ESCAPE '\'
        OR p.proname IN (
          'apply_listing_media_link_round3',
          'apply_listing_media_link_round4',
          'listing_media_diag_after_round3',
          'heal_orphan_auth_profile',
          'fn_resync_listing_pricing',
          'archive_stale_messaging',
          'cleanup_old_user_sessions',
          'cleanup_stale_property_chats',
          'auto_approve_old_delete_requests',
          'auto_terminate_expired_permit_contracts',
          'expire_overdue_permits',
          'expire_reservations',
          'flag_old_delete_requests_for_admin',
          'run_document_expiry_checks',
          'check_expired_licenses',
          'login_with_national_id'
        )
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f.signature);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 6) Pre-auth + guest RPCs that Flutter actually calls without a session.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prokind IN ('f', 'p')
      AND p.proname IN (
        'get_login_email',
        'get_email_by_national_id',
        'get_login_account_status',
        'get_login_email_by_national_id',
        'get_security_username_for_login',
        'get_status_by_username',
        'record_failed_password_login',
        'request_inapp_otp',
        'verify_inapp_otp',
        'ensure_otp_username_for_me',
        'signup_email_taken',
        'signup_fal_license_taken',
        'signup_phone_taken',
        'signup_unified_commercial_taken',
        'signup_unified_national_taken',
        'signup_username_taken',
        'org_preview_by_invite_code',
        'org_browse_public',
        'org_public_profile',
        'get_active_legal_version',
        'get_app_audience_stats',
        'ping_app_presence',
        'get_user_presence_summary'
      )
  LOOP
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role',
      f.signature
    );
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 7) RLS helper functions used by policies granted to anon/public.
--    Without EXECUTE, guest home-feed SELECTs fail with 42501.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
  pol_sql text;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature, p.proname
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prosecdef
      AND p.prokind IN ('f', 'p')
  LOOP
    SELECT string_agg(coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, ''), ' ')
      INTO pol_sql
    FROM pg_policies pol
    WHERE pol.schemaname IN ('public', 'storage')
      AND (
        'anon' = ANY (pol.roles)
        OR 'public' = ANY (pol.roles)
      )
      AND (
        coalesce(pol.qual, '') ~ ('\m' || f.proname || '\M')
        OR coalesce(pol.with_check, '') ~ ('\m' || f.proname || '\M')
      );

    IF pol_sql IS NOT NULL THEN
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role',
        f.signature
      );
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- -----------------------------------------------------------------------------
-- Checks (after commit)
-- -----------------------------------------------------------------------------
SELECT 'functions_missing_search_path' AS check_name, count(*)::bigint AS count
FROM pg_proc p
JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
WHERE nsp.nspname = 'public'
  AND p.prokind IN ('f', 'p')
  AND NOT EXISTS (
    SELECT 1
    FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
    WHERE cfg LIKE 'search_path=%'
  )
UNION ALL
SELECT 'public_bucket_select_policies', count(*)::bigint
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND cmd = 'SELECT'
  AND (
    policyname ILIKE '%public read property images%'
    OR policyname ILIKE '%public read property videos%'
  )
UNION ALL
SELECT 'security_definer_execute_anon_unexpected', count(*)::bigint
FROM pg_proc p
JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
WHERE nsp.nspname = 'public'
  AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND p.proname NOT IN (
    'get_login_email',
    'get_email_by_national_id',
    'get_login_account_status',
    'get_login_email_by_national_id',
    'get_security_username_for_login',
    'get_status_by_username',
    'record_failed_password_login',
    'request_inapp_otp',
    'verify_inapp_otp',
    'ensure_otp_username_for_me',
    'signup_email_taken',
    'signup_fal_license_taken',
    'signup_phone_taken',
    'signup_unified_commercial_taken',
    'signup_unified_national_taken',
    'signup_username_taken',
    'org_preview_by_invite_code',
    'org_browse_public',
    'org_public_profile',
    'get_active_legal_version',
    'get_app_audience_stats',
    'ping_app_presence',
    'get_user_presence_summary',
    'is_admin',
    'property_has_listing_media',
    'property_marketer_public_verified',
    'property_owner_public_verified',
    'property_has_rega_publish_payload',
    'property_has_rega_publish_payload_for_property',
    'property_license_payload',
    'property_public_publish_ready',
    'property_image_public_home_readable',
    'property_id_public_home_feed_visible',
    'property_image_owned_by_auth_user'
  )
UNION ALL
SELECT 'server_only_still_executable_by_authenticated', count(*)::bigint
FROM pg_proc p
JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
WHERE nsp.nspname = 'public'
  AND p.prosecdef
  AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  AND (
    p.proname LIKE 'cron\_%' ESCAPE '\'
    OR p.proname LIKE 'dev\_%' ESCAPE '\'
    OR p.proname LIKE 'debug\_%' ESCAPE '\'
    OR p.proname IN (
      'apply_listing_media_link_round3',
      'apply_listing_media_link_round4',
      'listing_media_diag_after_round3',
      'heal_orphan_auth_profile',
      'fn_resync_listing_pricing',
      'login_with_national_id'
    )
  );

-- Remaining anon SECURITY DEFINER EXECUTE (expected: login + RLS helpers).
SELECT p.proname, p.oid::regprocedure AS signature
FROM pg_proc p
JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
WHERE nsp.nspname = 'public'
  AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY 1, 2;
