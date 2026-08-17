-- =============================================================================
-- إصلاح RLS لـ listing_permits: السماح للمسوّق المختار بإدراج/تحديث التصاريح
-- =============================================================================
-- السبب من شاشة المستخدم:
--   PostgrestException(message: new row violates row-level security policy
--   for table "listing_permits", code: 42501)
--
-- الحل:
--   • التأكد من تفعيل RLS.
--   • سياسات INSERT/UPDATE/SELECT للمسوّق المختار في طلب الإدراج
--     (selected_marketer_id) وكذلك مالك الطلب (للقراءة).
--   • SELECT لمالك الطلب (owner_id) ولـ marketer_id نفسه.
-- =============================================================================

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.listing_permits') IS NULL THEN
    RAISE NOTICE 'listing_permits not present — skipping policies migration';
    RETURN;
  END IF;

  -- (1) تفعيل RLS
  EXECUTE 'ALTER TABLE public.listing_permits ENABLE ROW LEVEL SECURITY';

  -- (2) إسقاط السياسات القديمة المتشابهة الأسماء (idempotent)
  PERFORM 1;
  EXECUTE 'DROP POLICY IF EXISTS lp_marketer_select ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS lp_owner_select ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS lp_marketer_insert ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS lp_marketer_update ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS lp_owner_update ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS listing_permits_select_marketer ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS listing_permits_select_owner ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS listing_permits_insert_marketer ON public.listing_permits';
  EXECUTE 'DROP POLICY IF EXISTS listing_permits_update_marketer ON public.listing_permits';

  -- (3) قراءة: المسوّق نفسه أو مالك الطلب
  EXECUTE $POLICY$
    CREATE POLICY listing_permits_select_marketer ON public.listing_permits
    FOR SELECT
    TO authenticated
    USING (marketer_id = auth.uid())
  $POLICY$;

  EXECUTE $POLICY$
    CREATE POLICY listing_permits_select_owner ON public.listing_permits
    FOR SELECT
    TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.listing_requests lr
        WHERE lr.id = listing_permits.request_id
          AND lr.owner_id = auth.uid()
      )
    )
  $POLICY$;

  -- (4) إدراج: المسوّق المختار في الطلب — أو مسوّق سبق وأن قُبِل عرضه
  --     (نتساهل ما دام هو المختار لتفادي حالات فقد الحقل في عقود قديمة)
  EXECUTE $POLICY$
    CREATE POLICY listing_permits_insert_marketer ON public.listing_permits
    FOR INSERT
    TO authenticated
    WITH CHECK (
      marketer_id = auth.uid()
      AND EXISTS (
        SELECT 1 FROM public.listing_requests lr
        WHERE lr.id = listing_permits.request_id
          AND (
            lr.selected_marketer_id = auth.uid()
            OR EXISTS (
              SELECT 1 FROM public.listing_offers lo
              WHERE lo.request_id = lr.id
                AND lo.marketer_id = auth.uid()
                AND lower(coalesce(lo.status::text,'')) IN ('accepted','contracted','signed')
            )
          )
      )
    )
  $POLICY$;

  -- (5) تحديث: المسوّق صاحب التصريح
  EXECUTE $POLICY$
    CREATE POLICY listing_permits_update_marketer ON public.listing_permits
    FOR UPDATE
    TO authenticated
    USING (marketer_id = auth.uid())
    WITH CHECK (marketer_id = auth.uid())
  $POLICY$;

END $$;

COMMIT;

-- =============================================================================
-- اختبار سريع (يُشغَّل من عميل authenticated):
--   INSERT INTO public.listing_permits (request_id, marketer_id, status, created_at)
--   VALUES ('<request-uuid>', auth.uid(), 'submitted', now());
-- يجب أن ينجح فقط إذا كان auth.uid() هو selected_marketer_id لذلك الطلب
-- أو لديه عرض مقبول/متعاقد عليه.
-- =============================================================================
