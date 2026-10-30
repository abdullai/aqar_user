-- توحيد وصف عمليات الدفع ورمز الريال في الفواتير الجديدة والقديمة.
BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_billing_display_copy()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_purpose text := lower(trim(coalesce(NEW.purpose, '')));
  v_amount text := to_char(coalesce(NEW.amount, 0), 'FM999,999,999,990.##');
BEGIN
  IF v_purpose = 'instant_market_request' THEN
    NEW.title_ar := 'طلب عقاري فوري — ' || v_amount || ' ' || chr(65020);
    NEW.title_en := 'Instant property request — ' || v_amount || ' SAR';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_normalize_billing_display_copy
  ON public.billing_transactions;
CREATE TRIGGER tr_normalize_billing_display_copy
  BEFORE INSERT OR UPDATE OF purpose, amount, title_ar, title_en
  ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.normalize_billing_display_copy();

UPDATE public.billing_transactions
SET title_ar = 'طلب عقاري فوري — ' ||
    to_char(coalesce(amount, 0), 'FM999,999,999,990.##') || ' ' || chr(65020),
    title_en = 'Instant property request — ' ||
    to_char(coalesce(amount, 0), 'FM999,999,999,990.##') || ' SAR'
WHERE lower(trim(coalesce(purpose, ''))) = 'instant_market_request';

COMMIT;
