-- إخفاء سجل الرصيد الفوري للمستخدم دون حذف السجل المالي أو بيانات الاسترداد.

BEGIN;

ALTER TABLE public.market_request_instant_credits
  ADD COLUMN IF NOT EXISTS hidden_from_user boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_instant_credits_hidden_user
  ON public.market_request_instant_credits (user_id, hidden_from_user, created_at DESC);

DROP POLICY IF EXISTS market_request_instant_credits_select_own
  ON public.market_request_instant_credits;
CREATE POLICY market_request_instant_credits_select_own
  ON public.market_request_instant_credits FOR SELECT TO authenticated
  USING (user_id = auth.uid() AND hidden_from_user = false);

CREATE OR REPLACE FUNCTION public.billing_hide_own_instant_credit(p_id uuid)
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

  UPDATE public.market_request_instant_credits
     SET hidden_from_user = true
   WHERE id = p_id
     AND user_id = auth.uid();
  GET DIAGNOSTICS n = ROW_COUNT;

  IF n = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.billing_hide_own_instant_credit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.billing_hide_own_instant_credit(uuid) TO authenticated;

COMMIT;
