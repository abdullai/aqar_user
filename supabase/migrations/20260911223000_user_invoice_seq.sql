-- ترقيم فواتير تصاعدي لكل مستخدم من 1، ونصوص الخصم المعتمدة للعرض.

BEGIN;

ALTER TABLE public.billing_transactions
  ADD COLUMN IF NOT EXISTS user_invoice_seq integer;

WITH numbered AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id
           ORDER BY coalesce(created_at, timezone('utc', now())), id
         ) AS seq
    FROM public.billing_transactions
)
UPDATE public.billing_transactions b
   SET user_invoice_seq = numbered.seq
  FROM numbered
 WHERE b.id = numbered.id
   AND (b.user_invoice_seq IS NULL OR b.user_invoice_seq IS DISTINCT FROM numbered.seq);

UPDATE public.billing_transactions
   SET user_invoice_seq = 1
 WHERE user_invoice_seq IS NULL;

ALTER TABLE public.billing_transactions
  ALTER COLUMN user_invoice_seq SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_billing_user_invoice_seq
  ON public.billing_transactions (user_id, user_invoice_seq);

CREATE OR REPLACE FUNCTION public._billing_next_user_invoice_seq(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  n int;
BEGIN
  IF p_user IS NULL THEN
    RETURN 1;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext(p_user::text));
  SELECT coalesce(max(user_invoice_seq), 0) + 1
    INTO n
    FROM public.billing_transactions
   WHERE user_id = p_user;
  RETURN n;
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
    IF NEW.user_invoice_seq IS NULL THEN
      NEW.user_invoice_seq := public._billing_next_user_invoice_seq(NEW.user_id);
    END IF;
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
  NEW.user_id := OLD.user_id;
  NEW.user_invoice_seq := OLD.user_invoice_seq;

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

COMMIT;
