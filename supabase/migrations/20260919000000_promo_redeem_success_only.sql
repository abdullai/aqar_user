-- استهلاك الكود فقط بعد نجاح الدفع. لا يُستهلك على فاتورة معلّقة.
-- الـ webhook / mark_billing_gateway_outcome يستدعي _promo_finalize_on_paid_billing.

BEGIN;

CREATE OR REPLACE FUNCTION public.redeem_promo_code(
  p_code text,
  p_billing_transaction_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_tx public.billing_transactions%ROWTYPE;
  v_stored text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_billing_transaction_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_required');
  END IF;
  SELECT * INTO v_tx
  FROM public.billing_transactions
  WHERE id = p_billing_transaction_id AND user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_found');
  END IF;
  IF v_tx.status IS DISTINCT FROM 'success' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'billing_not_success');
  END IF;

  v_stored := public._promo_norm_code(coalesce(
    v_tx.gateway_response->>'promo_code',
    v_tx.gateway_response->'offer'->>'promo_code',
    p_code
  ));
  IF v_stored IS NOT NULL
     AND public._promo_norm_code(p_code) IS NOT NULL
     AND lower(v_stored) IS DISTINCT FROM lower(public._promo_norm_code(p_code)) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'code_mismatch');
  END IF;

  PERFORM public._promo_finalize_on_paid_billing(v_tx.id);
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.redeem_promo_code(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_promo_code(text, uuid)
  TO authenticated, service_role;

COMMIT;
