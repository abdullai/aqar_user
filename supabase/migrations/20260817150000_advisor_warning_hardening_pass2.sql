-- Pass 2: revoke Data API EXECUTE on unused internal SECURITY DEFINER helpers.
-- Login/guest RPCs and trigger functions stay granted. See
-- supabase/sql/APPLY_NOW_advisor_warning_hardening_pass2.sql.

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
