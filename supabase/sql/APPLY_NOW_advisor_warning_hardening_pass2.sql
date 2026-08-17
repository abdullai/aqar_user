-- =============================================================================
-- Pass 2 — extra Advisor WARN reduction (idempotent).
-- Paste this entire file in SQL Editor after pass 1.
--
-- This does NOT zero Security Advisor.
--   0028 remaining after this: login / signup / guest RPCs + RLS helpers.
--   0029 remaining after this: every Flutter SECURITY DEFINER RPC + triggers.
-- Revoking those remaining grants would break login, guest home, and DML.
--
-- This pass:
--   • drops anon EXECUTE on ensure_otp_username_for_me (not called from Flutter)
--   • drops authenticated EXECUTE on internal _* helpers and request_otp_dev
--     unless the function is a trigger or referenced from RLS
--
-- Dashboard (not SQL): Authentication → Attack protection
--   → Enable leaked password protection
-- =============================================================================

BEGIN;

DO $$
BEGIN
  EXECUTE 'REVOKE ALL ON FUNCTION public.ensure_otp_username_for_me(text) FROM PUBLIC, anon';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.ensure_otp_username_for_me(text) TO authenticated, postgres, service_role';
EXCEPTION
  WHEN undefined_function THEN
    RAISE NOTICE 'ensure_otp_username_for_me(text) not present';
END $$;

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
      AND (
        p.proname = 'request_otp_dev'
        OR (
          p.proname LIKE '\_%' ESCAPE '\'
          AND NOT EXISTS (
            SELECT 1 FROM pg_trigger t
            WHERE t.tgfoid = p.oid AND NOT t.tgisinternal
          )
          AND NOT EXISTS (
            SELECT 1 FROM pg_policies pol
            WHERE pol.schemaname IN ('public', 'storage')
              AND (
                coalesce(pol.qual, '') ~ ('\m' || p.proname || '\M')
                OR coalesce(pol.with_check, '') ~ ('\m' || p.proname || '\M')
              )
          )
        )
      )
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      f.signature
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO postgres, service_role',
      f.signature
    );
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;

SELECT p.proname, p.oid::regprocedure AS signature
FROM pg_proc p
JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
WHERE nsp.nspname = 'public'
  AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY 1, 2;
