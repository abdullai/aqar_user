-- إدراج/تحديث طلب عقاري للمستخدم الحالي + قراءة صفوفه (مسودة أو منشور).
-- سبب الخطأ الشائع: سياسة SELECT العامة لا تغطي المسودات، أو INSERT غير ممنوح،
-- أو requester_id لا يساوي auth.uid() عند WITH CHECK.

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.market_property_requests
  TO authenticated;

DROP POLICY IF EXISTS market_property_requests_insert_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_insert_own
  ON public.market_property_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS market_property_requests_update_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_update_own
  ON public.market_property_requests
  FOR UPDATE
  TO authenticated
  USING (requester_id = auth.uid())
  WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS market_property_requests_delete_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_delete_own
  ON public.market_property_requests
  FOR DELETE
  TO authenticated
  USING (requester_id = auth.uid());

DROP POLICY IF EXISTS market_property_requests_select_own
  ON public.market_property_requests;
CREATE POLICY market_property_requests_select_own
  ON public.market_property_requests
  FOR SELECT
  TO authenticated
  USING (requester_id = auth.uid());

COMMENT ON POLICY market_property_requests_insert_own
  ON public.market_property_requests IS
  'صاحب الحساب يدرج طلبه فقط (requester_id = auth.uid()).';
