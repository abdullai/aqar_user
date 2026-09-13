-- =============================================================================
-- 2026-09-11 — تفعيل خادمي + إغلاق كتابة الاشتراك من العميل + مطابقة الدور
-- Forward-only. لا يغيّر أسعار الباقات.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) أعمدة الفاتورة + الاشتراك
-- ---------------------------------------------------------------------------
ALTER TABLE public.billing_transactions
  ADD COLUMN IF NOT EXISTS purpose text,
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.subscription_plans (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS billing_period text,
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS invoice_number text,
  ADD COLUMN IF NOT EXISTS subtotal_sar numeric(12,2),
  ADD COLUMN IF NOT EXISTS discount_sar numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vat_sar numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fees_sar numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS vat_included boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS fulfillment_applied_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS refunded_at timestamptz,
  ADD COLUMN IF NOT EXISTS refund_amount numeric(12,2),
  ADD COLUMN IF NOT EXISTS failure_reason text,
  ADD COLUMN IF NOT EXISTS failure_code text,
  ADD COLUMN IF NOT EXISTS review_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS uq_billing_invoice_number
  ON public.billing_transactions (invoice_number)
  WHERE invoice_number IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_billing_idempotency_user
  ON public.billing_transactions (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL
    AND length(trim(idempotency_key)) > 0
    AND status IN ('pending', 'success');

CREATE UNIQUE INDEX IF NOT EXISTS uq_billing_gateway_transaction_id
  ON public.billing_transactions (gateway_transaction_id)
  WHERE gateway_transaction_id IS NOT NULL AND length(trim(gateway_transaction_id)) > 0;

CREATE INDEX IF NOT EXISTS idx_billing_purpose_user
  ON public.billing_transactions (user_id, purpose, created_at DESC);

ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS is_lifetime boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS granted_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS grant_reason text;

ALTER TABLE public.user_subscriptions
  ALTER COLUMN end_date DROP NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_subscriptions' AND column_name = 'ends_at'
  ) THEN
    ALTER TABLE public.user_subscriptions ALTER COLUMN ends_at DROP NOT NULL;
  END IF;
END $$;

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public' AND t.relname = 'user_subscriptions'
      AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%period%'
  LOOP
    EXECUTE format('ALTER TABLE public.user_subscriptions DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.user_subscriptions
  ADD CONSTRAINT user_subscriptions_period_check
  CHECK (period IN ('monthly', 'yearly', 'one_time'));

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public' AND t.relname = 'billing_transactions'
      AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.billing_transactions DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.billing_transactions
  ADD CONSTRAINT billing_transactions_status_check
  CHECK (status IN (
    'pending', 'authorized', 'success', 'failed',
    'cancelled', 'expired', 'refunded', 'partially_refunded'
  ));

ALTER TABLE public.subscription_promotions
  ADD COLUMN IF NOT EXISTS min_amount_sar numeric(12,2),
  ADD COLUMN IF NOT EXISTS applies_periods text[],
  ADD COLUMN IF NOT EXISTS applies_plan_ids uuid[];

ALTER TABLE public.platform_staff
  ADD COLUMN IF NOT EXISTS can_refund boolean NOT NULL DEFAULT false;

UPDATE public.platform_staff
   SET can_refund = true
 WHERE coalesce(is_owner, false) OR coalesce(can_finance, false);

CREATE SEQUENCE IF NOT EXISTS public.billing_invoice_seq;

CREATE TABLE IF NOT EXISTS public.instant_credit_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  credit_id uuid REFERENCES public.market_request_instant_credits (id) ON DELETE SET NULL,
  billing_transaction_id uuid REFERENCES public.billing_transactions (id) ON DELETE SET NULL,
  entry_type text NOT NULL
    CHECK (entry_type IN (
      'credit', 'debit', 'reservation', 'consumed',
      'refunded', 'expired', 'manual_adjustment'
    )),
  units numeric(12,2) NOT NULL DEFAULT 1,
  amount_sar numeric(12,2),
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_instant_credit_ledger_user
  ON public.instant_credit_ledger (user_id, created_at DESC);

ALTER TABLE public.instant_credit_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS instant_credit_ledger_select_own ON public.instant_credit_ledger;
CREATE POLICY instant_credit_ledger_select_own ON public.instant_credit_ledger
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_platform_staff(auth.uid()));

-- ---------------------------------------------------------------------------
-- 2) رقم فاتورة + منع تغيير الحالة من العميل
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._billing_next_invoice_number()
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN 'INV-' || to_char(timezone('utc', now()), 'YYYYMMDD') || '-' ||
         lpad(nextval('public.billing_invoice_seq')::text, 6, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_billing_tx_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.invoice_number IS NULL THEN
      NEW.invoice_number := public._billing_next_invoice_number();
    END IF;
    IF NEW.subtotal_sar IS NULL THEN
      NEW.subtotal_sar := NEW.amount;
    END IF;
    NEW.gateway_transaction_id := nullif(trim(coalesce(NEW.gateway_transaction_id, '')), '');
    RETURN NEW;
  END IF;

  NEW.updated_at := timezone('utc', now());
  NEW.gateway_transaction_id := nullif(trim(coalesce(NEW.gateway_transaction_id, '')), '');

  IF NEW.amount IS DISTINCT FROM OLD.amount THEN
    RAISE EXCEPTION 'amount_immutable';
  END IF;

  IF auth.uid() IS NOT NULL
     AND NOT public.is_platform_staff(auth.uid()) THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      RAISE EXCEPTION 'status_server_only';
    END IF;
    IF NEW.fulfillment_applied_at IS DISTINCT FROM OLD.fulfillment_applied_at THEN
      RAISE EXCEPTION 'fulfillment_server_only';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_billing_tx_immutable_amount ON public.billing_transactions;
DROP TRIGGER IF EXISTS tr_billing_tx_before_write ON public.billing_transactions;
CREATE TRIGGER tr_billing_tx_before_write
  BEFORE INSERT OR UPDATE ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_billing_tx_before_write();

-- ---------------------------------------------------------------------------
-- 3) مطابقة الباقة مع نوع الحساب — مصدر واحد
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.subscription_map_account_audience(p_account_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_account_type, '')))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'photographer' THEN 'photographer'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(p_audience text)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_audience
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    WHEN 'photographer' THEN ARRAY[1]
    ELSE ARRAY[]::int[]
  END;
$$;

CREATE OR REPLACE FUNCTION public.subscription_audience_for_uid(p_uid uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_at text;
BEGIN
  IF p_uid IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT coalesce(nullif(trim(up.account_type::text), ''), '')
    INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = p_uid;
  IF v_at IS NULL OR v_at = '' THEN
    RETURN NULL;
  END IF;
  RETURN public.subscription_map_account_audience(v_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.subscription_assert_plan_allowed(p_uid uuid, p_plan_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_aud text;
  v_plan public.subscription_plans%ROWTYPE;
  v_sorts int[];
BEGIN
  IF p_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_required');
  END IF;

  v_aud := public.subscription_audience_for_uid(p_uid);
  IF v_aud IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'account_type_unknown');
  END IF;

  SELECT * INTO v_plan FROM public.subscription_plans WHERE id = p_plan_id;
  IF NOT FOUND OR coalesce(v_plan.is_active, false) = false THEN
    RETURN jsonb_build_object('ok', false, 'error', 'plan_invalid');
  END IF;

  v_sorts := public.subscription_allowed_sorts_for_audience(v_aud);
  IF coalesce(array_length(v_sorts, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'plan_account_mismatch',
      'audience', v_aud
    );
  END IF;

  IF lower(trim(v_plan.user_type)) IS DISTINCT FROM v_aud THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'plan_account_mismatch',
      'audience', v_aud,
      'plan_user_type', v_plan.user_type
    );
  END IF;

  IF NOT (coalesce(v_plan.sort_order, -1) = ANY (v_sorts)) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'plan_account_mismatch',
      'audience', v_aud,
      'sort_order', v_plan.sort_order
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'audience', v_aud,
    'plan_id', v_plan.id,
    'sort_order', v_plan.sort_order
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._billing_security_event(
  p_user_id uuid,
  p_event text,
  p_plan_id uuid,
  p_period text,
  p_amount numeric,
  p_payload jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.payment_security_audit
    (user_id, event, plan_id, period, amount_sar, expected_sar, payload)
  VALUES
    (p_user_id, p_event, p_plan_id, p_period, p_amount, NULL, coalesce(p_payload, '{}'::jsonb));
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._subscription_lifecycle_write(
  p_user_id uuid,
  p_event_type text,
  p_subscription_id uuid,
  p_organization_id uuid,
  p_payload jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.subscription_lifecycle_events (
    user_id, organization_id, subscription_id, event_type, payload
  ) VALUES (
    p_user_id, p_organization_id, p_subscription_id, p_event_type, coalesce(p_payload, '{}'::jsonb)
  );
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public.payment_security_audit (user_id, event, payload)
  VALUES (p_user_id, p_event_type, coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('lifecycle_insert_failed', true));
END;
$$;

-- توسيع أنواع أحداث الدورة دون كسر الصفوف القديمة
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public' AND t.relname = 'subscription_lifecycle_events'
      AND c.contype = 'c' AND pg_get_constraintdef(c.oid) ILIKE '%event_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.subscription_lifecycle_events DROP CONSTRAINT IF EXISTS %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.subscription_lifecycle_events
  ADD CONSTRAINT subscription_lifecycle_events_event_type_check
  CHECK (event_type IN (
    'subscription_started',
    'subscription_renewed',
    'subscription_upgraded',
    'subscription_cancel_requested',
    'subscription_cancel_finalized',
    'subscription_expired',
    'subscription_activated',
    'retention_offer_shown',
    'retention_offer_accepted',
    'retention_offer_declined',
    'churn_feedback',
    'topup_applied',
    'period_switched',
    'admin_grant',
    'admin_cancel'
  ));

COMMIT;
