-- =============================================================================
-- Security hardening - phase 2
--
-- Run after 20260429_emergency_security_hardening_phase1.sql.
-- Goal: remove TRUNCATE from client roles. RLS does not protect TRUNCATE the
-- same way it protects row-level SELECT/INSERT/UPDATE/DELETE.
--
-- Includes views/materialized views because information_schema may still report
-- inherited table privileges on them after broad GRANT ALL migrations.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name, c.relname AS object_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r', 'p', 'v', 'm')
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE ON %I.%I FROM anon, authenticated',
      r.schema_name,
      r.object_name
    );
  END LOOP;
END $$;

COMMIT;

SELECT 'client_truncate_remaining' AS check_name, count(*)::bigint AS count
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
  AND privilege_type = 'TRUNCATE';
