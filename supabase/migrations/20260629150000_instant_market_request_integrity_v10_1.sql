-- v10.1: حماية الطلب الفوري — لا يبقى منشوراً بدون رصيد مُستهلك؛ حذف عند الاسترجاع
BEGIN;

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

  -- أي طلب مسودة «فوري» للمستخدم يُحذف عند استرجاع الرصيد (لم يُستهلك).
  DELETE FROM public.market_property_requests
   WHERE requester_id = v_uid
     AND coalesce(request_priority, 'standard') = 'immediate'
     AND coalesce(status, '') = 'draft'
     AND created_at >= coalesce(v_row.activated_at, v_row.created_at) - interval '7 days';

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
         refunded_at = now(),
         market_request_id = NULL
   WHERE id = p_credit_id;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', p_credit_id,
    'billing_transaction_id', v_row.billing_transaction_id,
    'refunded_sar', v_row.amount_sar,
    'message_ar', 'تم إلغاء رصيد الطلب الفوري. لن يظهر أي طلب مسودة مرتبط به.',
    'message_en', 'Instant credit cancelled; any linked unpublished request was removed.'
  );
END;
$$;

-- منع نشر «فوري» بدون رصيد consumed (على مستوى الخادم عند الربط).
CREATE OR REPLACE FUNCTION public.tr_market_request_instant_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_credit public.market_request_instant_credits%ROWTYPE;
BEGIN
  IF coalesce(NEW.request_priority, 'standard') <> 'immediate' THEN
    RETURN NEW;
  END IF;
  IF coalesce(NEW.status, '') NOT IN ('published', 'active', 'open') THEN
    RETURN NEW;
  END IF;
  IF NEW.instant_credit_id IS NULL THEN
    RAISE EXCEPTION 'instant_credit_required'
      USING HINT = 'الطلب الفوري يتطلب رصيد دفع مُستهلك قبل النشر.';
  END IF;
  SELECT * INTO v_credit FROM public.market_request_instant_credits
   WHERE id = NEW.instant_credit_id;
  IF NOT FOUND OR v_credit.status <> 'consumed' THEN
    RAISE EXCEPTION 'instant_credit_not_consumed';
  END IF;
  IF NEW.instant_paid_at IS NULL THEN
    NEW.instant_paid_at := coalesce(v_credit.consumed_at, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_market_request_instant_integrity
  ON public.market_property_requests;
CREATE TRIGGER tr_market_request_instant_integrity
  BEFORE INSERT OR UPDATE OF status, request_priority, instant_credit_id
  ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.tr_market_request_instant_integrity();

COMMIT;
