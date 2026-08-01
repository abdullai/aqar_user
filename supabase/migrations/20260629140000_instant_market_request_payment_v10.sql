-- =============================================================================
-- v10: دفع «طلب فوري» — 30 ر.س/طلب — رصيد قابل للاستخدام أو الاسترجاع
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.market_request_instant_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  billing_transaction_id uuid NOT NULL REFERENCES public.billing_transactions (id) ON DELETE RESTRICT,
  amount_sar numeric(10,2) NOT NULL DEFAULT 30.00,
  status text NOT NULL DEFAULT 'pending_payment'
    CHECK (status IN ('pending_payment', 'available', 'consumed', 'refunded')),
  market_request_id uuid REFERENCES public.market_property_requests (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz,
  consumed_at timestamptz,
  refunded_at timestamptz,
  CONSTRAINT market_request_instant_credits_amount_positive CHECK (amount_sar > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_market_request_instant_credits_billing
  ON public.market_request_instant_credits (billing_transaction_id);

CREATE INDEX IF NOT EXISTS idx_market_request_instant_credits_user_status
  ON public.market_request_instant_credits (user_id, status, created_at DESC);

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS instant_credit_id uuid
    REFERENCES public.market_request_instant_credits (id) ON DELETE SET NULL;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS instant_paid_at timestamptz;

COMMENT ON TABLE public.market_request_instant_credits IS
  'رصيد دفع «طلب فوري» — يُستهلك عند نشر الطلب أو يُسترد إذا لم يُستخدم.';

ALTER TABLE public.market_request_instant_credits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS market_request_instant_credits_select_own
  ON public.market_request_instant_credits;
CREATE POLICY market_request_instant_credits_select_own
  ON public.market_request_instant_credits FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ── إنشاء سجل pending + billing ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_instant_market_request_checkout()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bid uuid;
  v_cid uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  INSERT INTO public.billing_transactions (
    user_id, amount, currency, status, payment_method,
    title_ar, title_en, gateway_response
  ) VALUES (
    v_uid, 30.00, 'SAR', 'pending', 'card',
    N'طلب عقاري فوري — 30 ر.س',
    'Instant property request — SAR 30',
    jsonb_build_object(
      'purpose', 'instant_market_request',
      'product', 'aqar_reliable',
      'unit_price_sar', 30
    )
  )
  RETURNING id INTO v_bid;

  INSERT INTO public.market_request_instant_credits (
    user_id, billing_transaction_id, amount_sar, status
  ) VALUES (
    v_uid, v_bid, 30.00, 'pending_payment'
  )
  RETURNING id INTO v_cid;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', v_cid,
    'billing_transaction_id', v_bid,
    'amount_sar', 30.00,
    'purpose', 'instant_market_request'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_instant_market_request_checkout() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_instant_market_request_checkout()
  TO authenticated;

-- ── تفعيل الرصيد بعد نجاح الدفع ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.activate_instant_market_request_credit(
  p_billing_transaction_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.market_request_instant_credits%ROWTYPE;
  v_bill public.billing_transactions%ROWTYPE;
BEGIN
  IF p_billing_transaction_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_required');
  END IF;

  SELECT * INTO v_bill FROM public.billing_transactions
   WHERE id = p_billing_transaction_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;
  IF v_bill.status <> 'success' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_success', 'status', v_bill.status);
  END IF;
  IF abs(v_bill.amount - 30.00) > 0.05 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'amount_mismatch');
  END IF;

  SELECT * INTO v_row FROM public.market_request_instant_credits
   WHERE billing_transaction_id = p_billing_transaction_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_found');
  END IF;

  IF v_row.status = 'available' THEN
    RETURN jsonb_build_object('ok', true, 'credit_id', v_row.id, 'already_active', true);
  END IF;
  IF v_row.status = 'consumed' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_consumed');
  END IF;
  IF v_row.status = 'refunded' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_refunded');
  END IF;

  UPDATE public.market_request_instant_credits
     SET status = 'available',
         activated_at = coalesce(activated_at, now())
   WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', v_row.id,
    'billing_transaction_id', p_billing_transaction_id,
    'amount_sar', v_row.amount_sar
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_instant_market_request_credit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_instant_market_request_credit(uuid)
  TO authenticated, service_role;

-- ── رصيد متاح للمستخدم ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_available_instant_market_request_credit()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.market_request_instant_credits%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO v_row
  FROM public.market_request_instant_credits c
  WHERE c.user_id = v_uid
    AND c.status = 'available'
  ORDER BY c.activated_at DESC NULLS LAST, c.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'has_credit', false);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'has_credit', true,
    'credit_id', v_row.id,
    'billing_transaction_id', v_row.billing_transaction_id,
    'amount_sar', v_row.amount_sar,
    'activated_at', v_row.activated_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_available_instant_market_request_credit() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_instant_market_request_credit()
  TO authenticated;

-- ── استهلاك عند نشر الطلب ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.consume_instant_market_request_credit(
  p_credit_id uuid,
  p_market_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.market_request_instant_credits%ROWTYPE;
  v_req public.market_property_requests%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_credit_id IS NULL OR p_market_request_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_args');
  END IF;

  SELECT * INTO v_row FROM public.market_request_instant_credits
   WHERE id = p_credit_id AND user_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_found');
  END IF;
  IF v_row.status <> 'available' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_available', 'status', v_row.status);
  END IF;

  SELECT * INTO v_req FROM public.market_property_requests
   WHERE id = p_market_request_id AND requester_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'request_not_found');
  END IF;
  IF coalesce(v_req.request_priority, 'standard') <> 'immediate' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_immediate_request');
  END IF;

  UPDATE public.market_request_instant_credits
     SET status = 'consumed',
         market_request_id = p_market_request_id,
         consumed_at = now()
   WHERE id = p_credit_id;

  UPDATE public.market_property_requests
     SET instant_credit_id = p_credit_id,
         instant_paid_at = now(),
         request_priority = 'immediate'
   WHERE id = p_market_request_id;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', p_credit_id,
    'market_request_id', p_market_request_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.consume_instant_market_request_credit(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_instant_market_request_credit(uuid, uuid)
  TO authenticated;

-- ── استرجاع إذا لم يُستهلك ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.refund_unused_instant_market_request_credit(
  p_credit_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.market_request_instant_credits%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT * INTO v_row FROM public.market_request_instant_credits
   WHERE id = p_credit_id AND user_id = v_uid
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'credit_not_found');
  END IF;
  IF v_row.status <> 'available' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'not_refundable',
      'status', v_row.status,
      'message_ar', CASE v_row.status
        WHEN 'consumed' THEN 'لا يمكن الاسترجاع — تم استخدام الدفع في طلب فوري.'
        WHEN 'refunded' THEN 'تم الاسترجاع مسبقاً.'
        WHEN 'pending_payment' THEN 'لم يكتمل الدفع بعد.'
        ELSE 'الرصيد غير قابل للاسترجاع.'
      END
    );
  END IF;

  UPDATE public.billing_transactions
     SET status = 'refunded',
         gateway_response = coalesce(gateway_response, '{}'::jsonb)
           || jsonb_build_object('refunded_at', now(), 'refund_reason', 'unused_instant_credit'),
         completed_at = coalesce(completed_at, now())
   WHERE id = v_row.billing_transaction_id
     AND user_id = v_uid
     AND status = 'success';

  UPDATE public.market_request_instant_credits
     SET status = 'refunded',
         refunded_at = now()
   WHERE id = p_credit_id;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', p_credit_id,
    'billing_transaction_id', v_row.billing_transaction_id,
    'refunded_sar', v_row.amount_sar,
    'message_ar', 'تم إلغاء رصيد الطلب الفوري وعكس العملية على نفس وسيلة الدفع (حسب سياسة البوابة).',
    'message_en', 'Instant request credit cancelled; reversal initiated to the original payment method.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.refund_unused_instant_market_request_credit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refund_unused_instant_market_request_credit(uuid)
  TO authenticated;

-- ── trigger: تفعيل الرصيد تلقائياً عند success ─────────────────────────────

CREATE OR REPLACE FUNCTION public.tr_billing_activate_instant_credit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'success' AND (OLD.status IS DISTINCT FROM 'success') THEN
    IF EXISTS (
      SELECT 1 FROM public.market_request_instant_credits c
      WHERE c.billing_transaction_id = NEW.id
        AND c.status = 'pending_payment'
    ) THEN
      PERFORM public.activate_instant_market_request_credit(NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_billing_activate_instant_credit ON public.billing_transactions;
CREATE TRIGGER tr_billing_activate_instant_credit
  AFTER UPDATE OF status ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_billing_activate_instant_credit();

COMMIT;
