-- Idempotent auto-renew extension after a successful billing row (server/cron or webhook).
-- Uses interval arithmetic in UTC (aligned with app for typical monthly/yearly renewals).

ALTER TABLE public.billing_transactions
  ADD COLUMN IF NOT EXISTS renewal_extension_applied_at timestamptz;

CREATE OR REPLACE FUNCTION public.subscription_apply_auto_renew_extension(
  p_subscription_id uuid,
  p_billing_transaction_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bt public.billing_transactions%ROWTYPE;
  s public.user_subscriptions%ROWTYPE;
  pl public.subscription_plans%ROWTYPE;
  expect numeric(10, 2);
  base_ts timestamptz;
  new_end timestamptz;
  v_updated int;
BEGIN
  SELECT * INTO bt
  FROM public.billing_transactions
  WHERE id = p_billing_transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'billing_not_found');
  END IF;

  IF bt.subscription_id IS DISTINCT FROM p_subscription_id THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'subscription_mismatch');
  END IF;

  IF bt.status IS DISTINCT FROM 'success' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'billing_not_success', 'status', bt.status);
  END IF;

  IF bt.renewal_extension_applied_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true);
  END IF;

  SELECT * INTO s
  FROM public.user_subscriptions
  WHERE id = p_subscription_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'subscription_not_found');
  END IF;

  SELECT * INTO pl FROM public.subscription_plans WHERE id = s.plan_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'plan_not_found');
  END IF;

  expect := CASE
    WHEN s.period = 'yearly' THEN pl.price_yearly
    ELSE pl.price_monthly
  END;

  IF expect IS NULL OR abs(bt.amount - expect) > 0.05 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'amount_mismatch', 'expected', expect, 'got', bt.amount);
  END IF;

  base_ts := greatest(s.ends_at, timezone('utc', now()));
  new_end := base_ts + CASE
    WHEN s.period = 'yearly' THEN interval '1 year'
    ELSE interval '1 month'
  END;

  UPDATE public.user_subscriptions
  SET
    ends_at = new_end,
    end_date = (new_end::date - 1),
    status = 'active',
    cancelled_at = NULL,
    auto_renew_last_failure_at = NULL,
    auto_renew_last_failure_reason = NULL
  WHERE id = p_subscription_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'subscription_update_zero');
  END IF;

  UPDATE public.billing_transactions
  SET renewal_extension_applied_at = timezone('utc', now())
  WHERE id = p_billing_transaction_id
    AND renewal_extension_applied_at IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'ends_at', new_end);
END;
$$;

REVOKE ALL ON FUNCTION public.subscription_apply_auto_renew_extension(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_apply_auto_renew_extension(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.subscription_apply_auto_renew_extension(uuid, uuid) IS
  'Applies one subscription period extension after a successful auto-renew billing row; idempotent per billing id.';
