-- =============================================================================
-- AQAR full database/security/schema audit
-- Run in Supabase SQL Editor as project owner/postgres.
--
-- This script is read-only against application data. It creates TEMP audit
-- tables/functions only for the current SQL session.
--
-- What it checks:
--   1) Tables/columns/constraints/indexes used by the Flutter code
--   2) RLS enabled/forced state, grants, and policies for anon/authenticated
--   3) SECURITY DEFINER functions and public execute grants
--   4) Storage buckets/policies
--   5) Known FK orphan counts and account/profile data-quality gaps
--
-- Tip: Supabase SQL Editor may show only the last result if you run all at once.
-- Run the final SELECT blocks one by one if needed.
-- =============================================================================

CREATE TEMP TABLE IF NOT EXISTS aqar_audit_findings (
  section text NOT NULL,
  item text NOT NULL,
  severity text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb
) ON COMMIT DROP;

TRUNCATE aqar_audit_findings;

CREATE OR REPLACE FUNCTION pg_temp.aqar_has_table(p_table text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT to_regclass(format('public.%I', p_table)) IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION pg_temp.aqar_has_column(p_table text, p_column text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = p_table
      AND c.column_name = p_column
  );
$$;

CREATE OR REPLACE FUNCTION pg_temp.aqar_add_count(
  p_section text,
  p_item text,
  p_severity text,
  p_sql text
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_count bigint;
BEGIN
  EXECUTE p_sql INTO v_count;

  INSERT INTO aqar_audit_findings(section, item, severity, details)
  VALUES (
    p_section,
    p_item,
    CASE WHEN coalesce(v_count, 0) > 0 THEN p_severity ELSE 'ok' END,
    jsonb_build_object('count', coalesce(v_count, 0))
  );
EXCEPTION WHEN OTHERS THEN
  INSERT INTO aqar_audit_findings(section, item, severity, details)
  VALUES (
    p_section,
    p_item,
    'error',
    jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE)
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- A) Expected application tables from current Flutter/Supabase code
-- -----------------------------------------------------------------------------
WITH expected(table_name) AS (
  VALUES
    ('users_profiles'),
    ('marketer_profiles'),
    ('profiles'),
    ('properties'),
    ('property_images'),
    ('property_media'),
    ('favorites'),
    ('reservations'),
    ('conversations'),
    ('messages'),
    ('ads'),
    ('ads_delete_requests'),
    ('listing_requests'),
    ('listing_request_images'),
    ('listing_request_invites'),
    ('listing_request_marketer_exclusions'),
    ('listing_chat_visibility_requests'),
    ('listing_offers'),
    ('listing_contracts'),
    ('listing_contract_messages'),
    ('listing_permits'),
    ('marketing_requests'),
    ('marketing_offers'),
    ('market_property_requests'),
    ('market_request_offers'),
    ('property_auction_sessions'),
    ('property_auction_bids'),
    ('listing_payment_events'),
    ('listing_user_reports'),
    ('listing_moderation_escalations'),
    ('property_review_logs'),
    ('property_listing_view_events'),
    ('verification_requests'),
    ('org_units'),
    ('org_memberships'),
    ('org_join_requests'),
    ('org_activity_log'),
    ('org_team_channel_posts'),
    ('user_devices'),
    ('user_trusted_devices'),
    ('user_push_tokens'),
    ('nafath_logins'),
    ('in_app_notifications'),
    ('user_peer_ratings')
)
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'schema.expected_tables',
  e.table_name,
  CASE WHEN c.oid IS NULL THEN 'critical' ELSE 'ok' END,
  jsonb_build_object('exists', c.oid IS NOT NULL)
FROM expected e
LEFT JOIN pg_class c
  ON c.oid = to_regclass(format('public.%I', e.table_name));

-- -----------------------------------------------------------------------------
-- B) RLS and grants: public tables that can expose or mutate data
-- -----------------------------------------------------------------------------
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'security.rls',
  c.relname,
  CASE
    WHEN c.relrowsecurity THEN 'ok'
    WHEN c.relname LIKE 'v\_%' ESCAPE '\' THEN 'info'
    ELSE 'critical'
  END,
  jsonb_build_object(
    'rls_enabled', c.relrowsecurity,
    'force_rls', c.relforcerowsecurity,
    'kind', c.relkind
  )
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.relname;

INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'security.direct_grants',
  g.table_name || ':' || g.grantee,
  CASE
    WHEN g.grantee = 'anon' AND g.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE') THEN 'critical'
    WHEN g.grantee = 'authenticated' AND g.privilege_type = 'TRUNCATE' THEN 'critical'
    WHEN g.grantee = 'anon' AND g.privilege_type = 'SELECT'
      AND g.table_name NOT IN ('properties', 'property_images', 'property_media', 'market_property_requests') THEN 'warning'
    ELSE 'info'
  END,
  jsonb_build_object(
    'grantee', g.grantee,
    'privilege', g.privilege_type,
    'grantor', g.grantor
  )
FROM information_schema.role_table_grants g
WHERE g.table_schema = 'public'
  AND g.grantee IN ('anon', 'authenticated', 'public')
ORDER BY g.table_name, g.grantee, g.privilege_type;

INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'security.policies',
  p.tablename || ':' || p.policyname,
  CASE
    WHEN p.roles::text ILIKE '%anon%'
      AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL') THEN 'warning'
    ELSE 'info'
  END,
  jsonb_build_object(
    'operation', p.cmd,
    'permissive', p.permissive,
    'roles', p.roles::text,
    'using', p.qual,
    'with_check', p.with_check
  )
FROM pg_policies p
WHERE p.schemaname = 'public'
ORDER BY p.tablename, p.cmd, p.policyname;

-- Tables with RLS enabled but no policy usually become inaccessible to clients.
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'security.rls_without_policy',
  c.relname,
  'warning',
  jsonb_build_object('rls_enabled', true)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND c.relrowsecurity
  AND NOT EXISTS (
    SELECT 1
    FROM pg_policies p
    WHERE p.schemaname = 'public'
      AND p.tablename = c.relname
  );

-- -----------------------------------------------------------------------------
-- C) SECURITY DEFINER functions and execute grants
-- -----------------------------------------------------------------------------
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'security.functions',
  p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
  CASE
    WHEN p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE') THEN 'critical'
    WHEN p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN 'warning'
    WHEN p.prosecdef THEN 'info'
    ELSE 'info'
  END,
  jsonb_build_object(
    'security_definer', p.prosecdef,
    'volatile', p.provolatile,
    'execute_anon', has_function_privilege('anon', p.oid, 'EXECUTE'),
    'execute_authenticated', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
    'search_path', coalesce(array_to_string(p.proconfig, ','), '')
  )
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
ORDER BY p.prosecdef DESC, p.proname;

-- SECURITY DEFINER without explicit search_path is risky.
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'security.function_search_path',
  p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
  'critical',
  jsonb_build_object('security_definer', true, 'search_path', p.proconfig)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef
  AND NOT EXISTS (
    SELECT 1
    FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
    WHERE cfg LIKE 'search_path=%'
  );

-- -----------------------------------------------------------------------------
-- D) Storage buckets and policies
-- -----------------------------------------------------------------------------
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'storage.buckets',
  b.id,
  CASE WHEN b.public THEN 'warning' ELSE 'info' END,
  jsonb_build_object(
    'name', b.name,
    'public', b.public,
    'file_size_limit', b.file_size_limit,
    'allowed_mime_types', b.allowed_mime_types
  )
FROM storage.buckets b
ORDER BY b.id;

INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'storage.policies',
  p.tablename || ':' || p.policyname,
  CASE
    WHEN p.roles::text ILIKE '%anon%'
      AND p.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL') THEN 'critical'
    WHEN p.roles::text ILIKE '%anon%' THEN 'warning'
    ELSE 'info'
  END,
  jsonb_build_object(
    'operation', p.cmd,
    'roles', p.roles::text,
    'using', p.qual,
    'with_check', p.with_check
  )
FROM pg_policies p
WHERE p.schemaname = 'storage'
ORDER BY p.tablename, p.policyname;

-- -----------------------------------------------------------------------------
-- E) Known FK orphan checks from the app's relationship map
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT *
    FROM (VALUES
      ('conversations','property_id','properties','id'),
      ('conversations','reservation_id','reservations','id'),
      ('messages','conversation_id','conversations','id'),
      ('reservations','property_id','properties','id'),
      ('listing_request_invites','request_id','listing_requests','id'),
      ('listing_request_invites','marketer_id','marketer_profiles','user_id'),
      ('listing_offers','request_id','listing_requests','id'),
      ('listing_offers','marketer_id','marketer_profiles','user_id'),
      ('listing_contracts','request_id','listing_requests','id'),
      ('listing_contracts','offer_id','listing_offers','id'),
      ('listing_permits','request_id','listing_requests','id'),
      ('property_images','property_id','properties','id'),
      ('property_media','property_id','properties','id'),
      ('favorites','property_id','properties','id'),
      ('ads_delete_requests','ad_id','ads','id'),
      ('listing_request_images','request_id','listing_requests','id'),
      ('marketing_requests','property_id','properties','id'),
      ('marketing_requests','owner_id','users_profiles','user_id'),
      ('marketing_offers','request_id','marketing_requests','id'),
      ('marketing_offers','marketer_id','users_profiles','user_id'),
      ('property_review_logs','property_id','properties','id'),
      ('property_listing_view_events','property_id','properties','id'),
      ('org_memberships','org_id','org_units','id'),
      ('users_profiles','org_id','org_units','id'),
      ('org_activity_log','org_id','org_units','id'),
      ('listing_chat_visibility_requests','listing_request_id','listing_requests','id'),
      ('listing_request_marketer_exclusions','listing_request_id','listing_requests','id'),
      ('org_join_requests','org_id','org_units','id'),
      ('org_join_requests','verification_request_id','verification_requests','id'),
      ('listing_contract_messages','contract_id','listing_contracts','id'),
      ('market_request_offers','market_request_id','market_property_requests','id'),
      ('conversations','market_request_id','market_property_requests','id'),
      ('property_auction_bids','property_id','properties','id'),
      ('market_property_requests','selected_offer_id','market_request_offers','id'),
      ('property_auction_sessions','property_id','properties','id'),
      ('listing_payment_events','property_id','properties','id'),
      ('listing_payment_events','auction_session_id','property_auction_sessions','id'),
      ('listing_user_reports','property_id','properties','id'),
      ('listing_moderation_escalations','property_id','properties','id')
    ) AS x(child_table, child_column, parent_table, parent_column)
  LOOP
    IF pg_temp.aqar_has_table(r.child_table)
       AND pg_temp.aqar_has_table(r.parent_table)
       AND pg_temp.aqar_has_column(r.child_table, r.child_column)
       AND pg_temp.aqar_has_column(r.parent_table, r.parent_column) THEN
      PERFORM pg_temp.aqar_add_count(
        'data.fk_orphans',
        r.child_table || '.' || r.child_column || ' -> ' || r.parent_table || '.' || r.parent_column,
        'critical',
        format(
          'SELECT count(*) FROM public.%I c LEFT JOIN public.%I p ON c.%I = p.%I WHERE c.%I IS NOT NULL AND p.%I IS NULL',
          r.child_table, r.parent_table, r.child_column, r.parent_column, r.child_column, r.parent_column
        )
      );
    ELSE
      INSERT INTO aqar_audit_findings(section, item, severity, details)
      VALUES (
        'data.fk_orphans',
        r.child_table || '.' || r.child_column || ' -> ' || r.parent_table || '.' || r.parent_column,
        'warning',
        jsonb_build_object('skipped', 'missing table or column')
      );
    END IF;
  END LOOP;
END $$;

-- FKs defined in the database vs relationships expected by the app.
WITH expected(child_table, child_column, parent_table, parent_column) AS (
  VALUES
    ('conversations','property_id','properties','id'),
    ('conversations','reservation_id','reservations','id'),
    ('messages','conversation_id','conversations','id'),
    ('reservations','property_id','properties','id'),
    ('listing_request_invites','request_id','listing_requests','id'),
    ('listing_request_invites','marketer_id','marketer_profiles','user_id'),
    ('listing_offers','request_id','listing_requests','id'),
    ('listing_offers','marketer_id','marketer_profiles','user_id'),
    ('listing_contracts','request_id','listing_requests','id'),
    ('listing_contracts','offer_id','listing_offers','id'),
    ('property_images','property_id','properties','id'),
    ('property_media','property_id','properties','id'),
    ('favorites','property_id','properties','id'),
    ('marketing_requests','owner_id','users_profiles','user_id'),
    ('market_request_offers','market_request_id','market_property_requests','id'),
    ('listing_user_reports','property_id','properties','id')
),
actual AS (
  SELECT
    tc.table_name AS child_table,
    kcu.column_name AS child_column,
    ccu.table_name AS parent_table,
    ccu.column_name AS parent_column
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON kcu.constraint_schema = tc.constraint_schema
   AND kcu.constraint_name = tc.constraint_name
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_schema = tc.constraint_schema
   AND ccu.constraint_name = tc.constraint_name
  WHERE tc.constraint_schema = 'public'
    AND tc.constraint_type = 'FOREIGN KEY'
)
INSERT INTO aqar_audit_findings(section, item, severity, details)
SELECT
  'schema.missing_fk_constraints',
  e.child_table || '.' || e.child_column || ' -> ' || e.parent_table || '.' || e.parent_column,
  CASE WHEN a.child_table IS NULL THEN 'warning' ELSE 'ok' END,
  jsonb_build_object('constraint_exists', a.child_table IS NOT NULL)
FROM expected e
LEFT JOIN actual a USING (child_table, child_column, parent_table, parent_column);

-- -----------------------------------------------------------------------------
-- F) Account/profile and listing data quality
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF pg_temp.aqar_has_table('users_profiles') THEN
    IF pg_temp.aqar_has_column('users_profiles', 'username') THEN
      PERFORM pg_temp.aqar_add_count(
        'data.profile_quality',
        'users_profiles missing national id / username',
        'warning',
        'SELECT count(*) FROM public.users_profiles WHERE nullif(trim(coalesce(username::text, '''')), '''') IS NULL'
      );
    END IF;

    IF pg_temp.aqar_has_column('users_profiles', 'license_no') THEN
      PERFORM pg_temp.aqar_add_count(
        'data.profile_quality',
        'users_profiles invalid or missing FAL license for verified statuses',
        'warning',
        'SELECT count(*) FROM public.users_profiles WHERE coalesce(verification_status::text, '''') IN (''verified_business'', ''verified_identity'') AND nullif(trim(coalesce(license_no::text, '''')), '''') IS NULL'
      );
    END IF;

    IF pg_temp.aqar_has_column('users_profiles', 'full_name_ar') THEN
      PERFORM pg_temp.aqar_add_count(
        'data.profile_quality',
        'users_profiles missing Arabic full name',
        'warning',
        'SELECT count(*) FROM public.users_profiles WHERE nullif(trim(coalesce(full_name_ar::text, full_name::text, '''')), '''') IS NULL'
      );
    END IF;

    IF pg_temp.aqar_has_column('users_profiles', 'user_id') THEN
      PERFORM pg_temp.aqar_add_count(
        'data.profile_quality',
        'users_profiles without auth.users row',
        'critical',
        'SELECT count(*) FROM public.users_profiles up LEFT JOIN auth.users au ON au.id = up.user_id WHERE au.id IS NULL'
      );
    END IF;
  END IF;

  IF pg_temp.aqar_has_table('properties') AND pg_temp.aqar_has_column('properties', 'owner_id') THEN
    PERFORM pg_temp.aqar_add_count(
      'data.property_quality',
      'properties owner_id missing profile',
      'critical',
      'SELECT count(*) FROM public.properties p LEFT JOIN public.users_profiles up ON up.user_id = p.owner_id WHERE p.owner_id IS NOT NULL AND up.user_id IS NULL'
    );
  END IF;

  IF pg_temp.aqar_has_table('listing_offers') AND pg_temp.aqar_has_column('listing_offers', 'marketer_id') THEN
    PERFORM pg_temp.aqar_add_count(
      'data.marketing_quality',
      'listing_offers marketer_id missing marketer profile',
      'critical',
      'SELECT count(*) FROM public.listing_offers lo LEFT JOIN public.marketer_profiles mp ON mp.user_id = lo.marketer_id WHERE lo.marketer_id IS NOT NULL AND mp.user_id IS NULL'
    );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- Final result blocks
-- -----------------------------------------------------------------------------

-- 1) Executive summary
SELECT
  severity,
  count(*)::bigint AS findings
FROM aqar_audit_findings
GROUP BY severity
ORDER BY CASE severity
  WHEN 'critical' THEN 1
  WHEN 'error' THEN 2
  WHEN 'warning' THEN 3
  WHEN 'info' THEN 4
  WHEN 'ok' THEN 5
  ELSE 6
END;

-- 2) Findings requiring review first
SELECT section, item, severity, details
FROM aqar_audit_findings
WHERE severity IN ('critical', 'error', 'warning')
ORDER BY CASE severity
  WHEN 'critical' THEN 1
  WHEN 'error' THEN 2
  WHEN 'warning' THEN 3
  ELSE 4
END, section, item;

-- 3) Full table/column inventory
SELECT
  c.table_schema,
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable,
  c.column_default
FROM information_schema.columns c
WHERE c.table_schema IN ('public', 'storage')
ORDER BY c.table_schema, c.table_name, c.ordinal_position;

-- 4) Full constraints inventory
SELECT
  tc.table_schema,
  tc.table_name,
  tc.constraint_name,
  tc.constraint_type,
  kcu.column_name,
  ccu.table_schema AS foreign_table_schema,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
LEFT JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_schema = tc.constraint_schema
 AND ccu.constraint_name = tc.constraint_name
WHERE tc.table_schema IN ('public', 'storage')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_type, tc.constraint_name;

-- 5) Full index inventory
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname IN ('public', 'storage')
ORDER BY schemaname, tablename, indexname;

-- 6) Row-count estimates for every public table
SELECT
  n.nspname AS schema_name,
  c.relname AS table_name,
  c.reltuples::bigint AS estimated_rows,
  pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
ORDER BY c.reltuples DESC, c.relname;

-- 7) All raw audit findings, including ok/info
SELECT section, item, severity, details
FROM aqar_audit_findings
ORDER BY section, severity, item;
