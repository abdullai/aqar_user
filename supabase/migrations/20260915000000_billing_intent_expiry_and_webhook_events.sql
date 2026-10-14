-- =============================================================================
-- 2026-09-15 — intent expires_at + gateway_status + webhook event idempotency
-- لا يغيّر الأسعار. لا DROP بيانات.
-- =============================================================================

BEGIN;

ALTER TABLE public.billing_transactions
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS pricing_version text NOT NULL DEFAULT 'catalog_v1',
  ADD COLUMN IF NOT EXISTS gateway_status text,
  ADD COLUMN IF NOT EXISTS gateway_environment text
    CHECK (gateway_environment IS NULL OR gateway_environment IN ('test', 'live'));

UPDATE public.billing_transactions
   SET expires_at = created_at + interval '2 hours'
 WHERE status = 'pending'
   AND expires_at IS NULL;

CREATE TABLE IF NOT EXISTS public.moyasar_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type text NOT NULL,
  payment_id text,
  billing_transaction_id uuid,
  fingerprint text NOT NULL,
  payload jsonb,
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_moyasar_webhook_events_payment
  ON public.moyasar_webhook_events (payment_id, created_at DESC);

ALTER TABLE public.moyasar_webhook_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.trg_billing_intent_defaults()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'pending' AND NEW.expires_at IS NULL THEN
      NEW.expires_at := timezone('utc', now()) + interval '2 hours';
    END IF;
    IF NEW.pricing_version IS NULL OR trim(NEW.pricing_version) = '' THEN
      NEW.pricing_version := 'catalog_v1';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_billing_intent_defaults ON public.billing_transactions;
CREATE TRIGGER tr_billing_intent_defaults
  BEFORE INSERT ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_billing_intent_defaults();

CREATE OR REPLACE FUNCTION public.record_moyasar_webhook_event(
  p_event_type text,
  p_payment_id text,
  p_billing_transaction_id uuid,
  p_payload jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fp text;
BEGIN
  v_fp := md5(
    coalesce(p_event_type, '') || '|' ||
    coalesce(p_payment_id, '') || '|' ||
    coalesce(p_billing_transaction_id::text, '') || '|' ||
    coalesce(p_payload->>'id', '')
  );
  INSERT INTO public.moyasar_webhook_events (
    event_type, payment_id, billing_transaction_id, fingerprint, payload
  ) VALUES (
    coalesce(nullif(trim(p_event_type), ''), 'unknown'),
    nullif(trim(p_payment_id), ''),
    p_billing_transaction_id,
    v_fp,
    p_payload
  );
  RETURN jsonb_build_object('ok', true, 'duplicate', false);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok', true, 'duplicate', true);
END;
$$;

REVOKE ALL ON FUNCTION public.record_moyasar_webhook_event(text, text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_moyasar_webhook_event(text, text, uuid, jsonb)
  TO service_role;

CREATE OR REPLACE FUNCTION public.mark_billing_gateway_outcome(
  p_billing_transaction_id uuid,
  p_status text,
  p_gateway_transaction_id text DEFAULT NULL,
  p_gateway_response jsonb DEFAULT NULL,
  p_failure_code text DEFAULT NULL,
  p_failure_reason text DEFAULT NULL,
  p_review_required boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  bt public.billing_transactions%ROWTYPE;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_env text;
BEGIN
  SELECT * INTO bt FROM public.billing_transactions WHERE id = p_billing_transaction_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;

  IF v_status = 'success' AND bt.status = 'success'
     AND coalesce(bt.gateway_transaction_id, '') = coalesce(nullif(trim(p_gateway_transaction_id), ''), bt.gateway_transaction_id) THEN
    RETURN jsonb_build_object('ok', true, 'duplicate', true);
  END IF;

  IF v_status = 'success' AND bt.expires_at IS NOT NULL
     AND bt.expires_at < timezone('utc', now())
     AND bt.status = 'pending' THEN
    UPDATE public.billing_transactions
       SET status = 'expired',
           failure_code = 'intent_expired',
           failure_reason = 'pending_intent_expired',
           review_required = true,
           completed_at = coalesce(completed_at, timezone('utc', now()))
     WHERE id = bt.id AND status = 'pending';
    RETURN jsonb_build_object('ok', false, 'error', 'intent_expired');
  END IF;

  IF v_status = 'success' AND bt.status NOT IN ('pending', 'authorized') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'illegal_status_transition', 'from', bt.status, 'to', v_status);
  END IF;

  IF v_status = 'success' AND bt.status IN ('failed', 'cancelled', 'expired', 'refunded') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'illegal_status_transition');
  END IF;

  v_env := CASE
    WHEN coalesce(p_gateway_response->>'livemode', '') IN ('true', 't') THEN 'live'
    WHEN coalesce(p_gateway_response->>'livemode', '') IN ('false', 'f') THEN 'test'
    ELSE bt.gateway_environment
  END;

  UPDATE public.billing_transactions
     SET status = v_status,
         gateway_status = coalesce(p_gateway_response->>'status', v_status),
         gateway_environment = coalesce(v_env, gateway_environment),
         gateway_transaction_id = coalesce(nullif(trim(p_gateway_transaction_id), ''), gateway_transaction_id),
         gateway_response = coalesce(p_gateway_response, gateway_response),
         failure_code = p_failure_code,
         failure_reason = p_failure_reason,
         review_required = coalesce(p_review_required, false),
         paid_at = CASE WHEN v_status = 'success' THEN coalesce(paid_at, timezone('utc', now())) ELSE paid_at END,
         completed_at = CASE WHEN v_status IN ('success', 'failed', 'cancelled', 'expired', 'refunded')
           THEN coalesce(completed_at, timezone('utc', now())) ELSE completed_at END
   WHERE id = bt.id;

  RETURN jsonb_build_object('ok', true, 'status', v_status);
END;
$$;

REVOKE ALL ON FUNCTION public.mark_billing_gateway_outcome(uuid, text, text, jsonb, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_billing_gateway_outcome(uuid, text, text, jsonb, text, text, boolean)
  TO service_role;

CREATE OR REPLACE FUNCTION public.subscription_expire_due()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
BEGIN
  FOR r IN
    SELECT id, user_id, organization_id
      FROM public.user_subscriptions
     WHERE status = 'active'
       AND coalesce(is_lifetime, false) = false
       AND coalesce(ends_at, end_date::timestamptz) IS NOT NULL
       AND coalesce(ends_at, end_date::timestamptz) <= timezone('utc', now())
     FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.user_subscriptions
       SET status = 'expired',
           auto_renew = false,
           updated_at = timezone('utc', now())
     WHERE id = r.id AND status = 'active';
    PERFORM public._subscription_lifecycle_write(
      r.user_id, 'subscription_expired', r.id, r.organization_id, '{}'::jsonb
    );
    n := n + 1;
  END LOOP;

  UPDATE public.billing_transactions
     SET status = 'expired',
         failure_code = 'pending_expired',
         completed_at = coalesce(completed_at, timezone('utc', now()))
   WHERE status = 'pending'
     AND (
       (expires_at IS NOT NULL AND expires_at < timezone('utc', now()))
       OR created_at < timezone('utc', now()) - interval '2 hours'
     );

  RETURN jsonb_build_object('ok', true, 'expired_count', n);
END;
$$;

REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM anon;
REVOKE ALL ON FUNCTION public.subscription_expire_due() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.subscription_expire_due() TO service_role;

COMMIT;
