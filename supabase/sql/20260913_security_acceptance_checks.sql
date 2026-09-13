-- =============================================================================
-- فحوصات قبول أمنية — SQL Editor.
-- لا ينشئ جدولاً دائماً (لا يظهر تحذير RLS).
-- المتوقع: كل check_ok = true، و summary = ALL_CHECKS_PASSED
-- =============================================================================

WITH policy_flags AS (
  SELECT
    NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'user_subscriptions'
        AND cmd = 'INSERT' AND roles::text ILIKE '%authenticated%'
    ) AS no_sub_insert,
    (SELECT coalesce(string_agg(policyname, ', '), 'none')
       FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'user_subscriptions' AND cmd = 'INSERT'
    ) AS sub_insert_policies,
    NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'user_subscriptions'
        AND cmd = 'UPDATE' AND roles::text ILIKE '%authenticated%'
    ) AS no_sub_update,
    (SELECT coalesce(string_agg(policyname, ', '), 'none')
       FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'user_subscriptions' AND cmd = 'UPDATE'
    ) AS sub_update_policies,
    NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'billing_transactions'
        AND cmd = 'INSERT' AND roles::text ILIKE '%authenticated%'
    ) AS no_bill_insert,
    (SELECT coalesce(string_agg(policyname, ', '), 'none')
       FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'billing_transactions' AND cmd = 'INSERT'
    ) AS bill_insert_policies,
    NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'billing_transactions'
        AND cmd = 'UPDATE' AND roles::text ILIKE '%authenticated%'
    ) AS no_bill_update,
    (SELECT coalesce(string_agg(policyname, ', '), 'none')
       FROM pg_policies
      WHERE schemaname = 'public' AND tablename = 'billing_transactions' AND cmd = 'UPDATE'
    ) AS bill_update_policies
),
rpc_flags AS (
  SELECT
    NOT has_function_privilege(
      'authenticated',
      'public.apply_instant_credit_refund(uuid, text)',
      'EXECUTE'
    ) AS refund_denied,
    EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'fulfill_paid_billing'
    ) AS fulfill_exists,
    EXISTS (
      SELECT 1 FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'cancel_subscription'
    ) AS cancel_exists,
    has_function_privilege('service_role', 'public.subscription_expire_due()', 'EXECUTE')
    AND NOT has_function_privilege(
      'authenticated',
      'public.subscription_expire_due()',
      'EXECUTE'
    ) AS expire_service_only
),
rows AS (
  SELECT * FROM (
    SELECT '1_no_user_subscriptions_insert_policy' AS step,
           p.no_sub_insert AS check_ok,
           p.sub_insert_policies AS detail
    FROM policy_flags p
    UNION ALL
    SELECT '2_no_user_subscriptions_update_policy',
           p.no_sub_update,
           p.sub_update_policies
    FROM policy_flags p
    UNION ALL
    SELECT '3_no_billing_insert_policy',
           p.no_bill_insert,
           p.bill_insert_policies
    FROM policy_flags p
    UNION ALL
    SELECT '4_no_billing_update_policy',
           p.no_bill_update,
           p.bill_update_policies
    FROM policy_flags p
    UNION ALL
    SELECT '5_refund_rpc_not_granted_to_authenticated',
           r.refund_denied,
           'authenticated EXECUTE on apply_instant_credit_refund'
    FROM rpc_flags r
    UNION ALL
    SELECT '6_fulfill_rpc_exists',
           r.fulfill_exists,
           'fulfill_paid_billing'
    FROM rpc_flags r
    UNION ALL
    SELECT '7_cancel_rpc_exists',
           r.cancel_exists,
           'cancel_subscription'
    FROM rpc_flags r
    UNION ALL
    SELECT '8_expire_rpc_service_role_only',
           r.expire_service_only,
           format(
             'authenticated_exec=%s service_role_exec=%s',
             has_function_privilege('authenticated', 'public.subscription_expire_due()', 'EXECUTE')::text,
             has_function_privilege('service_role', 'public.subscription_expire_due()', 'EXECUTE')::text
           )
    FROM rpc_flags r
  ) x
)
SELECT step, check_ok, detail FROM rows
UNION ALL
SELECT
  'summary',
  bool_and(check_ok),
  CASE WHEN bool_and(check_ok) THEN 'ALL_CHECKS_PASSED' ELSE 'SOME_CHECKS_FAILED' END
FROM rows
ORDER BY step;
