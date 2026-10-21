-- Read-only readiness audit for subscription and billing migrations.
-- Run in the Supabase SQL Editor. This does not apply or modify migrations.
-- This checks the billing/subscription migration chain, not all app migrations.

WITH expected_migrations(version, migration_name, apply_mode) AS (
  VALUES
    ('20260503120000', 'subscriptions_payments_billing', 'standard'),
    ('20260503150000', 'billing_audit_promotions_staff_read', 'standard'),
    ('20260514120000', 'subscription_lifecycle_retention', 'standard'),
    ('20260515194500', 'subscription_lifecycle_staff_read', 'standard'),
    ('20260516140000', 'user_subscriptions_instants_renewal_fail', 'standard'),
    ('20260516150000', 'subscription_auto_renew_extension_rpc', 'standard'),
    ('20260517210000', 'org_seats_subscription_join_gate', 'standard'),
    ('20260517220000', 'subscription_plans_five_account_types', 'standard'),
    ('20260530140000', 'subscription_plans_pricing_v2_and_trial', 'standard'),
    ('20260530150000', 'trial_plan_and_strict_trial_flow', 'standard'),
    ('20260530160000', 'plans_limits_v3_and_seat_discount', 'standard'),
    ('20260530170000', 'subscription_billing_context_rpc', 'standard'),
    ('20260530180000', 'plans_limits_v3_data_repair', 'standard'),
    ('20260530190000', 'subscription_plans_select_subscribed', 'standard'),
    ('20260530200000', 'individual_offer_quota_and_one_time_plan', 'standard'),
    ('20260530210000', 'dedup_individual_plans', 'standard'),
    ('20260530220000', 'subscription_plans_v4_market_offers_quota', 'standard'),
    ('20260530240000', 'individual_offer_quota_v2_honest_counting', 'standard'),
    ('20260530250000', 'market_offer_topup_for_marketing_roles', 'standard'),
    ('20260530260000', 'auto_pay_discount_and_cancellation', 'standard'),
    ('20260530310000', 'billing_context_active_trial_access', 'standard'),
    ('20260530330000', 'enforce_active_plans_for_roles', 'standard'),
    ('20260602030000', 'restore_three_plans_per_role', 'standard'),
    ('20260602040000', 'canonical_one_plan_per_role_v5', 'standard'),
    ('20260602050000', 'subscription_lifecycle_guards_v5', 'standard'),
    ('20260602060000', 'plans_visibility_for_subscribers', 'standard'),
    ('20260602070000', 'world_class_payment_addons_v6', 'standard'),
    ('20260602080000', 'payment_security_hardening_v6', 'standard'),
    ('20260602090000', 'topup_lifecycle_and_listing_quota_v7', 'standard'),
    ('20260602100000', 'fix_subscription_can_subscribe_ambiguity', 'standard'),
    ('20260617000000', 'subscription_catalog_rpc_and_trial_fix', 'standard'),
    ('20260617110000', 'fix_rls_recursion_dedup_plans_payment', 'standard'),
    ('20260617120000', 'subscription_plans_policy_idempotent', 'standard'),
    ('20260617130000', 'subscription_plans_limits_review', 'standard'),
    ('20260617140000', 'billing_transactions_delete_own', 'standard'),
    ('20260618190000', 'subscription_comprehensive_shamel_v8', 'standard'),
    ('20260629120000', 'subscription_partner_excellence_v9', 'standard'),
    ('20260629140000', 'instant_market_request_payment_v10', 'standard'),
    ('20260629150000', 'instant_market_request_integrity_v10_1', 'standard'),
    ('20260629180000', 'remove_partner_plan_owner_free_tier', 'standard'),
    ('20260828030000', 'validate_payment_intent_addons', 'standard'),
    ('20260828040000', 'trust_line_stability_lock', 'standard'),
    ('20260829010000', 'platform_fee_catalog_guest_one_time', 'standard'),
    ('20260829270000', 'promo_codes_and_grant_plan', 'standard'),
    ('20260829280000', 'promo_windows_support_welcome', 'standard'),
    ('20260910000000', 'subscription_catalog_by_account_type', 'standard'),
    ('20260911000000', 'billing_idempotency_and_fulfillment', 'standard'),
    ('20260911201500', 'checkout_best_of_discount', 'standard'),
    ('20260911223000', 'user_invoice_seq', 'standard'),
    ('20260911230000', 'subscription_fulfillment_and_rls', 'standard'),
    ('20260911235959', 'user_subscriptions_period_one_time', 'standard'),
    ('20260912000000', 'validate_payment_intent_account_type', 'standard'),
    ('20260913000100', 'promo_audience_and_refund_lock', 'standard'),
    ('20260915000000', 'billing_intent_expiry_and_webhook_events', 'standard'),
    ('20260916000000', 'subscription_expire_pg_cron', 'standard'),
    ('20260917000000', 'invoice_number_hide_and_immutable', 'standard'),
    ('20260918000000', 'checkout_offer_discount_policy', 'standard'),
    ('20260919000000', 'promo_redeem_success_only', 'standard'),
    ('20260925120000', 'photographer_subscription_audience', 'standard'),
    ('20260925140000', 'photographer_catalog_trial', 'standard'),
    ('20261014000000', 'repair_billing_user_invoice_seq_trigger', 'standard'),
    ('20261014010000', 'individual_deal_plan_catalog_visibility', 'standard'),
    ('20261018010000', 'individual_main_lifetime_plan_and_quotas', 'manual_review'),
    ('20261019010000', 'deduplicate_individual_main_plans', 'manual_review'),
    ('20261019020000', 'individual_one_time_operation_credits', 'standard'),
    ('20261019030000', 'individual_operation_credit_consumption', 'standard'),
    ('20261019040000', 'role_aware_single_operation_credits', 'standard')
),
applied_migrations AS (
  SELECT version::text AS version
  FROM supabase_migrations.schema_migrations
),
expected_tables(table_name) AS (
  VALUES
    ('subscription_plans'),
    ('user_subscriptions'),
    ('saved_cards'),
    ('billing_transactions'),
    ('subscription_promotions'),
    ('subscription_promotion_redemptions'),
    ('platform_fee_catalog'),
    ('moyasar_webhook_events'),
    ('market_request_instant_credits'),
    ('instant_credit_ledger'),
    ('market_request_subscription_usage'),
    ('market_offer_single_use_credit_usage'),
    ('market_request_offer_atomic_authorizations')
),
expected_columns(table_name, column_name) AS (
  VALUES
    ('subscription_plans', 'user_type'),
    ('subscription_plans', 'sort_order'),
    ('subscription_plans', 'is_active'),
    ('subscription_plans', 'is_trial_plan'),
    ('subscription_plans', 'plan_program'),
    ('subscription_plans', 'price_monthly'),
    ('subscription_plans', 'price_yearly'),
    ('subscription_plans', 'max_listing_requests'),
    ('subscription_plans', 'max_market_offers'),
    ('subscription_plans', 'auto_pay_discount_percent'),
    ('user_subscriptions', 'user_id'),
    ('user_subscriptions', 'plan_id'),
    ('user_subscriptions', 'status'),
    ('user_subscriptions', 'period'),
    ('user_subscriptions', 'starts_at'),
    ('user_subscriptions', 'ends_at'),
    ('user_subscriptions', 'is_lifetime'),
    ('user_subscriptions', 'is_trial'),
    ('user_subscriptions', 'is_topup'),
    ('user_subscriptions', 'service_audience'),
    ('saved_cards', 'user_id'),
    ('saved_cards', 'card_token'),
    ('saved_cards', 'last_four'),
    ('saved_cards', 'card_scheme'),
    ('saved_cards', 'expiry_month'),
    ('saved_cards', 'expiry_year'),
    ('saved_cards', 'is_default'),
    ('billing_transactions', 'user_id'),
    ('billing_transactions', 'amount'),
    ('billing_transactions', 'currency'),
    ('billing_transactions', 'status'),
    ('billing_transactions', 'payment_method'),
    ('billing_transactions', 'gateway_transaction_id'),
    ('billing_transactions', 'gateway_response'),
    ('billing_transactions', 'purpose'),
    ('billing_transactions', 'plan_id'),
    ('billing_transactions', 'billing_period'),
    ('billing_transactions', 'idempotency_key'),
    ('billing_transactions', 'invoice_number'),
    ('billing_transactions', 'user_invoice_seq'),
    ('billing_transactions', 'subtotal_sar'),
    ('billing_transactions', 'discount_sar'),
    ('billing_transactions', 'vat_sar'),
    ('billing_transactions', 'fees_sar'),
    ('billing_transactions', 'vat_included'),
    ('billing_transactions', 'fulfillment_applied_at'),
    ('billing_transactions', 'paid_at'),
    ('billing_transactions', 'refunded_at'),
    ('billing_transactions', 'refund_amount'),
    ('billing_transactions', 'failure_code'),
    ('billing_transactions', 'failure_reason'),
    ('billing_transactions', 'review_required'),
    ('billing_transactions', 'expires_at'),
    ('billing_transactions', 'pricing_version'),
    ('billing_transactions', 'gateway_status'),
    ('billing_transactions', 'gateway_environment'),
    ('billing_transactions', 'hidden_from_user'),
    ('platform_fee_catalog', 'fee_key'),
    ('platform_fee_catalog', 'amount_sar'),
    ('moyasar_webhook_events', 'event_type'),
    ('moyasar_webhook_events', 'payment_id'),
    ('moyasar_webhook_events', 'billing_transaction_id'),
    ('moyasar_webhook_events', 'fingerprint'),
    ('market_request_instant_credits', 'billing_transaction_id'),
    ('market_request_instant_credits', 'status'),
    ('market_request_subscription_usage', 'subscription_id'),
    ('market_request_subscription_usage', 'single_use_credit'),
    ('market_offer_single_use_credit_usage', 'subscription_id'),
    ('market_request_offer_atomic_authorizations', 'transaction_id')
),
expected_functions(function_name, required_role) AS (
  VALUES
    ('list_subscription_catalog_plans', 'authenticated'),
    ('subscription_allowed_sorts_for_audience', 'authenticated'),
    ('validate_payment_intent', 'authenticated'),
    ('quote_checkout_offer', 'authenticated'),
    ('list_eligible_promo_codes', 'authenticated'),
    ('create_pending_billing_from_intent', 'authenticated'),
    ('create_pending_billing_catalog_fee', 'authenticated'),
    ('fulfill_paid_billing', 'authenticated'),
    ('mark_billing_gateway_outcome', 'service_role'),
    ('record_moyasar_webhook_event', 'service_role'),
    ('create_instant_market_request_checkout', 'authenticated'),
    ('activate_instant_market_request_credit', 'authenticated'),
    ('redeem_promo_code', 'authenticated'),
    ('subscription_compute_upgrade_charge', 'authenticated'),
    ('compute_canonical_charge', 'authenticated')
),
expected_rls_tables(table_name) AS (
  VALUES
    ('subscription_plans'),
    ('user_subscriptions'),
    ('saved_cards'),
    ('billing_transactions'),
    ('subscription_promotions'),
    ('subscription_promotion_redemptions'),
    ('platform_fee_catalog'),
    ('market_request_instant_credits'),
    ('instant_credit_ledger'),
    ('market_request_subscription_usage'),
    ('market_offer_single_use_credit_usage'),
    ('market_request_offer_atomic_authorizations')
),
function_state AS (
  SELECT
    e.function_name,
    e.required_role,
    count(p.oid) > 0 AS function_exists,
    coalesce(
      bool_or(
        has_function_privilege(e.required_role, p.oid, 'EXECUTE')
      ) FILTER (WHERE p.oid IS NOT NULL),
      false
    ) AS role_can_execute
  FROM expected_functions e
  LEFT JOIN pg_proc p
    ON p.pronamespace = 'public'::regnamespace
   AND p.proname = e.function_name
  GROUP BY e.function_name, e.required_role
),
findings AS (
  SELECT
    CASE WHEN e.apply_mode = 'manual_review' THEN 'REVIEW' ELSE 'HIGH' END AS severity,
    'migration_history' AS area,
    e.version || '_' || e.migration_name AS item,
    CASE
      WHEN e.apply_mode = 'manual_review' THEN 'NOT_IN_HISTORY_REVIEW_BEFORE_APPLY'
      ELSE 'NOT_IN_HISTORY'
    END AS status,
    'Migration version is absent from supabase_migrations.schema_migrations.'
      AS details,
    CASE
      WHEN e.apply_mode = 'manual_review' THEN
        'Check the actual schema and review this migration before running it; its file is explicitly marked for manual review.'
      ELSE
        'If it was never applied, apply pending repository migrations in timestamp order. If it was run manually, verify its objects before repairing migration history.'
    END AS recommended_action
  FROM expected_migrations e
  LEFT JOIN applied_migrations a ON a.version = e.version
  WHERE a.version IS NULL

  UNION ALL

  SELECT
    'HIGH',
    'table',
    'public.' || e.table_name,
    'MISSING',
    'Required billing/subscription table does not exist.',
    'Apply the repository migration that creates this table; do not create a substitute table by hand.'
  FROM expected_tables e
  LEFT JOIN information_schema.tables t
    ON t.table_schema = 'public'
   AND t.table_name = e.table_name
  WHERE t.table_name IS NULL

  UNION ALL

  SELECT
    'HIGH',
    'column',
    'public.' || e.table_name || '.' || e.column_name,
    'MISSING',
    'Required billing/subscription column does not exist.',
    'Apply the migration that adds this column; do not add it manually without checking its constraints and triggers.'
  FROM expected_columns e
  LEFT JOIN information_schema.columns c
    ON c.table_schema = 'public'
   AND c.table_name = e.table_name
   AND c.column_name = e.column_name
  WHERE c.column_name IS NULL
    AND EXISTS (
      SELECT 1
      FROM information_schema.tables t
      WHERE t.table_schema = 'public'
        AND t.table_name = e.table_name
    )

  UNION ALL

  SELECT
    'HIGH',
    'rpc',
    'public.' || f.function_name,
    CASE
      WHEN NOT f.function_exists THEN 'MISSING'
      ELSE 'EXECUTE_NOT_GRANTED_TO_' || f.required_role
    END,
    'Required RPC is missing or the application/server role cannot execute it.',
    'Apply the migration that defines the RPC and grants its intended role; preserve service_role-only access for gateway outcome functions.'
  FROM function_state f
  WHERE NOT f.function_exists OR NOT f.role_can_execute

  UNION ALL

  SELECT
    'HIGH',
    'row_level_security',
    'public.' || e.table_name,
    'RLS_DISABLED',
    'A billing/subscription table exists without row-level security enabled.',
    'Review and apply the table-specific RLS migration before exposing the table through the Supabase API.'
  FROM expected_rls_tables e
  JOIN pg_class c ON c.relname = e.table_name
  JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
  WHERE c.relkind IN ('r', 'p')
    AND NOT c.relrowsecurity
)
SELECT severity, area, item, status, details, recommended_action
FROM findings
ORDER BY
  CASE severity WHEN 'HIGH' THEN 1 WHEN 'REVIEW' THEN 2 ELSE 3 END,
  area,
  item;

-- After the schema checks pass, this optional read-only query shows plan rows
-- used by current individual and marketing catalogs:
--
-- SELECT user_type, sort_order, is_active, is_trial_plan, plan_program,
--        price_monthly, price_yearly
-- FROM public.subscription_plans
-- WHERE user_type IN ('individual', 'marketer', 'office', 'institution', 'company')
--   AND sort_order IN (1, 2, 3, 4, 11, 12, 14, 15, 16, 21, 22, 23, 24)
-- ORDER BY user_type, sort_order, is_trial_plan;
