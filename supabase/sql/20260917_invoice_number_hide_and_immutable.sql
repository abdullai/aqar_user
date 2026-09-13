-- رقم فاتورة رسمي لكل صف قديم + إخفاء من السجل بدل الحذف المالي.
-- لا يغيّر المبالغ ولا حالات Moyasar ولا الاشتراك.

BEGIN;

ALTER TABLE public.billing_transactions
  ADD COLUMN IF NOT EXISTS hidden_from_user boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_billing_hidden_user
  ON public.billing_transactions (user_id, hidden_from_user, created_at DESC);

CREATE OR REPLACE FUNCTION public._billing_invoice_number_for(p_at timestamptz)
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN 'INV-' || to_char(timezone('utc', coalesce(p_at, timezone('utc', now()))), 'YYYYMMDD') || '-' ||
         lpad(nextval('public.billing_invoice_seq')::text, 6, '0');
END;
$$;

CREATE OR REPLACE FUNCTION public._billing_next_invoice_number()
RETURNS text
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN public._billing_invoice_number_for(timezone('utc', now()));
END;
$$;

-- صفوف قديمة بلا رقم: رقم فريد من تسلسل الخادم + تاريخ الإنشاء. لا يُشتق من UUID.
UPDATE public.billing_transactions
   SET invoice_number = public._billing_invoice_number_for(created_at)
 WHERE invoice_number IS NULL;

CREATE OR REPLACE FUNCTION public.trg_billing_tx_before_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.invoice_number IS NULL OR length(trim(NEW.invoice_number)) = 0 THEN
      NEW.invoice_number := public._billing_invoice_number_for(coalesce(NEW.created_at, timezone('utc', now())));
    END IF;
    IF NEW.subtotal_sar IS NULL THEN
      NEW.subtotal_sar := NEW.amount;
    END IF;
    NEW.gateway_transaction_id := nullif(trim(coalesce(NEW.gateway_transaction_id, '')), '');
    NEW.hidden_from_user := coalesce(NEW.hidden_from_user, false);
    RETURN NEW;
  END IF;

  NEW.updated_at := timezone('utc', now());
  NEW.gateway_transaction_id := nullif(trim(coalesce(NEW.gateway_transaction_id, '')), '');

  IF OLD.invoice_number IS NOT NULL
     AND NEW.invoice_number IS DISTINCT FROM OLD.invoice_number THEN
    RAISE EXCEPTION 'invoice_number_immutable';
  END IF;
  IF NEW.invoice_number IS NULL OR length(trim(NEW.invoice_number)) = 0 THEN
    NEW.invoice_number := public._billing_invoice_number_for(coalesce(NEW.created_at, timezone('utc', now())));
  END IF;

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
    IF NEW.paid_at IS DISTINCT FROM OLD.paid_at THEN
      RAISE EXCEPTION 'paid_at_server_only';
    END IF;
    IF NEW.discount_sar IS DISTINCT FROM OLD.discount_sar
       OR NEW.vat_sar IS DISTINCT FROM OLD.vat_sar
       OR NEW.fees_sar IS DISTINCT FROM OLD.fees_sar
       OR NEW.subtotal_sar IS DISTINCT FROM OLD.subtotal_sar
       OR NEW.vat_included IS DISTINCT FROM OLD.vat_included
       OR NEW.currency IS DISTINCT FROM OLD.currency
       OR NEW.refund_amount IS DISTINCT FROM OLD.refund_amount
       OR NEW.refunded_at IS DISTINCT FROM OLD.refunded_at
       OR NEW.gateway_transaction_id IS DISTINCT FROM OLD.gateway_transaction_id THEN
      RAISE EXCEPTION 'billing_fields_server_only';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_billing_tx_before_write ON public.billing_transactions;
CREATE TRIGGER tr_billing_tx_before_write
  BEFORE INSERT OR UPDATE ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_billing_tx_before_write();

-- الفاتورة مستند مالي: لا حذف صف من العميل.
DROP POLICY IF EXISTS billing_transactions_delete_own ON public.billing_transactions;

CREATE OR REPLACE FUNCTION public.billing_hide_own_invoice(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth');
  END IF;
  UPDATE public.billing_transactions
     SET hidden_from_user = true,
         updated_at = timezone('utc', now())
   WHERE id = p_id
     AND user_id = auth.uid();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.billing_hide_own_invoice(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.billing_hide_own_invoice(uuid) TO authenticated;

COMMIT;
