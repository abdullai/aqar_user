-- السماح للمستخدم بحذف فواتيره الخاصة من سجل المدفوعات.
BEGIN;

DROP POLICY IF EXISTS billing_transactions_delete_own ON public.billing_transactions;
CREATE POLICY billing_transactions_delete_own ON public.billing_transactions
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

COMMIT;
