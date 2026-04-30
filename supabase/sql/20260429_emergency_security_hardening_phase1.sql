-- =============================================================================
-- Emergency security hardening - phase 1
--
-- Run in Supabase SQL Editor as project owner/postgres.
-- Goal: close the broad anon/public access shown by
-- diagnostics_full_security_schema_audit.sql without deleting data.
--
-- Safe intent:
--   - anon keeps read access only to public discovery tables.
--   - authenticated keeps table privileges, but RLS remains the real gate.
--   - SECURITY DEFINER functions stop being executable through PUBLIC/anon.
--   - RLS is enabled on tables that were exposed with RLS disabled.
--
-- After running: re-run diagnostics_full_security_schema_audit.sql.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Lock down anon table privileges.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name, c.relname AS object_name, c.relkind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p', 'v', 'm')
  LOOP
    EXECUTE format(
      'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON %I.%I FROM anon',
      r.schema_name,
      r.object_name
    );

    IF r.object_name NOT IN (
      'ads',
      'properties',
      'property_images',
      'property_media',
      'market_property_requests',
      'property_auction_sessions',
      'property_auction_bids'
    ) THEN
      EXECUTE format(
        'REVOKE SELECT ON %I.%I FROM anon',
        r.schema_name,
        r.object_name
      );
    END IF;
  END LOOP;
END $$;

-- Public discovery reads that the Flutter home feed can legitimately need.
GRANT SELECT ON public.ads TO anon, authenticated;
GRANT SELECT ON public.properties TO anon, authenticated;
GRANT SELECT ON public.property_images TO anon, authenticated;
GRANT SELECT ON public.property_media TO anon, authenticated;
GRANT SELECT ON public.market_property_requests TO anon, authenticated;
GRANT SELECT ON public.property_auction_sessions TO anon, authenticated;
GRANT SELECT ON public.property_auction_bids TO anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2) Enable RLS on tables reported as disabled.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'app_users_legacy',
    'auth_audit',
    'fal_licenses',
    'listing_chat_visibility_requests',
    'listing_request_marketer_exclusions',
    'otp_requests',
    'property_delete_audit',
    'property_media',
    'r_backup',
    'user_otps',
    'verification_history'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    END IF;
  END LOOP;
END $$;

-- property_media was RLS-off in the audit but is used as public listing media.
DROP POLICY IF EXISTS property_media_public_read_published ON public.property_media;
CREATE POLICY property_media_public_read_published
  ON public.property_media
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_media.property_id
        AND p.status IS DISTINCT FROM 'deleted'
        AND coalesce(p.home_feed_suppressed, false) = false
        AND (
          p.status IN (
            'published', 'active', 'available', 'live', 'reserved', 'approved',
            'listed', 'open', 'visible', 'for_sale', 'for_rent',
            'forsale', 'forrent'
          )
          OR lower(coalesce(p.workflow_stage, '')) IN ('published', 'reserved')
        )
    )
  );

DROP POLICY IF EXISTS property_media_owner_manage ON public.property_media;
CREATE POLICY property_media_owner_manage
  ON public.property_media
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_media.property_id
        AND p.owner_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_media.property_id
        AND p.owner_id = auth.uid()
    )
  );

-- -----------------------------------------------------------------------------
-- 3) Revoke PUBLIC/anon execution from SECURITY DEFINER functions.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f.signature);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', f.signature);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 4) Grant authenticated/service_role back for app RPCs.
--    The function bodies still must validate auth.uid() and ownership.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        '_resolve_inapp_otp_profile',
        '_resolve_user_id_from_login_digits',
        'accept_listing_offer',
        'accept_terms_v1',
        'ack_profile_data_revision',
        'bump_user_session_epoch',
        'cancel_listing_contract',
        'clear_must_change_password_after_auth',
        'clear_user_devices_except_current',
        'close_property_auction_session',
        'complete_market_property_request',
        'complete_property_sale',
        'create_listing_contract_from_offer',
        'create_or_update_listing_permit',
        'edit_chat_message',
        'ensure_org_team_channel_conversation',
        'ensure_direct_conversation',
        'ensure_market_request_conversation',
        'ensure_my_org_unit',
        'get_active_legal_version',
        'get_chat_list2',
        'hide_chat_message_for_me',
        'get_login_account_status',
        'get_market_insights_snapshot',
        'get_peer_rating_summary',
        'get_security_username_for_login',
        'is_device_known',
        'is_user_session_active',
        'issue_listing_permit',
        'listing_request_owner_ack_regulatory',
        'mark_chat_messages_delivered',
        'mark_chat_messages_read_receipts',
        'marketer_submit_offer',
        'my_org_context',
        'my_pending_org_join_banner',
        'open_property_auction_session',
        'org_decide_join_request',
        'org_get_my_recruit_join_code',
        'org_list_pending_join_requests',
        'org_owner_revoke_member_device',
        'org_submit_join_request',
        'org_update_member_permissions',
        'owner_decline_listing_offer',
        'owner_delete_property_cascade',
        'owner_edit_property',
        'owner_request_marketing_admin_escalation',
        'owner_return_listing_contract',
        'owner_sign_listing_contract',
        'ping_chat_presence',
        'place_property_bid',
        'publish_property_after_permit',
        'publish_property_from_contract',
        'reconcile_user_device_slot',
        'reconcile_user_session',
        'record_owner_viewed_listing_offers',
        'record_property_listing_view',
        'register_device',
        'register_listing_payment_event',
        'register_single_user_session',
        'register_user_device_slot',
        'register_user_device_v2',
        'release_or_expire_reservation',
        'relist_completed_market_request_as_new',
        'relist_completed_property_as_new',
        'relist_property_for_marketing',
        'report_rega_license_mismatch',
        'request_delete_market_property_request',
        'request_inapp_otp',
        'reserve_property',
        'respond_market_request_offer',
        'revoke_chat_message_for_everyone',
        'revoke_my_trusted_device',
        'send_listing_contract_to_owner',
        'set_chat_last_seen_hidden',
        'signup_phone_taken',
        'signup_unified_national_taken',
        'signup_username_taken',
        'submit_listing_offer',
        'sync_user_fcm_profile_token',
        'update_market_property_request_limited',
        'upsert_my_profile',
        'verify_inapp_otp',
        'workflow_create_notification'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.signature);
  END LOOP;
END $$;

-- Login/signup lookup RPCs are intentionally callable before authentication.
-- They return minimal status/email lookup data needed by the login and signup UI.
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'get_login_email',
        'get_email_by_national_id',
        'get_login_account_status',
        'get_security_username_for_login',
        'signup_phone_taken',
        'signup_unified_national_taken',
        'signup_username_taken'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role', f.signature);
  END LOOP;
END $$;

-- Background/admin functions should be service_role only.
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'admin_approve_property_delete',
        'admin_decide_ad_delete_request',
        'admin_reject_property_delete',
        'auto_approve_old_delete_requests',
        'cleanup_stale_property_chats',
        'cron_expire_pending_offers_72h',
        'cron_expire_permit_pending_72h',
        'cron_expire_reservations',
        'expire_overdue_permits',
        'expire_reservations',
        'flag_old_delete_requests_for_admin',
        'purge_market_request_chat_data',
        'purge_property_chat_data',
        'refresh_listing_report_aggregate_for_property',
        'run_document_expiry_checks'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.signature);
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 5) Add explicit search_path to SECURITY DEFINER functions that lacked it.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
        WHERE cfg LIKE 'search_path=%'
      )
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public', f.signature);
  END LOOP;
END $$;

COMMIT;

-- Quick verification after commit.
SELECT 'anon_table_dml_remaining' AS check_name, count(*)::bigint AS count
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee = 'anon'
  AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
UNION ALL
SELECT 'rls_disabled_public_tables_remaining', count(*)::bigint
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND c.relrowsecurity = false
UNION ALL
SELECT 'security_definer_execute_anon_unexpected_remaining', count(*)::bigint
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND p.proname NOT IN (
    'get_login_email',
    'get_email_by_national_id',
    'get_login_account_status',
    'get_security_username_for_login',
    'signup_phone_taken',
    'signup_unified_national_taken',
    'signup_username_taken'
  );
