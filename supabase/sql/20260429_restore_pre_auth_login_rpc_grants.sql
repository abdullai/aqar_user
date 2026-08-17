-- =============================================================================
-- Restore pre-auth login RPC grants
--
-- Run in Supabase SQL Editor as project owner/postgres.
--
-- Why:
--   Emergency hardening revoked PUBLIC/anon EXECUTE from SECURITY DEFINER
--   functions. Login username lookup runs before the user is authenticated, so
--   these specific low-output lookup RPCs must remain executable by anon.
-- =============================================================================

BEGIN;

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
        'signup_username_taken',
        'signup_phone_taken',
        'signup_unified_national_taken'
      )
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon, authenticated, service_role', f.signature);
  END LOOP;
END $$;

-- Ask PostgREST/Supabase API to refresh function/policy metadata quickly.
NOTIFY pgrst, 'reload schema';

COMMIT;

SELECT
  p.proname AS function_name,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,
  p.oid::regprocedure AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'get_login_email',
    'get_email_by_national_id',
    'get_login_account_status',
    'get_security_username_for_login',
    'signup_username_taken',
    'signup_phone_taken',
    'signup_unified_national_taken'
  )
ORDER BY p.proname, (p.oid::regprocedure)::text;
