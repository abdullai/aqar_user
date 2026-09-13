-- =============================================================================
-- 2026-09-14 — قفل subscription_expire_due على الخادم فقط
-- =============================================================================

BEGIN;

REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM anon;
REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.subscription_expire_due() TO service_role;

COMMIT;

SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec,
  has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_exec
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'subscription_expire_due';
